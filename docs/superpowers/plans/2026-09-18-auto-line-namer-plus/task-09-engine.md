# Task 9: engine

**Files:**
- Create: `res/scripts/anujctrl/alnp/engine.lua`
- Test: `test/test_engine.lua`

**Interfaces:**
- Consumes: `log` (C2), `settings` (C4), `classify` (C5), `tracker` (C7), `facts` (C8),
  `propose` (C9), `test/fake_game.lua` (its API is in
  `.superpowers/sdd/2026-09-18-auto-line-namer-plus/task-6-report.md`).
- Produces: contract C10. This is the **only** module allowed to call `api.cmd`.

Read spec §6 and §11. The engine runs on the game's engine thread: `tick` is called about five
times a second and must do a small, bounded amount of work each time.

## Implementation (write this; adjust only if a test proves it wrong)

```lua
-- Engine-thread loop: looks at a few lines per tick, and renames a line only when it changed,
-- has settled, and tracker.decide says the mod may touch it. The only module that sends commands.
local log = require "anujctrl/alnp/log"
local settings = require "anujctrl/alnp/settings"
local classify = require "anujctrl/alnp/classify"
local tracker = require "anujctrl/alnp/tracker"
local propose = require "anujctrl/alnp/propose"
local facts = require "anujctrl/alnp/facts"

local engine = {}

local state          -- { settings = tbl, records = { [lineId] = record }, version = n }  (saved)
local runtime = {}   -- [lineId] = { signature = s, changedAt = seconds or nil }          (not saved)
local queue, cursor = {}, 0
local defaultWords   -- cache, cleared whenever a setting changes

local function userDefaults()
    local ok, overrides = pcall(require, "anujctrl/alnp/user_defaults")
    if ok and type(overrides) == "table" then return overrides end
    return nil
end

local function touch() state.version = (state.version or 0) + 1 end

-- saved may be nil (new game) or whatever save() returned, after a trip through the save file.
function engine.load(saved)
    saved = type(saved) == "table" and saved or {}
    state = { settings = settings.merge(userDefaults(), saved.settings), records = {}, version = saved.version or 0 }
    for lineId, record in pairs(type(saved.records) == "table" and saved.records or {}) do
        local id = tonumber(lineId) -- keys may come back from the save file as strings
        if id and type(record) == "table" then
            state.records[id] = {
                lastAssigned = type(record.lastAssigned) == "string" and record.lastAssigned or nil,
                locked = (record.locked == "player" or record.locked == "edited") and record.locked or nil,
                number = tonumber(record.number),
                numberKey = type(record.numberKey) == "string" and record.numberKey or nil,
            }
        end
    end
    runtime, queue, cursor, defaultWords = {}, {}, 0, nil
    log.setLevel(state.settings.log.level)
    facts.clearCache()
end

function engine.save()
    if not state then engine.load(nil) end
    return state
end

local function words()
    defaultWords = defaultWords or tracker.defaultWords(state.settings, _("Line"))
    return defaultWords
end

local function recordFor(lineId)
    state.records[lineId] = state.records[lineId] or tracker.newRecord()
    return state.records[lineId]
end

local function forget(lineId)
    if state.records[lineId] then touch() end
    state.records[lineId], runtime[lineId] = nil, nil
end

-- Every line gets looked at again after the settle delay (a pattern or label changed).
local function rescan(now)
    for __, entry in pairs(runtime) do entry.changedAt = now end
end

-- Give the line the name propose.name says it should have. The record is updated even when the
-- name is already right, because from now on the mod owns that name.
local function rename(lineId, lineFacts)
    local record = recordFor(lineId)
    local name, n, key = propose.name(lineFacts, record, state.settings, propose.takenByKey(state.records, lineId))
    if not name then return end
    record.lastAssigned, record.number, record.numberKey = name, n, key
    if record.locked == "edited" then record.locked = nil end
    touch()
    if name ~= lineFacts.name then
        api.cmd.sendCommand(api.cmd.make.setName(lineId, name))
        log.info(('renamed line %d: "%s" -> "%s"'):format(lineId, lineFacts.name, name))
    end
end

local function consider(lineId)
    local lineFacts = facts.forLine(lineId, state.settings)
    if not lineFacts then return forget(lineId) end
    local kind = classify.kind(lineFacts)
    local kindSettings = state.settings.kinds[kind]
    local action = tracker.decide(state.records[lineId], lineFacts.name,
        kindSettings and kindSettings.autoRename, state.settings, words())
    if action == "rename" then
        rename(lineId, lineFacts)
    elseif action == "autoLock" then
        local record = recordFor(lineId)
        if record.locked ~= "edited" then
            record.locked = "edited"
            touch()
        end
    end
end

local function visit(lineId, now)
    local signature = facts.signature(lineId)
    if not signature then return forget(lineId) end
    local entry = runtime[lineId]
    if not entry then
        entry = { signature = signature, changedAt = now }
        runtime[lineId] = entry
    elseif entry.signature ~= signature then
        entry.signature, entry.changedAt = signature, now
    end
    if entry.changedAt and now - entry.changedAt >= state.settings.scan.settleSeconds then
        entry.changedAt = nil
        consider(lineId)
    end
end

local function refillQueue()
    queue, cursor = facts.playerLines(), 0
    local alive = {}
    for __, lineId in ipairs(queue) do alive[lineId] = true end
    for lineId in pairs(state.records) do if not alive[lineId] then forget(lineId) end end
    for lineId in pairs(runtime) do if not alive[lineId] then runtime[lineId] = nil end end
end

function engine.tick(now)
    if not state then engine.load(nil) end
    if not state.settings.enabled then return end
    for __ = 1, state.settings.scan.linesPerTick do
        if cursor >= #queue then
            refillQueue()
            if #queue == 0 then return end
        end
        cursor = cursor + 1
        visit(queue[cursor], now)
    end
end

local handlers = {}

function handlers.set(param, now)
    local ok, err = settings.set(state.settings, param.path, param.value)
    if not ok then return log.error("setting rejected: " .. tostring(err)) end
    if param.path == "log.level" then log.setLevel(param.value) end
    if param.path:find("^industry%.") then facts.clearCache() end
    defaultWords = nil
    rescan(now)
end

function handlers.lock(param, now)
    local lineId = tonumber(param.line)
    if not lineId then return end
    recordFor(lineId).locked = param.locked and "player" or nil
    if runtime[lineId] then runtime[lineId].changedAt = now end
end

-- The player ticked these rows in the Lines tab and pressed "Apply checked".
function handlers.apply(param)
    for __, item in ipairs(param.renames or {}) do
        local lineId, name = tonumber(item.line), item.name
        if lineId and type(name) == "string" and name:match("%S") and facts.signature(lineId) then
            local record = recordFor(lineId)
            record.lastAssigned, record.number, record.numberKey = name, tonumber(item.n), item.key
            if record.locked == "edited" then record.locked = nil end
            if name ~= facts.name(lineId) then
                api.cmd.sendCommand(api.cmd.make.setName(lineId, name))
                log.info(('renamed line %d to "%s" (applied from the Lines tab)'):format(lineId, name))
            end
        end
    end
end

-- "rename now" on one row: the player asked, so the tracker is not consulted.
function handlers.renameNow(param)
    local lineId = tonumber(param.line)
    local lineFacts = lineId and facts.forLine(lineId, state.settings)
    if lineFacts then rename(lineId, lineFacts) end
end

function handlers.preset(param, now)
    if settings.applyPreset(state.settings, param.key) then rescan(now) end
end

function handlers.resetSection(param, now)
    settings.resetSection(state.settings, param.section)
    defaultWords = nil
    facts.clearCache()
    log.setLevel(state.settings.log.level)
    rescan(now)
end

function handlers.resetAll(__, now)
    state.settings = settings.merge(userDefaults(), nil)
    defaultWords = nil
    facts.clearCache()
    log.setLevel(state.settings.log.level)
    rescan(now)
end

function handlers.apiCheck()
    for __, line in ipairs(facts.apiCheck(state.settings)) do log.info("api check: " .. line) end
end

function engine.handleEvent(name, param)
    if not state then engine.load(nil) end
    local handler = handlers[name]
    if not handler then return log.error("unknown event: " .. tostring(name)) end
    handler(type(param) == "table" and param or {}, os.time())
    touch()
end

return engine
```

Notes for you:
- After the engine renames a line, the line's signature changes (the name is part of it), so
  the line is considered once more after the settle delay; that pass proposes the same name and
  sends nothing. This is expected, and test 4 pins it.
- `state.version` lets the GUI thread notice that something changed without comparing tables.

## Tests (`test/test_engine.lua`)

Build worlds with `test/fake_game.lua`. It does not provide `api.cmd`; install this in your test
file after creating a world (a local helper, not a shared file):

```lua
local function installCmd(world)
    local sent = {}
    api.cmd = {
        make = { setName = function(id, name) return { id = id, name = name } end },
        sendCommand = function(cmd)
            sent[#sent + 1] = cmd
            world.renameLine(cmd.id, cmd.name) -- the game applies it
        end,
    }
    return sent
end
```

The module is cached by `require`, so start every test with `engine.load(nil)` (or a saved
table). Capture logs with `log.reset()` and a `log.sink` replacement where a test asserts on them.
Pass `now` to `tick` explicitly; for events, the engine reads `os.time()` itself, so use
`settleSeconds = 0` in tests that follow an event with a tick.

Required cases:
1. a new default-named bus line is renamed once the settle delay has passed: tick at `t=100`
   sends nothing; tick at `t=104` sends nothing; tick at `t=105` sends one `setName` with the
   proposed name; the record has `lastAssigned` set;
2. with 12 lines and `linesPerTick = 5`, one tick calls `facts.signature` for exactly 5 lines
   (wrap `facts.signature` to count), and three ticks have visited all 12;
3. a hand-named line is never renamed and its record becomes `locked = "edited"`;
4. after a rename, further ticks send no second command for that line;
5. changing a mod-named line's stops renames it again after the settle delay; while the stops
   keep changing every second, nothing is sent (the timer restarts);
6. `eligible.modAssigned = false`: the changed line from case 5 is left alone;
7. `kinds.bus.autoRename = false`: a default-named bus line is left alone;
8. `enabled = false`: `tick` sends nothing and does not call `facts.signature` at all;
9. a line named `r` is renamed even though it was `locked = "edited"`, and the lock clears;
10. a `lock` event sets `"player"` and the line is then left alone; unlocking makes it eligible again;
11. two lines between the same towns get `… ` and `… 2`; deleting the first and adding a third
    gives the third the freed number 1 (blank);
12. a removed line's record disappears after the queue refills;
13. a one-stop line is never renamed and never blanked;
14. `apply` renames exactly the listed lines, records ownership, skips a blank name and a
    vanished line, and sends nothing when the name already matches;
15. `renameNow` renames a player-locked, hand-named line; the player lock stays, an `edited` lock clears;
16. `set` with an invalid value logs an error and leaves the setting unchanged; a valid
    `patterns.default` change causes mod-named lines to be renamed to the new pattern;
17. `preset`, `resetSection` and `resetAll` change the settings as `settings.lua` defines;
    `resetAll` keeps `records`;
18. `save()` then `load(saved)` round-trips settings and records; string keys in `records`
    (`{ ["12"] = {...} }`) come back as number keys; a garbage `locked` value is dropped;
19. `state.version` increases after an event and after a rename, and not on an idle tick;
20. `apiCheck` logs one `api check:` line per report entry; an unknown event logs an error.

## Steps

- [ ] **Step 1:** write `test/test_engine.lua`.
- [ ] **Step 2:** run `lua5.4 test/run.lua test_engine` → fails to load.
- [ ] **Step 3:** write `engine.lua` from the listing.
- [ ] **Step 4:** run the same command → all pass. `luac -p` the module.
- [ ] **Step 5:** report (do not commit): files written, test count, anything in the listing you
  changed and why, any contract concern.
