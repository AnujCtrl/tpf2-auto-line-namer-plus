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
    engine.handleEvent("apply", { renames = {
        { line = 1, name = "Bus Springfield", n = 2, key = "k1" },
        { line = 2, name = "   ", n = 1, key = "k2" },
        { line = 3, name = "Ghost Renamed", n = 1, key = "k3" },
        { line = 4, name = "Already Right", n = 3, key = "k4" },
    } })
    local records = engine.save().records
    eq(records[1], { lastAssigned = "Bus Springfield", number = 2, numberKey = "k1" })
    eq(records[2], nil)
    eq(records[3], nil)
    eq(records[4], { lastAssigned = "Already Right", number = 3, numberKey = "k4" })
    eq(#sent, 1)
    eq(sent[1], { id = 1, name = "Bus Springfield" })
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
