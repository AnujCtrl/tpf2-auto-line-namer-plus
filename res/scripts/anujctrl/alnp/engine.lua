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
local pending, pendingCursor = {}, 0 -- apply items waiting to be renamed, drained a few per tick
local applyOne                       -- defined with the apply handler, used by engine.tick
local defaultWords   -- cache, cleared whenever a setting changes

-- A mod folder with no user_defaults.lua is perfectly normal, so a "not found" is silent. A file
-- that IS there and fails to load (a syntax error the player introduced) is not: without a word
-- in the log their overrides would simply vanish, with nothing to point at.
local USER_DEFAULTS = "anujctrl/alnp/user_defaults"

local function userDefaults()
    local ok, overrides = pcall(require, USER_DEFAULTS)
    if ok then
        if type(overrides) == "table" then return overrides end
        return nil
    end
    local message = tostring(overrides)
    if not message:find("module '" .. USER_DEFAULTS .. "' not found", 1, true) then
        log.error("user_defaults.lua could not be loaded, ignoring it: " .. message)
    end
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
    pending, pendingCursor = {}, 0
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
    local existing = state.records[lineId]
    local name, n, key = propose.name(lineFacts, existing, state.settings, propose.takenByKey(state.records, lineId))
    if not name then return end
    local record = recordFor(lineId)
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

-- Renames the player queued with "Apply checked", at most scan.linesPerTick of them, before the
-- normal scan gets a turn. A tick that applied something does nothing else: the budget is what
-- keeps one huge batch from stalling the game, so it must not be spent twice in the same tick.
local function drainPending()
    local budget = state.settings.scan.linesPerTick
    local done = 0
    while done < budget and pendingCursor < #pending do
        pendingCursor = pendingCursor + 1
        done = done + 1
        applyOne(pending[pendingCursor])
    end
    if pendingCursor >= #pending then pending, pendingCursor = {}, 0 end
    return done
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
    if drainPending() > 0 then return end
    local visits = 0
    for __ = 1, state.settings.scan.linesPerTick do
        if cursor >= #queue then
            refillQueue()
            if #queue == 0 then return end
        end
        if visits >= #queue then return end
        cursor = cursor + 1
        visits = visits + 1
        visit(queue[cursor], now)
    end
end

local handlers = {}

function handlers.set(param, now)
    if type(param.path) ~= "string" then return log.error("setting rejected: no path") end
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

-- The player ticked these rows in the Lines tab and pressed "Apply checked". Each item carries
-- `from`: the name the Lines tab saw when it built that row's proposal. The engine is the
-- authority on whether that is still true -- if the line has been renamed since (by the player,
-- by another mod, by an earlier apply), the item is dropped rather than overwriting a name the
-- player never offered up. The GUI unticks such rows too, but this check is what guarantees it.
-- Forward-declared above so engine.tick can drain the queue; defined here, next to its handler.
function applyOne(item)
    local lineId, name = tonumber(item.line), item.name
    if not (lineId and type(name) == "string" and name:match("%S") and facts.signature(lineId)) then return end
    if type(item.from) ~= "string" or facts.name(lineId) ~= item.from then
        return log.info(("apply skipped for line %d: its name changed since the preview"):format(lineId))
    end
    local record = recordFor(lineId)
    record.lastAssigned, record.number, record.numberKey = name, tonumber(item.n), item.key
    if record.locked == "edited" then record.locked = nil end
    if name ~= facts.name(lineId) then
        api.cmd.sendCommand(api.cmd.make.setName(lineId, name))
        log.info(('renamed line %d to "%s" (applied from the Lines tab)'):format(lineId, name))
    end
end

-- Queue only: engine.tick applies them a few per tick. The `from` check in applyOne happens at
-- the moment each item is applied, so a line the player renames while its item waits is skipped.
function handlers.apply(param)
    for __, item in ipairs(param.renames or {}) do
        if type(item) == "table" then pending[#pending + 1] = item end
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

-- "Reset section" restores what a brand-new save would start with for those rows -- the shipped
-- defaults with user_defaults.lua laid over them -- exactly as "Reset everything" does below, so
-- the two buttons can never disagree about what "default" means.
function handlers.resetSection(param, now)
    local fresh = settings.merge(userDefaults(), nil)
    for __, row in ipairs(settings.rowsIn(param.section)) do
        settings.set(state.settings, row.path, settings.get(fresh, row.path))
    end
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
