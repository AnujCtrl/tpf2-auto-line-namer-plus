-- Engine cases 14-20 (task-09-engine.md "Required cases"): the event handlers apply/renameNow/
-- set/preset/resetSection/resetAll, the save/load round trip, version bookkeeping and apiCheck.
local H = require("engine_helpers")
local eq = H.fake.eq
local t = {}

function t.case14_apply_renames_listed_lines_and_skips_blank_or_vanished()
    local world = H.world({
        [1] = H.busLine("Line 1"),
        [2] = H.busLine("Blanky"),
        [3] = H.busLine("Ghost"),
        [4] = H.busLine("Already Right"),
    })
    world.removeLine(3)
    local sent = H.installCmd(world)
    local engine = H.freshEngine(H.saved({}))
    -- `from` is the name the Lines tab saw at preview time; here every line still has it (A1).
    engine.handleEvent("apply", { renames = {
        { line = 1, name = "Bus Springfield", from = "Line 1", n = 2, key = "k1" },
        { line = 2, name = "   ", from = "Blanky", n = 1, key = "k2" },
        { line = 3, name = "Ghost Renamed", from = "Ghost", n = 1, key = "k3" },
        { line = 4, name = "Already Right", from = "Already Right", n = 3, key = "k4" },
    } })
    -- Y6: the handler only queues; one tick drains all four (scan.linesPerTick defaults to 5).
    engine.tick(100)
    local records = engine.save().records
    eq(records[1], { lastAssigned = "Bus Springfield", number = 2, numberKey = "k1" })
    eq(records[2], nil)
    eq(records[3], nil)
    eq(records[4], { lastAssigned = "Already Right", number = 3, numberKey = "k4" })
    eq(#sent, 1)
    eq(sent[1], { id = 1, name = "Bus Springfield" })
end

-- A1: the engine is the authority. Every apply item carries `from`, the name the Lines tab saw
-- when it built the preview. If the line's name has moved on since (the player renamed it by
-- hand), the item is dropped: no command, no record change, one log line.
function t.case14b_apply_skips_items_whose_name_changed_since_the_preview()
    local world = H.world({ [1] = H.busLine("Line 1"), [2] = H.busLine("Line 2") })
    local sent = H.installCmd(world)
    local engine, logs = H.freshEngine(H.saved({}))
    world.renameLine(1, "Airport Express") -- the player renamed it after the preview
    engine.handleEvent("apply", { renames = {
        { line = 1, name = "Bus Springfield", from = "Line 1", n = 1, key = "k1" },
        { line = 2, name = "Bus Shelbyville", from = "Line 2", n = 2, key = "k2" },
    } })
    engine.tick(100) -- Y6: the handler queues, the tick applies
    eq(#sent, 1, "only the line whose name is unchanged may be renamed")
    eq(sent[1], { id = 2, name = "Bus Shelbyville" })
    eq(engine.save().records[1], nil, "the skipped line's record must be untouched")
    local skipped = false
    for __, line in ipairs(logs) do
        if line:find("apply skipped for line 1", 1, true) then skipped = true end
    end
    eq(skipped, true, "the skip must be logged")
end

-- An item with no `from` at all (an old GUI, or a hand-made event) is never trusted.
function t.case14c_apply_without_a_from_field_sends_nothing()
    local world = H.world({ [1] = H.busLine("Line 1") })
    local sent = H.installCmd(world)
    local engine = H.freshEngine(H.saved({}))
    engine.handleEvent("apply", { renames = { { line = 1, name = "Bus Springfield", n = 1, key = "k1" } } })
    engine.tick(100) -- Y6: the handler queues, the tick applies
    eq(#sent, 0, "an item with no `from` must be dropped")
    eq(engine.save().records[1], nil)
end

-- Y6: "Apply checked" used to rename the whole batch inside the event handler, on one tick. The
-- items are queued instead and drained at most scan.linesPerTick per tick, so a 200-row apply
-- cannot stall the game the way one huge tick would.
local function twelveLines()
    local lines = {}
    for i = 1, 12 do lines[i] = H.busLine("Line " .. i) end
    return lines
end

local function twelveItems()
    local items = {}
    for i = 1, 12 do
        items[i] = { line = i, name = "Renamed " .. i, from = "Line " .. i, n = i, key = "k" .. i }
    end
    return items
end

function t.case14d_a_batch_of_twelve_is_applied_five_per_tick()
    local world = H.world(twelveLines())
    local sent = H.installCmd(world)
    local engine = H.freshEngine(H.saved({ ["scan.linesPerTick"] = 5 }))
    engine.handleEvent("apply", { renames = twelveItems() })
    eq(#sent, 0, "the handler itself must rename nothing")
    engine.tick(100)
    eq(#sent, 5, "first tick")
    engine.tick(101)
    eq(#sent, 10, "second tick")
    engine.tick(102)
    eq(#sent, 12, "third tick drains the rest")
    eq(sent[12], { id = 12, name = "Renamed 12" })
end

function t.case14e_a_queued_item_is_skipped_when_the_line_is_renamed_while_it_waits()
    local world = H.world(twelveLines())
    local sent = H.installCmd(world)
    local engine, logs = H.freshEngine(H.saved({ ["scan.linesPerTick"] = 5 }))
    engine.handleEvent("apply", { renames = twelveItems() })
    engine.tick(100)
    world.renameLine(12, "Player Named It") -- while item 12 is still queued
    engine.tick(101)
    engine.tick(102)
    eq(#sent, 11, "the hand-renamed line must not be overwritten")
    eq(engine.save().records[12], nil, "and its record must be untouched")
    local skipped = false
    for __, line in ipairs(logs) do
        if line:find("apply skipped for line 12", 1, true) then skipped = true end
    end
    eq(skipped, true, "the skip must be logged")
end

-- The master switch turns AUTOMATIC renaming off. "Apply checked" is the player asking explicitly,
-- so a queued apply must still drain when the switch is off (the help text and the Lines tab both
-- promise this); only the scan is skipped.
function t.case14f_a_queued_apply_still_drains_when_the_master_switch_is_off()
    local world = H.world({ [1] = H.busLine("Line 1"), [2] = H.busLine("Line 2") })
    local sent = H.installCmd(world)
    local engine = H.freshEngine(H.saved({ enabled = false }))
    engine.handleEvent("apply", { renames = { { line = 1, name = "Chosen By Hand", from = "Line 1" } } })
    engine.tick(100)
    eq(#sent, 1, "the explicit apply must be sent even though automatic renaming is off")
    eq(sent[1].name, "Chosen By Hand")
    engine.tick(101)
    engine.tick(110)
    eq(#sent, 1, "and with the switch off nothing is renamed automatically: line 2 keeps its default name")
end

function t.case15_rename_now_ignores_lock_but_only_clears_edited()
    local world = H.world({
        [1] = H.busLine("My Custom Name"),
        [2] = H.busLine("My Other Name"),
    })
    local sent = H.installCmd(world)
    local engine = H.freshEngine(H.saved({}, { [1] = { locked = "player" }, [2] = { locked = "edited" } }))
    engine.handleEvent("renameNow", { line = 1 })
    engine.handleEvent("renameNow", { line = 2 })
    local records = engine.save().records
    eq(records[1].locked, "player")
    eq(records[2].locked, nil)
    eq(#sent, 2)
end

function t.case16_set_validates_and_valid_change_triggers_rerename()
    local world = H.world({ [1] = H.busLine("Line 1") })
    local sent = H.installCmd(world)
    local engine, logs = H.freshEngine(H.saved({ ["scan.settleSeconds"] = 0 }))
    engine.tick(os.time() + 1)
    eq(#sent, 1)
    engine.handleEvent("set", { path = "patterns.default", value = "" })
    eq(engine.save().settings.patterns.default, "{type} {towns}[ {n}]")
    local rejected = false
    for __, line in ipairs(logs) do
        if line:find("setting rejected", 1, true) then rejected = true end
    end
    eq(rejected, true)
    engine.handleEvent("set", { path = "patterns.default", value = "{type} Local" })
    eq(engine.save().settings.patterns.default, "{type} Local")
    engine.tick(os.time() + 5)
    eq(sent[2].name, "Bus Local")
end

-- A bad "set" event (missing or non-string path) must not raise, and must leave settings alone.
function t.case16b_set_with_bad_path_does_not_raise()
    local world = H.world({ [1] = H.busLine("Line 1") })
    H.installCmd(world)
    local engine, logs = H.freshEngine(H.saved({}))
    local settings = require("anujctrl/alnp/settings")
    local expected = settings.defaults()

    engine.handleEvent("set", {})
    local rejected1 = false
    for __, line in ipairs(logs) do
        if line:find("setting rejected", 1, true) then rejected1 = true end
    end
    eq(rejected1, true)
    eq(engine.save().settings, expected)

    -- Same message as above, so log.error's consecutive-duplicate dedup swallows a second line;
    -- what matters here is that this call does not raise and settings stay untouched.
    engine.handleEvent("set", { path = 42, value = 1 })
    local rejected2 = false
    for __, line in ipairs(logs) do
        if line:find("setting rejected", 1, true) then rejected2 = true end
    end
    eq(rejected2, true)
    eq(engine.save().settings, expected)
end

function t.case17_preset_resetSection_resetAll_change_settings_and_resetAll_keeps_records()
    local world = H.world({ [1] = H.busLine("Line 1") })
    H.installCmd(world)
    local engine = H.freshEngine(H.saved({ ["scan.settleSeconds"] = 0 }))
    engine.tick(os.time() + 1)
    local before = engine.save().records[1].lastAssigned
    engine.handleEvent("preset", { key = "upstream" })
    local afterPreset = engine.save().settings
    eq(afterPreset.patterns.default, "{type} {cargo}-{towns:3}-{scope}-{n}")
    eq(afterPreset.patterns.trainCargo, "")
    engine.handleEvent("set", { path = "enabled", value = false })
    eq(engine.save().settings.enabled, false)
    engine.handleEvent("resetSection", { section = "general" })
    eq(engine.save().settings.enabled, true)
    engine.handleEvent("resetAll", {})
    eq(engine.save().settings.patterns.default, "{type} {towns}[ {n}]")
    eq(engine.save().records[1].lastAssigned, before)
end

-- A5. "Reset section" and "Reset everything" must restore the same thing: what a brand-new save
-- would start with, i.e. the shipped defaults with user_defaults.lua laid over them.
local function withUserDefaults(overrides, fn)
    local key = "anujctrl/alnp/user_defaults"
    local real = package.loaded[key]
    package.loaded[key] = overrides
    local ok, err = pcall(fn)
    package.loaded[key] = real
    if not ok then error(err, 0) end
end

function t.case17b_resetSection_restores_the_user_defaults_not_the_shipped_ones()
    local world = H.world({ [1] = H.busLine("Line 1") })
    H.installCmd(world)
    withUserDefaults({ lock = { prefix = "!" }, reload = { names = "rr" } }, function()
        local engine = H.freshEngine(nil) -- a new save: load() reads user_defaults itself
        eq(engine.save().settings.lock.prefix, "!", "a new save starts from user_defaults.lua")

        engine.handleEvent("set", { path = "lock.prefix", value = "#" })
        engine.handleEvent("set", { path = "reload.names", value = "zzz" })
        engine.handleEvent("resetSection", { section = "general" })
        eq(engine.save().settings.lock.prefix, "!", "resetSection restores the user default, not \"\"")
        eq(engine.save().settings.reload.names, "rr")

        engine.handleEvent("set", { path = "lock.prefix", value = "#" })
        engine.handleEvent("resetAll", {})
        eq(engine.save().settings.lock.prefix, "!", "resetAll restores the same thing")
    end)
end

-- A6. A mod folder with no user_defaults.lua at all is normal and stays silent; a file that IS
-- there but does not load (a syntax error the player introduced) must say so, or the player's
-- overrides vanish with no explanation at all.
local UD_KEY = "anujctrl/alnp/user_defaults"

local function withoutUserDefaultsModule(replacement, fn)
    local realLoaded, realPreload, realPath = package.loaded[UD_KEY], package.preload[UD_KEY], package.path
    package.loaded[UD_KEY], package.preload[UD_KEY] = nil, replacement
    package.path = "./no-such-directory/?.lua"
    local ok, err = pcall(fn)
    package.loaded[UD_KEY], package.preload[UD_KEY], package.path = realLoaded, realPreload, realPath
    if not ok then error(err, 0) end
end

local function linesMentioning(logs, needle)
    local found = 0
    for __, line in ipairs(logs) do
        if line:find(needle, 1, true) then found = found + 1 end
    end
    return found
end

function t.case21_a_missing_user_defaults_file_is_silent()
    H.world({ [1] = H.busLine("Line 1") })
    withoutUserDefaultsModule(nil, function()
        local engine, logs = H.freshEngine(nil)
        eq(linesMentioning(logs, "user_defaults"), 0, "a missing user_defaults.lua must not be reported")
        eq(engine.save().settings.enabled, true, "and the shipped defaults are used")
    end)
end

function t.case22_a_broken_user_defaults_file_is_logged_once()
    H.world({ [1] = H.busLine("Line 1") })
    local broken = function() error("user_defaults.lua:19: unexpected symbol near ','", 0) end
    withoutUserDefaultsModule(broken, function()
        local engine, logs = H.freshEngine(nil)
        eq(linesMentioning(logs, "user_defaults"), 1, "a broken user_defaults.lua is reported once")
        eq(linesMentioning(logs, "unexpected symbol"), 1, "and the report carries the real message")
        eq(engine.save().settings.enabled, true, "the mod still starts, on the shipped defaults")
    end)
end

function t.case18_save_load_round_trip_normalizes_records()
    local engine = H.freshEngine(H.saved({ ["log.level"] = "debug" }))
    local saved1 = engine.save()
    eq(saved1.settings.log.level, "debug")
    engine.load({
        settings = saved1.settings,
        version = 7,
        records = { ["12"] = { lastAssigned = "X", locked = "banana", number = "3", numberKey = "k" } },
    })
    local saved2 = engine.save()
    eq(saved2.records[12], { lastAssigned = "X", number = 3, numberKey = "k" })
    eq(saved2.records["12"], nil)
    eq(saved2.version, 7)
    eq(saved2.settings.log.level, "debug")
end

function t.case19_version_increases_on_event_and_rename_not_on_idle_tick()
    local world = H.world({ [1] = H.busLine("Line 1") })
    H.installCmd(world)
    local engine = H.freshEngine(H.saved({ ["scan.settleSeconds"] = 0 }))
    local v0 = engine.save().version
    engine.handleEvent("lock", { line = 1, locked = false })
    local v1 = engine.save().version
    eq(v1 > v0, true)
    engine.tick(os.time() + 1) -- settles and renames line 1
    local v2 = engine.save().version
    eq(v2 > v1, true)
    -- The rename itself changes the signature (the name changed), and a line is now visited at
    -- most once per tick, so the reconfirm (same name, no new command) lands on the next tick.
    engine.tick(os.time() + 2)
    local v3 = engine.save().version
    eq(v3 > v2, true)
    engine.tick(os.time() + 5) -- nothing left to change: idle
    eq(engine.save().version, v3)
end

function t.case20_apiCheck_logs_one_line_per_entry_and_unknown_event_errors()
    local world = H.world({ [1] = H.busLine("Line 1") })
    H.installCmd(world)
    local engine, logs = H.freshEngine(H.saved({}))
    engine.handleEvent("apiCheck", {})
    local checkLines = {}
    for __, line in ipairs(logs) do
        if line:find("^aln_plus: api check: ") then checkLines[#checkLines + 1] = line end
    end
    eq(#checkLines, 2)
    eq(checkLines[1], 'aln_plus: api check: translated default word: _("Line") = "Line"')
    eq(checkLines[2], "aln_plus: api check: no cargo lines found; build one and run the check again")
    engine.handleEvent("bogusEvent", {})
    local sawUnknown = false
    for __, line in ipairs(logs) do
        if line == "aln_plus: unknown event: bogusEvent" then sawUnknown = true end
    end
    eq(sawUnknown, true)
end

return t
