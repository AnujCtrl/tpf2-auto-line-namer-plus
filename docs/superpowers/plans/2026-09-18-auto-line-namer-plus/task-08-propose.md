# Task 8: propose, and the GUI field-sync helper

**Files:**
- Create: `res/scripts/anujctrl/alnp/propose.lua`
- Create: `res/scripts/anujctrl/alnp/gui/sync.lua`
- Test: `test/test_propose.lua`, `test/test_sync.lua`

**Interfaces:**
- Consumes: `classify` (C5), `naming` (C6), `settings` (C4), record shape (C7), facts table (C3).
- Produces: contract C9, and `sync` below. Both are pure Lua: no `api`, no `game`, no `_()`.

## Part A — `propose.lua`

The engine and the Lines tab must always agree on what a line would be called, so the
composition lives here once. Write this:

```lua
-- What a line would be called right now. Shared by the engine (which renames) and the Lines tab
-- (which previews), so the two can never disagree.
local classify = require "anujctrl/alnp/classify"
local naming = require "anujctrl/alnp/naming"
local settings = require "anujctrl/alnp/settings"

local propose = {}

-- Lines that share a key share one number sequence (spec §7.2).
local function numberKeyFor(scope, kind, baseName)
    if scope == "global" then return "*" end
    if scope == "kind" then return "kind:" .. kind end
    return "name:" .. baseName
end

-- { [numberKey] = { [n] = true } } for every line except one.
function propose.takenByKey(records, exceptLineId)
    local taken = {}
    for lineId, record in pairs(records or {}) do
        if lineId ~= exceptLineId and record.numberKey and record.number then
            taken[record.numberKey] = taken[record.numberKey] or {}
            taken[record.numberKey][record.number] = true
        end
    end
    return taken
end

-- Returns nil when the line should be left alone (too few stops, or a blank result);
-- otherwise name, n, numberKey (n and numberKey are nil when the pattern has no number token).
function propose.name(facts, record, tbl, takenByKey)
    if #(facts.stops or {}) < tbl.minStops then return nil end
    local kind = classify.kind(facts)
    local ctx = { settings = tbl, kind = kind, scope = classify.scope(facts, tbl) }
    local pattern = settings.patternFor(tbl, kind)

    local n, key
    if naming.usesNumber(pattern) then
        local baseName = naming.render(pattern, facts, ctx) -- ctx.n is nil, so the number renders empty
        key = numberKeyFor(tbl.number.scope, kind, baseName)
        local current = record and record.numberKey == key and record.number or nil
        n = naming.pickNumber(current, (takenByKey or {})[key] or {})
        ctx.n = n
    end

    local name = naming.render(pattern, facts, ctx)
    if name == "" then return nil end
    return name, n, key
end

return propose
```

Tests (`test/test_propose.lua`) — use `settings.defaults()` for `tbl` and `naming.sampleFacts(kind)`
or hand-built facts:

1. a two-stop bus line with default settings → `"Bus <TownA> – <TownB>"`, `n == 1`, key `"name:Bus <TownA> – <TownB>"`;
2. same facts, `takenByKey = { [thatKey] = { [1] = true } }` → name ends in `" 2"`, `n == 2`;
3. a record holding `{ number = 3, numberKey = thatKey }` keeps 3 even when 1 and 2 are free;
4. a record whose `numberKey` differs (the base name changed) is renumbered to the lowest free;
5. `number.scope = "kind"` → key `"kind:bus"`; `"global"` → key `"*"`;
6. a pattern without `{n}` → `n == nil`, `key == nil`;
7. one stop with `minStops = 2` → nil; `minStops = 1` → a name;
8. a pattern that renders blank (e.g. `"[{via}]"` on a two-town line) → nil;
9. a cargo train uses the `trainCargo` pattern; after `settings.set(tbl, "patterns.trainCargo", "")` it uses the default;
10. `takenByKey(records, 7)` skips line 7, skips records without a number, and groups by key.

## Part B — `gui/sync.lua`

The GUI thread receives the engine's state many times a second. If a refresh wrote that state
into a text field while the player is typing, fast typing would be eaten: the field shows `ab`,
the engine has only acknowledged `a`, and the refresh would write `a` back. This helper decides
when a refresh may overwrite a widget.

```lua
local sync = require "anujctrl/alnp/gui/sync"
local s = sync.new(clock)        -- clock: function returning seconds; defaults to os.time
s:sent(path, value)              -- the widget just sent this value to the engine
s:shouldApply(path, stateValue)  -- may a refresh overwrite the widget with stateValue?
```

Rules for `shouldApply`:
- nothing pending for `path` → `true`;
- pending, and `stateValue` equals the pending value → clear the pending entry, return `false`
  (the engine caught up; the widget already shows it);
- pending, values differ, and less than `sync.TIMEOUT` (2) seconds since `sent` → `false`
  (the engine has not caught up yet);
- pending, values differ, and the timeout has passed → clear the pending entry, return `true`
  (the engine rejected the value, so show the real one).

Tests (`test/test_sync.lua`), with a fake clock you advance by hand: each of the four rules;
fast typing (`sent a`, `sent ab`, state `a` → false, state `ab` → false, then state `x` → true);
two paths are independent; two `sync.new` instances are independent.

## Steps

- [ ] **Step 1:** write both test files.
- [ ] **Step 2:** run `lua5.4 test/run.lua test_propose test_sync` → both fail to load.
- [ ] **Step 3:** write `propose.lua` from the listing and `gui/sync.lua` from the rules.
- [ ] **Step 4:** run the same command → all pass. `luac -p` both modules.
- [ ] **Step 5:** report (do not commit): files written, test count, any contract concern.
