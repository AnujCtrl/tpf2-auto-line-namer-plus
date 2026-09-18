local linesTab = require("anujctrl/alnp/gui/lines_tab")
local settings = require("anujctrl/alnp/settings")
local help = require("anujctrl/alnp/gui/help")
local topics = require("anujctrl/alnp/help_topics")
local facts = require("anujctrl/alnp/facts")
local propose = require("anujctrl/alnp/propose")
local fakeGame = require("fake_game")
local fakeGui = require("fake_gui")
local eq = require("fake_api").eq

local t = {}

-- ------------------------------------------------------------------------------------------
-- World: several bus lines (two with default names sharing a route, for the numbering case),
-- one cargo (truck) line, two hand-named lines (one untracked, one already auto-locked), one
-- player-locked line, and one one-stop line. Ids are chosen to sort in this same order, since
-- facts.playerLines() returns ids sorted ascending -- so table_.rows[i] is line i throughout.
-- ------------------------------------------------------------------------------------------
local function buildWorld()
    return fakeGame.world{
        towns = {
            [100] = "Springfield", [101] = "Shelbyville",
            [102] = "Ogdenville", [103] = "Capital City",
            [104] = "North Haverbrook", [105] = "Cypress Creek",
            [106] = "Shelbyville Junction",
        },
        stationGroups = {
            [11] = { name = "Springfield Central", station = 1011, town = 100, position = { 0, 0, 0 } },
            [12] = { name = "Shelbyville East", station = 1012, town = 101, position = { 500, 0, 0 } },
            [21] = { name = "Ogdenville North", station = 1021, town = 102, position = { 1000, 0, 0 } },
            [22] = { name = "Capital City Hub", station = 1022, town = 103, position = { 1500, 0, 0 } },
            [31] = { name = "North Haverbrook Yard", station = 1031, town = 104, position = { 2000, 0, 0 } },
            [32] = { name = "Cypress Creek Siding", station = 1032, town = 105, position = { 2500, 0, 0 } },
            [41] = { name = "Lonely Stop", station = 1041, town = 106, position = { 3000, 0, 0 } },
        },
        industries = {
            [701] = { name = "Coal Mine", position = { 50, 0, 0 } },
        },
        vehicles = {
            [601] = { capacities = { PASSENGERS = 40 } },
            [602] = { capacities = { PASSENGERS = 40 } },
            [603] = { capacities = { PASSENGERS = 40 } },
            [604] = { capacities = { COAL = 20 } },
            [605] = { capacities = { PASSENGERS = 10 } },
        },
        lines = {
            [1] = { name = "Line 1", stops = { 11, 12 }, modes = { "BUS" }, vehicles = { 601 } },
            [2] = { name = "Line 2", stops = { 11, 12 }, modes = { "BUS" }, vehicles = { 601 } },
            [3] = { name = "Downtown Express", stops = { 21, 22 }, modes = { "BUS" }, vehicles = { 602 } },
            [4] = { name = "Airport Express", stops = { 21, 22 }, modes = { "BUS" }, vehicles = { 602 } },
            [5] = { name = "Line 9", stops = { 31, 32 }, modes = { "BUS" }, vehicles = { 603 } },
            [6] = { name = "Freight 1", stops = { 11, 12 }, modes = { "TRUCK" }, vehicles = { 604 } },
            [7] = { name = "Line 7", stops = { 41 }, modes = { "BUS" }, vehicles = { 605 } },
        },
        player = 1,
    }
end

-- state.records for line 4 (already auto-locked by a previous engine tick) and line 5 (the
-- player ticked its lock box).
local function defaultRecords()
    return { [4] = { locked = "edited" }, [5] = { locked = "player" } }
end

local function newState(recordsOverride)
    return { settings = settings.defaults(), records = recordsOverride or defaultRecords() }
end

local function recordingSend()
    local calls = {}
    local function send(name, param)
        calls[#calls + 1] = { name = name, param = param }
    end
    return send, calls
end

-- Empties a recorded-calls table in place: `calls = {}` in the caller would only rebind the
-- caller's own local, leaving the `send` closure (which captured the original table) still
-- appending to it.
local function clearCalls(calls)
    for i = #calls, 1, -1 do
        calls[i] = nil
    end
end

local function findTable(root)
    local widget = fakeGui.find(root, function(w) return w.class == "comp.Table" end)
    assert(widget, "expected a comp.Table in the built component")
    return widget
end

-- The status TextView is the last item addItem'd into the button row's BoxLayout.
local function findStatus(root)
    local wrapper = fakeGui.find(root, function(w)
        return w.class == "comp.Component" and w.args[1] == "alnpLinesButtons"
    end)
    assert(wrapper, "expected the buttons row component")
    local layout = wrapper.children[1]
    return layout.children[#layout.children]
end

local function findButtonLabelled(root, label)
    return fakeGui.find(root, function(w)
        if w.class ~= "comp.Button" then return false end
        local child = w.args and w.args[1]
        return child ~= nil and fakeGui.text(child) == label
    end)
end

local function clickLabelled(root, label)
    local button = findButtonLabelled(root, label)
    assert(button, "no button labelled '" .. label .. "'")
    fakeGui.click(button)
end

local function toggle(checkBox, value)
    assert(checkBox.handlers.onToggle, "expected an onToggle handler")
    checkBox.handlers.onToggle(value)
end

local function previewAllAndDrain(component, times)
    clickLabelled(component, "Preview all")
    for __ = 1, (times or 10) do
        linesTab.update()
    end
end

-- ------------------------------------------------------------------------------------------
-- 1. build() reads nothing and produces an empty table with every info button in place.
-- ------------------------------------------------------------------------------------------
function t.build_reads_no_lines_and_creates_an_empty_table()
    linesTab.reset()
    help.reset()
    buildWorld()
    local state = newState()
    local send = function() end

    local realPlayerLines, realForLine = facts.playerLines, facts.forLine
    local playerLinesCalls, forLineCalls = 0, 0
    facts.playerLines = function(...)
        playerLinesCalls = playerLinesCalls + 1
        return realPlayerLines(...)
    end
    facts.forLine = function(...)
        forLineCalls = forLineCalls + 1
        return realForLine(...)
    end

    local component = linesTab.build(state, send)

    facts.playerLines = realPlayerLines
    facts.forLine = realForLine

    eq(playerLinesCalls, 0, "build must not call facts.playerLines")
    eq(forLineCalls, 0, "build must not call facts.forLine")

    local table_ = findTable(component)
    eq(#table_.rows, 0, "table starts with no rows")
end

function t.build_gives_every_header_and_both_buttons_an_info_button()
    linesTab.reset()
    help.reset()
    buildWorld()
    local component = linesTab.build(newState(), function() end)

    local function hasHelpButtonFor(key)
        local topic = topics.get(key)
        assert(topic, "missing topic " .. key)
        return fakeGui.find(component, function(w)
            -- rawget: `tooltip` is only set once setTooltip has actually been called on this
            -- widget, and a plain missing-field read must not trip the fake's strict `__index`.
            return w.class == "comp.Button" and rawget(w, "tooltip") == topic.text
        end) ~= nil
    end

    for __, key in ipairs({
        "lines.col.apply", "lines.col.kind", "lines.col.current",
        "lines.col.proposed", "lines.col.lock", "lines.col.renameNow",
        "lines.previewAll", "lines.applyChecked",
    }) do
        assert(hasHelpButtonFor(key), "expected an info button for topic " .. key)
    end
end

-- ------------------------------------------------------------------------------------------
-- 2. update() reads at most preview.linesPerFrame lines per call.
-- ------------------------------------------------------------------------------------------
function t.preview_all_reads_in_chunks_of_linesPerFrame()
    linesTab.reset()
    help.reset()
    local townsSpec, stationGroups, linesSpec = {}, {}, {}
    for i = 1, 5 do
        local townA, townB = 200 + i * 2 - 1, 200 + i * 2
        townsSpec[townA] = "Town" .. i .. "A"
        townsSpec[townB] = "Town" .. i .. "B"
        local groupA, groupB = 300 + i * 2 - 1, 300 + i * 2
        stationGroups[groupA] = { name = "Stop" .. i .. "A", station = 4000 + groupA, town = townA,
            position = { i * 1000, 0, 0 } }
        stationGroups[groupB] = { name = "Stop" .. i .. "B", station = 4000 + groupB, town = townB,
            position = { i * 1000 + 100, 0, 0 } }
        linesSpec[i] = { name = "Line " .. i, stops = { groupA, groupB }, modes = { "BUS" }, vehicles = {} }
    end
    fakeGame.world{ towns = townsSpec, stationGroups = stationGroups, lines = linesSpec, player = 1 }

    local tbl = settings.defaults()
    assert(settings.set(tbl, "preview.linesPerFrame", 2))
    local component = linesTab.build({ settings = tbl, records = {} }, function() end)
    local table_ = findTable(component)

    clickLabelled(component, "Preview all")
    eq(#table_.rows, 0, "no rows until update() runs")

    linesTab.update()
    eq(#table_.rows, 2, "first frame reads 2 lines")

    linesTab.update()
    eq(#table_.rows, 4, "second frame reads 2 more")

    linesTab.update()
    eq(#table_.rows, 5, "third frame reads the last one")
    assert(fakeGui.text(findStatus(component)):find("5", 1, true), "expected the final status to mention 5")

    linesTab.update()
    eq(#table_.rows, 5, "further update() calls read nothing more")
end

-- ------------------------------------------------------------------------------------------
-- 3. Row states: default-named (ticked), hand-named (unticked, empty/edited lock label),
--    player-locked (unticked), one-stop (left alone, disabled).
-- ------------------------------------------------------------------------------------------
function t.row_states_for_default_hand_named_locked_and_one_stop_lines()
    linesTab.reset()
    help.reset()
    buildWorld()
    local component = linesTab.build(newState(), function() end)
    local table_ = findTable(component)
    previewAllAndDrain(component)

    -- Line 1: default name -> ticked, shows a proposed name.
    local apply1, proposed1 = table_.rows[1][1], table_.rows[1][4]
    eq(apply1:isSelected(), true, "default-named line starts ticked")
    local proposedText1 = fakeGui.text(proposed1)
    assert(proposedText1 ~= nil and proposedText1 ~= "" and proposedText1 ~= "(left alone)",
        "expected a real proposed name, got " .. tostring(proposedText1))

    -- Line 3: hand-named, no record yet -> unticked, empty lock label.
    local apply3, lock3 = table_.rows[3][1], table_.rows[3][5]
    eq(apply3:isSelected(), false, "hand-named line (no record) starts unticked")
    eq(fakeGui.text(lock3), "", "no record yet: empty lock label")

    -- Line 4: hand-named, record already says "edited".
    local apply4, lock4 = table_.rows[4][1], table_.rows[4][5]
    eq(apply4:isSelected(), false, "hand-named line (edited record) starts unticked")
    eq(fakeGui.text(lock4), "locked: you edited the name")

    -- Line 5: player-locked.
    local apply5, lock5 = table_.rows[5][1], table_.rows[5][5]
    eq(apply5:isSelected(), false, "player-locked line starts unticked")
    eq(fakeGui.text(lock5), "locked")

    -- Line 6: cargo line -> kind label is translated and industry-aware naming kicks in.
    local kind6, proposed6 = table_.rows[6][2], table_.rows[6][4]
    eq(fakeGui.text(kind6), "Truck")
    assert(fakeGui.text(proposed6):find("Coal Mine", 1, true), "expected the cargo pattern to use the industry")

    -- Line 7: one stop -> left alone, apply box disabled.
    local apply7, proposed7 = table_.rows[7][1], table_.rows[7][4]
    eq(fakeGui.text(proposed7), "(left alone)")
    eq(apply7:isEnabled(), false, "a line with too few stops gets a disabled apply box")
end

-- ------------------------------------------------------------------------------------------
-- 4. Two default-named lines on the same route get distinct numbers in one preview.
-- ------------------------------------------------------------------------------------------
function t.two_default_named_lines_on_the_same_route_get_different_numbers()
    linesTab.reset()
    help.reset()
    buildWorld()
    local component = linesTab.build(newState({}), function() end)
    local table_ = findTable(component)
    previewAllAndDrain(component)

    local name1 = fakeGui.text(table_.rows[1][4])
    local name2 = fakeGui.text(table_.rows[2][4])
    assert(name1 ~= nil and name2 ~= nil and name1 ~= name2,
        "expected different proposed names, got " .. tostring(name1) .. " and " .. tostring(name2))
    assert(name2:find(name1, 1, true), "expected the second name to extend the first: " .. tostring(name2))
end

-- ------------------------------------------------------------------------------------------
-- 4b (fix round 1, F1). A line with a recorded number keeps it across a preview: it is not
-- bumped past its own number, and an unnumbered line scanned before it must not steal it.
-- Both lines share the Springfield <-> Shelbyville route (lines 1 and 2 from buildWorld()).
-- The numberKey is taken from a real propose.name() call rather than hand-written, so the test
-- cannot silently drift from how lines_tab.lua itself computes it.
-- ------------------------------------------------------------------------------------------
local function renamesByLine(calls)
    assert(#calls == 1 and calls[1].name == "apply", "expected exactly one apply event")
    local byLine = {}
    for __, rename in ipairs(calls[1].param.renames) do
        byLine[rename.line] = rename
    end
    return byLine
end

local function tickAndApply(component, table_, lineIndex1, lineIndex2)
    table_.rows[lineIndex1][1]:setSelected(true, false)
    table_.rows[lineIndex2][1]:setSelected(true, false)
    clickLabelled(component, "Apply checked")
end

function t.a_numbered_line_keeps_its_own_number_when_scanned_first()
    linesTab.reset()
    help.reset()
    buildWorld()
    local tbl = settings.defaults()
    facts.clearCache()
    local ownFacts = facts.forLine(1, tbl)
    local __, __, key = propose.name(ownFacts, nil, tbl, {})
    assert(key ~= nil, "expected the default pattern to use a number token")

    -- Line 1 (scanned first, ascending id order) already owns number 2; line 2 has no record.
    local records = { [1] = { lastAssigned = "Line 1", number = 2, numberKey = key } }
    local send, calls = recordingSend()
    local component = linesTab.build({ settings = tbl, records = records }, send)
    local table_ = findTable(component)
    previewAllAndDrain(component)

    tickAndApply(component, table_, 1, 2)
    local byLine = renamesByLine(calls)
    eq(byLine[1].n, 2, "the line that already owns number 2 must keep it, not be bumped to 3")
    eq(byLine[2].n, 1, "the other line must get a different (the lowest free) number")
    assert(byLine[1].name ~= byLine[2].name, "expected two distinct rendered names")

    eq(fakeGui.text(table_.rows[1][4]), byLine[1].name, "row 1's proposed-name text matches the apply payload")
    eq(fakeGui.text(table_.rows[2][4]), byLine[2].name, "row 2's proposed-name text matches the apply payload")
end

function t.an_unnumbered_line_scanned_first_does_not_steal_a_number_already_owned()
    linesTab.reset()
    help.reset()
    buildWorld()
    local tbl = settings.defaults()
    facts.clearCache()
    local ownFacts = facts.forLine(2, tbl)
    local __, __, key = propose.name(ownFacts, nil, tbl, {})
    assert(key ~= nil, "expected the default pattern to use a number token")

    -- Line 2 (the higher id) owns number 2; line 1 (the lower id, scanned FIRST) has no record.
    local records = { [2] = { lastAssigned = "Line 2", number = 2, numberKey = key } }
    local send, calls = recordingSend()
    local component = linesTab.build({ settings = tbl, records = records }, send)
    local table_ = findTable(component)
    previewAllAndDrain(component)

    tickAndApply(component, table_, 1, 2)
    local byLine = renamesByLine(calls)
    eq(byLine[2].n, 2, "the line scanned second must still keep the number it already owns")
    eq(byLine[1].n, 1, "the line scanned first must not steal number 2 from the line that owns it")
    assert(byLine[1].name ~= byLine[2].name, "expected two distinct rendered names")

    eq(fakeGui.text(table_.rows[1][4]), byLine[1].name, "row 1's proposed-name text matches the apply payload")
    eq(fakeGui.text(table_.rows[2][4]), byLine[2].name, "row 2's proposed-name text matches the apply payload")
end

-- ------------------------------------------------------------------------------------------
-- 4c (fix round 2, mutation survivor). The scan's *initial* taken-map seed
-- (propose.takenByKey(state.records, nil), at the top of startScan) is what stops a
-- not-yet-scanned line's number being handed to a line scanned EARLIER. The two fix-round-1
-- tests above both gave the numbered line `number = 2`, and naming.pickNumber always tries 1
-- first for an unnumbered line regardless of the seed -- so replacing the seed with `{}` still
-- passed them (the earlier-scanned unnumbered line lands on 1 either way, no collision). This
-- test instead gives the owned line `number = 1`, the value the earlier-scanned unnumbered line
-- WOULD naturally pick, so a missing seed produces a real, detectable collision.
-- ------------------------------------------------------------------------------------------
function t.the_initial_seed_stops_an_earlier_line_from_taking_a_number_a_later_line_owns()
    linesTab.reset()
    help.reset()
    buildWorld()
    local tbl = settings.defaults()
    facts.clearCache()
    local ownFacts = facts.forLine(2, tbl)
    local __, __, key = propose.name(ownFacts, nil, tbl, {})
    assert(key ~= nil, "expected the default pattern to use a number token")

    -- Line 2 (the higher id, scanned SECOND) already owns number 1 -- the number an unnumbered
    -- line would naturally pick first. Line 1 (the lower id, scanned FIRST) has no record.
    local records = { [2] = { lastAssigned = "Line 2", number = 1, numberKey = key } }
    local send, calls = recordingSend()
    local component = linesTab.build({ settings = tbl, records = records }, send)
    local table_ = findTable(component)
    previewAllAndDrain(component)

    tickAndApply(component, table_, 1, 2)
    local byLine = renamesByLine(calls)
    eq(byLine[2].n, 1, "the line that already owns number 1 must keep it")
    eq(byLine[1].n, 2, "the earlier-scanned line must not be given the number line 2 already owns")
    assert(byLine[1].n ~= byLine[2].n, "the two lines must not collide on the same number")

    eq(fakeGui.text(table_.rows[1][4]), byLine[1].name, "row 1's proposed-name text matches the apply payload")
    eq(fakeGui.text(table_.rows[2][4]), byLine[2].name, "row 2's proposed-name text matches the apply payload")
end

-- ------------------------------------------------------------------------------------------
-- 5. "Apply checked" sends exactly the ticked rows; a second click sends nothing.
-- ------------------------------------------------------------------------------------------
function t.apply_checked_sends_ticked_rows_then_nothing_on_second_click()
    linesTab.reset()
    help.reset()
    buildWorld()
    local send, calls = recordingSend()
    local component = linesTab.build(newState(), send)
    previewAllAndDrain(component)

    clickLabelled(component, "Apply checked")
    eq(#calls, 1, "one apply event sent")
    eq(calls[1].name, "apply")

    local byLine = {}
    for __, rename in ipairs(calls[1].param.renames) do
        byLine[rename.line] = rename
        assert(rename.name ~= nil, "every rename must carry a name")
    end
    assert(byLine[1] ~= nil and byLine[2] ~= nil, "expected the two default-named lines in the renames")
    assert(byLine[3] == nil and byLine[4] == nil and byLine[5] == nil and byLine[7] == nil,
        "unticked or disabled rows must not be sent")

    clearCalls(calls)
    clickLabelled(component, "Apply checked")
    eq(#calls, 0, "second click with nothing ticked sends nothing")
end

-- ------------------------------------------------------------------------------------------
-- 5b (A1). The headline promise: a row whose line the player renamed after the preview is
-- unticked by the next refresh, marked stale, and never sent by "Apply checked". Every item that
-- IS sent carries `from`, the name the row saw at preview time, so the engine can check it too.
-- ------------------------------------------------------------------------------------------
function t.a_hand_rename_after_the_preview_unticks_the_row_and_apply_skips_it()
    linesTab.reset()
    help.reset()
    local world = buildWorld()
    local state = newState()
    local send, calls = recordingSend()
    local component = linesTab.build(state, send)
    local table_ = findTable(component)
    previewAllAndDrain(component)
    eq(table_.rows[1][1]:isSelected(), true, "line 1 starts ticked (default name)")

    world.renameLine(1, "Airport Express")
    linesTab.clock = function() return 5000 end
    linesTab.refresh(state)

    eq(table_.rows[1][1]:isSelected(), false, "the renamed row must be unticked")
    eq(fakeGui.text(table_.rows[1][4]), "(name changed: preview again)")

    clickLabelled(component, "Apply checked")
    local byLine = renamesByLine(calls)
    eq(byLine[1], nil, "the hand-renamed line must not be applied")
    assert(byLine[2] ~= nil, "the untouched default-named line is still applied")
    eq(byLine[2].from, "Line 2", "every apply item carries the name seen at preview time")
end

-- ------------------------------------------------------------------------------------------
-- 5c (B4). A row locked without a name change is unticked once, but keeps showing its proposal
-- (never the false "name changed" notice) and is not permanently refused: the engine's apply
-- handler accepts an explicit re-tick, so a re-ticked row must survive a later refresh and be sent.
-- ------------------------------------------------------------------------------------------
function t.a_lock_with_no_name_change_keeps_the_proposal_and_allows_a_re_tick()
    linesTab.reset()
    help.reset()
    buildWorld()
    local state = newState()
    local send, calls = recordingSend()
    local component = linesTab.build(state, send)
    local table_ = findTable(component)
    previewAllAndDrain(component)
    eq(table_.rows[1][1]:isSelected(), true, "line 1 starts ticked (default name)")
    local proposedBefore = fakeGui.text(table_.rows[1][4])

    -- Line 1 becomes locked without ever being renamed.
    local lockedState = { settings = state.settings, records = { [1] = { locked = "player" } } }
    linesTab.clock = function() return 5000 end
    linesTab.refresh(lockedState)

    eq(table_.rows[1][1]:isSelected(), false, "a newly-locked row is unticked")
    eq(fakeGui.text(table_.rows[1][4]), proposedBefore,
        "the proposal is still shown -- the name never changed, so it is not stale")

    -- The player re-ticks it by hand; a later refresh (still locked, name still unchanged) must
    -- not force it back off, and Apply checked must send it.
    table_.rows[1][1]:setSelected(true, false)
    linesTab.clock = function() return 5001 end
    linesTab.refresh(lockedState)
    eq(table_.rows[1][1]:isSelected(), true, "a re-ticked, merely-locked row must not be re-forced off")

    clickLabelled(component, "Apply checked")
    local byLine = renamesByLine(calls)
    assert(byLine[1] ~= nil, "a re-ticked, merely-locked row must be sent")
end

-- ------------------------------------------------------------------------------------------
-- 5d (B4). Unlike a mere lock, a changed name needs a fresh preview: re-ticking must not help.
-- ------------------------------------------------------------------------------------------
function t.a_hand_renamed_row_stays_refused_even_after_a_re_tick()
    linesTab.reset()
    help.reset()
    local world = buildWorld()
    local state = newState()
    local send, calls = recordingSend()
    local component = linesTab.build(state, send)
    local table_ = findTable(component)
    previewAllAndDrain(component)

    world.renameLine(1, "Airport Express")
    linesTab.clock = function() return 5000 end
    linesTab.refresh(state)
    eq(table_.rows[1][1]:isSelected(), false, "the renamed row is unticked")

    table_.rows[1][1]:setSelected(true, false)
    clickLabelled(component, "Apply checked")
    local byLine = renamesByLine(calls)
    eq(byLine[1], nil, "a row whose name changed must stay refused even after a re-tick")
end

-- ------------------------------------------------------------------------------------------
-- 6. Lock box: ticking sends lock=true; unticking a player lock sends lock=false; unticking
--    an edited (or prefix) lock sends nothing, re-ticks itself, and explains in the status.
-- ------------------------------------------------------------------------------------------
function t.lock_box_sends_events_and_refuses_to_clear_edited_locks()
    linesTab.reset()
    help.reset()
    buildWorld()
    local send, calls = recordingSend()
    local component = linesTab.build(newState(), send)
    local table_ = findTable(component)
    previewAllAndDrain(component)

    -- Ticking the lock box on an unlocked line sends lock=true.
    local lockBox3 = table_.rows[3][5]
    toggle(lockBox3, true)
    eq(calls[#calls], { name = "lock", param = { line = 3, locked = true } })
    eq(fakeGui.text(lockBox3), "locked")

    -- Unticking a player lock sends lock=false.
    clearCalls(calls)
    local lockBox5 = table_.rows[5][5]
    toggle(lockBox5, false)
    eq(#calls, 1)
    eq(calls[1], { name = "lock", param = { line = 5, locked = false } })

    -- Unticking an "edited" lock cannot clear it from here.
    clearCalls(calls)
    local lockBox4 = table_.rows[4][5]
    toggle(lockBox4, false)
    eq(#calls, 0, "clearing an edited lock from here sends nothing")
    eq(lockBox4:isSelected(), true, "the box re-ticks itself")
    local statusText = fakeGui.text(findStatus(component))
    assert(statusText ~= nil and statusText ~= "", "the status explains why the lock did not clear")
end

-- ------------------------------------------------------------------------------------------
-- 7. "Rename now" sends renameNow with that row's line id.
-- ------------------------------------------------------------------------------------------
function t.rename_now_sends_that_rows_line_id()
    linesTab.reset()
    help.reset()
    buildWorld()
    local send, calls = recordingSend()
    local component = linesTab.build(newState(), send)
    local table_ = findTable(component)
    previewAllAndDrain(component)

    local renameButton3 = table_.rows[3][6]
    fakeGui.click(renameButton3)
    eq(#calls, 1)
    eq(calls[1], { name = "renameNow", param = { line = 3 } })
end

-- ------------------------------------------------------------------------------------------
-- 8. A line that vanishes mid-scan is skipped without an error.
-- ------------------------------------------------------------------------------------------
function t.a_line_that_vanishes_mid_scan_is_skipped_without_error()
    linesTab.reset()
    help.reset()
    local world = buildWorld()
    local tbl = settings.defaults()
    assert(settings.set(tbl, "preview.linesPerFrame", 1))
    local component = linesTab.build({ settings = tbl, records = {} }, function() end)
    local table_ = findTable(component)

    clickLabelled(component, "Preview all")
    linesTab.update() -- reads line 1
    eq(#table_.rows, 1)

    world.removeLine(2)
    local ok = pcall(linesTab.update) -- would read line 2, but it just vanished
    assert(ok, "update() must not raise when a line vanishes mid-scan")
    eq(#table_.rows, 1, "the vanished line contributed no row")

    for __ = 1, 10 do
        assert(pcall(linesTab.update), "update() must not raise while draining the rest of the scan")
    end
    eq(#table_.rows, 6, "every line except the vanished one got a row")
end

-- ------------------------------------------------------------------------------------------
-- 9. refresh() after a preview updates current name and lock label, at most once per second,
--    and never reads facts.forLine again.
-- ------------------------------------------------------------------------------------------
function t.refresh_after_preview_updates_rows_without_reading_facts_again()
    linesTab.reset()
    help.reset()
    local world = buildWorld()
    local state = newState()
    local component = linesTab.build(state, function() end)
    local table_ = findTable(component)
    previewAllAndDrain(component)

    world.renameLine(3, "Renamed By Hand")

    local realForLine = facts.forLine
    local forLineCalls = 0
    facts.forLine = function(...)
        forLineCalls = forLineCalls + 1
        return realForLine(...)
    end

    linesTab.clock = function() return 1000 end
    linesTab.refresh(state)

    facts.forLine = realForLine
    eq(forLineCalls, 0, "refresh must never call facts.forLine")
    eq(fakeGui.text(table_.rows[3][3]), "Renamed By Hand", "current name column updates")

    -- A second refresh within the same second does nothing further.
    world.renameLine(3, "Renamed Again")
    linesTab.refresh(state)
    eq(fakeGui.text(table_.rows[3][3]), "Renamed By Hand", "throttled: no update within the same second")

    -- After a second has passed, the next refresh picks it up.
    linesTab.clock = function() return 1001 end
    linesTab.refresh(state)
    eq(fakeGui.text(table_.rows[3][3]), "Renamed Again")
end

-- ------------------------------------------------------------------------------------------
-- 10 (A2). window.lua marks a version as refreshed before calling the tabs, so a refresh the
-- one-second throttle drops would otherwise be lost for good. The dropped state is kept and
-- applied by the next update() once the second has passed.
-- ------------------------------------------------------------------------------------------
function t.a_throttled_refresh_is_retried_by_the_next_update()
    linesTab.reset()
    help.reset()
    local world = buildWorld()
    local state = newState()
    local component = linesTab.build(state, function() end)
    local table_ = findTable(component)
    previewAllAndDrain(component)

    linesTab.clock = function() return 2000 end
    world.renameLine(3, "First Rename")
    linesTab.refresh(state)
    eq(fakeGui.text(table_.rows[3][3]), "First Rename", "the first refresh in a second goes through")

    -- Same second: this state is dropped by the throttle, but must not be forgotten.
    world.renameLine(3, "Second Rename")
    local lockedState = newState({ [3] = { locked = "player" } })
    linesTab.refresh(lockedState)
    eq(fakeGui.text(table_.rows[3][3]), "First Rename", "still throttled within the same second")

    linesTab.update() -- same second still: nothing to apply yet
    eq(fakeGui.text(table_.rows[3][3]), "First Rename", "update() must respect the throttle too")

    linesTab.clock = function() return 2001 end
    linesTab.update()
    eq(fakeGui.text(table_.rows[3][3]), "Second Rename", "the dropped refresh is applied a second later")
    eq(fakeGui.text(table_.rows[3][5]), "locked", "and it carries the dropped state's lock label")
end

-- ------------------------------------------------------------------------------------------
-- 11 (A3). refresh() syncs the lock box's tick, not only its label, and does so silently: a
-- setSelected that emitted would fire the row's own onToggle and send a bogus lock event back.
-- ------------------------------------------------------------------------------------------
function t.refresh_syncs_the_lock_boxes_tick_without_sending_events()
    linesTab.reset()
    help.reset()
    buildWorld()
    local send, calls = recordingSend()
    local component = linesTab.build(newState(), send)
    local table_ = findTable(component)
    previewAllAndDrain(component)

    local lockBox3 = table_.rows[3][5]
    eq(lockBox3:isSelected(), false, "line 3 has no record and starts unlocked")

    -- The engine auto-locked line 3 (the player edited its name).
    linesTab.clock = function() return 3000 end
    linesTab.refresh(newState({ [3] = { locked = "edited" } }))
    eq(lockBox3:isSelected(), true, "an auto-locked row shows a ticked lock box")
    eq(fakeGui.text(lockBox3), "locked: you edited the name")

    -- ...and the lock went away again (the engine renamed it, clearing the "edited" flag).
    linesTab.clock = function() return 3001 end
    linesTab.refresh(newState({ [3] = {} }))
    eq(lockBox3:isSelected(), false, "a cleared lock unticks the box")
    eq(fakeGui.text(lockBox3), "")

    eq(#calls, 0, "syncing the tick must never send a lock event")
end

-- ------------------------------------------------------------------------------------------
-- 12 (A6). "Preview all" clears the industry cache first. The GUI thread has its own copy of
-- facts.lua's cache, and nothing else on this thread ever clears it, so without this a stop's
-- industry is frozen at whatever the first preview of the session happened to see.
-- ------------------------------------------------------------------------------------------
function t.preview_all_clears_the_industry_cache_before_reading_anything()
    linesTab.reset()
    help.reset()
    buildWorld()
    local component = linesTab.build(newState(), function() end)

    local realClearCache, realForLine = facts.clearCache, facts.forLine
    local clears, readsBeforeFirstClear = 0, 0
    facts.clearCache = function(...)
        clears = clears + 1
        return realClearCache(...)
    end
    facts.forLine = function(...)
        if clears == 0 then readsBeforeFirstClear = readsBeforeFirstClear + 1 end
        return realForLine(...)
    end

    previewAllAndDrain(component)
    facts.clearCache, facts.forLine = realClearCache, realForLine

    eq(clears, 1, "Preview all must clear the industry cache exactly once")
    eq(readsBeforeFirstClear, 0, "and before it reads any line")
end

-- ------------------------------------------------------------------------------------------
-- 13 (A6). The preview already ignores a kind's auto-rename switch (it asks tracker.decide with
-- kindAutoRename = true), so it must ignore the master switch too, or "Preview all" with the mod
-- switched off reports "0 would change" and ticks nothing -- while the same tab with only the bus
-- kind switched off ticks everything. The engine's apply handler never consults `enabled`, so the
-- rows it then sends really are applied.
-- ------------------------------------------------------------------------------------------
function t.preview_with_the_master_switch_off_still_ticks_and_applies_rows()
    linesTab.reset()
    help.reset()
    buildWorld()
    local tbl = settings.defaults()
    assert(settings.set(tbl, "enabled", false))
    local send, calls = recordingSend()
    local component = linesTab.build({ settings = tbl, records = defaultRecords() }, send)
    local table_ = findTable(component)
    previewAllAndDrain(component)

    eq(table_.rows[1][1]:isSelected(), true, "a default-named line is still ticked with the mod off")
    eq(table_.rows[4][1]:isSelected(), false, "a locked line is still left unticked")
    assert(not fakeGui.text(findStatus(component)):find("0 would change", 1, true),
        "the status must not claim nothing would change: " .. fakeGui.text(findStatus(component)))

    clickLabelled(component, "Apply checked")
    local byLine = renamesByLine(calls)
    assert(byLine[1] ~= nil and byLine[2] ~= nil, "the ticked rows are sent to the engine")
    eq(byLine[1].from, "Line 1")
end

return t
