-- Engine tests: scanning behaviour (settle delay, linesPerTick pacing, enabled switch,
-- eligibility/kind gates, and minStops). See engine-tests-instructions.md for the shared
-- fixtures (H.world, H.busLine, H.installCmd, H.saved, H.freshEngine, H.tickRange).
local H = require("engine_helpers")
local eq = H.fake.eq
local t = {}

function t.case01_new_default_named_bus_line_is_renamed_after_settle()
    local world = H.world({ [1] = H.busLine("Line 1") })
    local sent = H.installCmd(world)
    local engine = H.freshEngine(nil)
    H.tickRange(engine, 100, 104)
    eq(#sent, 0)
    H.tickRange(engine, 105, 105)
    eq(#sent, 1)
    eq(sent[1].id, 1)
    local saved = engine.save()
    eq(type(saved.records[1].lastAssigned), "string")
end

function t.case02_scan_visits_linesPerTick_per_tick_and_all_lines_within_three_ticks()
    local lines = {}
    for i = 1, 12 do lines[i] = H.busLine("Line " .. i) end
    local world = H.world(lines)
    H.installCmd(world)
    local engine = H.freshEngine(H.saved({ ["scan.linesPerTick"] = 5 }))

    local facts = require("anujctrl/alnp/facts")
    local orig = facts.signature
    local calls, visited = 0, {}
    facts.signature = function(id)
        calls = calls + 1
        visited[id] = true
        return orig(id)
    end
    local ok, err = pcall(function()
        engine.tick(100)
        eq(calls, 5)
        engine.tick(101)
        engine.tick(102)
        local count = 0
        for __ in pairs(visited) do count = count + 1 end
        eq(count, 12)
    end)
    facts.signature = orig
    if not ok then error(err, 0) end
end

-- With fewer lines than linesPerTick (the normal case early in a game), a tick must still
-- visit each line at most once, not wrap around and revisit it within the same tick.
function t.case02b_scan_visits_each_line_at_most_once_per_tick_when_fewer_than_linesPerTick()
    local lines = {}
    for i = 1, 3 do lines[i] = H.busLine("Line " .. i) end
    local world = H.world(lines)
    H.installCmd(world)
    local engine = H.freshEngine(H.saved({})) -- default scan.linesPerTick = 5

    local facts = require("anujctrl/alnp/facts")
    local orig = facts.signature
    local perLine = {}
    facts.signature = function(id)
        perLine[id] = (perLine[id] or 0) + 1
        return orig(id)
    end
    local ok, err = pcall(function()
        engine.tick(100)
        eq(perLine[1], 1)
        eq(perLine[2], 1)
        eq(perLine[3], 1)
    end)
    facts.signature = orig
    if not ok then error(err, 0) end
end

function t.case03_hand_named_line_is_never_renamed_and_becomes_edited_locked()
    local world = H.world({ [1] = H.busLine("My favourite line") })
    local sent = H.installCmd(world)
    local engine = H.freshEngine(nil)
    H.tickRange(engine, 100, 112)
    eq(#sent, 0)
    local saved = engine.save()
    eq(saved.records[1].locked, "edited")
end

function t.case04_no_second_command_after_a_rename()
    local world = H.world({ [1] = H.busLine("Line 1") })
    local sent = H.installCmd(world)
    local engine = H.freshEngine(nil)
    H.tickRange(engine, 100, 112)
    eq(#sent, 1)
    H.tickRange(engine, 113, 140)
    eq(#sent, 1)
end

function t.case08_disabled_mod_ticks_without_scanning()
    local world = H.world({ [1] = H.busLine("Line 1") })
    local sent = H.installCmd(world)
    local engine = H.freshEngine(H.saved({ ["enabled"] = false }))

    local facts = require("anujctrl/alnp/facts")
    local orig = facts.signature
    local calls = 0
    facts.signature = function(id)
        calls = calls + 1
        return orig(id)
    end
    local ok, err = pcall(function()
        H.tickRange(engine, 100, 110)
        eq(calls, 0)
        eq(#sent, 0)
    end)
    facts.signature = orig
    if not ok then error(err, 0) end
end

function t.case13_one_stop_line_is_never_renamed_or_blanked()
    local world = H.world({ [1] = H.busLine("Line 1", { 11 }) })
    local sent = H.installCmd(world)
    local engine = H.freshEngine(nil)
    H.tickRange(engine, 100, 140)
    eq(#sent, 0)
    local facts = require("anujctrl/alnp/facts")
    eq(facts.name(1), "Line 1")
    local saved = engine.save()
    eq(saved.records[1], nil)
end

-- A reload request ("r") on a one-stop line: minStops still declines it, so nothing is sent
-- and no empty record is left behind either.
function t.case13b_reload_request_on_one_stop_line_is_ignored()
    local world = H.world({ [1] = H.busLine("r", { 11 }) })
    local sent = H.installCmd(world)
    local engine = H.freshEngine(nil)
    H.tickRange(engine, 100, 140)
    eq(#sent, 0)
    local saved = engine.save()
    eq(saved.records[1], nil)
end

function t.case07_bus_autoRename_disabled_leaves_default_named_line_alone()
    local world = H.world({ [1] = H.busLine("Line 1") })
    local sent = H.installCmd(world)
    local engine = H.freshEngine(H.saved({ ["kinds.bus.autoRename"] = false }))
    H.tickRange(engine, 100, 115)
    eq(#sent, 0)
    local saved = engine.save()
    eq(saved.records[1], nil)
end

function t.case05_stop_change_renames_again_after_settle_but_churn_delays_it()
    local world = H.world({ [1] = H.busLine("Line 1") })
    local sent = H.installCmd(world)
    local engine = H.freshEngine(nil)
    H.tickRange(engine, 100, 105)
    eq(#sent, 1)
    local firstName = sent[1].name
    -- stops churn every tick: the timer keeps restarting, so nothing settles
    for now = 106, 109 do
        world.setStops(1, (now % 2 == 0) and { 11, 12, 13 } or { 11, 12, 14 })
        engine.tick(now)
    end
    eq(#sent, 1)
    -- stops stop changing: settle delay elapses on the final value
    world.setStops(1, { 11, 12, 13 })
    H.tickRange(engine, 110, 116)
    eq(#sent, 2)
    eq(sent[2].name ~= firstName, true)
end

function t.case06_mod_assigned_renames_disabled_leaves_the_changed_line_alone()
    local world = H.world({ [1] = H.busLine("Line 1") })
    local sent = H.installCmd(world)
    local engine = H.freshEngine(H.saved({ ["eligible.modAssigned"] = false }))
    H.tickRange(engine, 100, 105)
    eq(#sent, 1)
    world.setStops(1, { 11, 12, 13 })
    H.tickRange(engine, 106, 116)
    eq(#sent, 1)
end

return t
