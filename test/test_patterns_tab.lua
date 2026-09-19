-- Tests for gui/patterns_tab.lua: the preset chooser, the default pattern row, one row per kind,
-- and the token cheat-sheet.
local fakeGui = require("fake_gui")
local eq = require("fake_api").eq
local help = require("anujctrl/alnp/gui/help")
local topics = require("anujctrl/alnp/help_topics")
local kinds = require("anujctrl/alnp/kinds")
local naming = require("anujctrl/alnp/naming")
local classify = require("anujctrl/alnp/classify")
local settings = require("anujctrl/alnp/settings")
local patternsTab = require("anujctrl/alnp/gui/patterns_tab")

local t = {}

local function newState()
    return { settings = settings.defaults(), records = {} }
end

local function sendRecorder()
    local sent = {}
    local function send(name, param) sent[#sent + 1] = { name = name, param = param } end
    return sent, send
end

-- A ComboBox's addItem() records the raw string item as a "child" too (fake_gui's addItem is
-- generic across every widget class), so a tree walk can hand a predicate a plain string instead
-- of a widget table; check the class first so rawget is only ever called on a real widget.
local function tooltipOf(w)
    if w.class ~= "comp.Button" then return nil end
    return rawget(w, "tooltip")
end

-- Counts DISTINCT widgets: the tab's scroll area both takes the content as its constructor
-- argument and is given it again through setContent (X11: that is what every proven use does),
-- and the fake records a child under each of those calls, so one real widget is reachable by two
-- edges of the fake's tree. The question asked here is "how many info buttons exist", not "how
-- many paths lead to one", so the same widget seen twice still counts once.
local function countButtonsWithTooltip(root, key)
    local text = topics.get(key).text
    local seen, count = {}, 0
    for __, widget in ipairs(fakeGui.findAll(root, function(w) return tooltipOf(w) == text end)) do
        if not seen[widget] then
            seen[widget] = true
            count = count + 1
        end
    end
    return count
end

-- One Component per logical row (built by patterns_tab's own newRow() helper); a row's subtree
-- can be searched on its own, so widgets that look alike across rows (every kind has a "Custom
-- pattern" check box) can still be told apart.
local function findRow(root, predicate)
    for __, candidate in ipairs(fakeGui.findAll(root, function(w)
        return w.class == "comp.Component" and fakeGui.text(w) == "alnpPatternsRow"
    end)) do
        if fakeGui.find(candidate, predicate) then return candidate end
    end
    return nil
end

local function kindRow(root, kind)
    return findRow(root, function(w) return w.class == "comp.TextView" and fakeGui.text(w) == kinds.label[kind] end)
end

local function textFieldIn(component)
    return fakeGui.find(component, function(w) return w.class == "comp.TextInputField" end)
end

local function checkboxIn(component, label)
    return fakeGui.find(component, function(w) return w.class == "comp.CheckBox" and fakeGui.text(w) == label end)
end

-- The row's preview TextView: the one whose text is not "i" (every help button's inner label).
local function previewIn(component)
    local views = fakeGui.findAll(component, function(w) return w.class == "comp.TextView" and fakeGui.text(w) ~= "i" end)
    return views[#views]
end

-- 1. every row exists (default + one per kind), and every surface has its info button. -----------

function t.rows_exist_for_default_and_every_kind_with_info_buttons()
    patternsTab.reset()
    help.reset()
    local root = patternsTab.build(newState(), function() end)

    eq(countButtonsWithTooltip(root, "patterns.preset"), 1)
    eq(countButtonsWithTooltip(root, "patterns.default"), 1)
    eq(countButtonsWithTooltip(root, "patterns.kind"), #kinds.list)
    eq(countButtonsWithTooltip(root, "patterns.autoRename"), #kinds.list)
    eq(countButtonsWithTooltip(root, "patterns.custom"), #kinds.list)

    local tokensTopic = topics.get("patterns.tokens")
    assert(fakeGui.find(root, function(w)
        local tooltip = tooltipOf(w)
        return tooltip ~= nil and tooltip:find(tokensTopic.text, 1, true) ~= nil
    end), "the token reference should carry its own info button")

    for __, kind in ipairs(kinds.list) do
        local row = kindRow(root, kind)
        assert(row, "missing row for kind " .. kind)
        assert(checkboxIn(row, "Rename automatically"), kind .. " row missing the auto-rename checkbox")
        assert(checkboxIn(row, "Custom pattern"), kind .. " row missing the custom-pattern checkbox")
        assert(textFieldIn(row), kind .. " row missing its pattern field")
        assert(previewIn(row), kind .. " row missing its preview")
    end
end

-- 2. previews equal naming.render's own output for the bus and trainCargo samples. ---------------

function t.default_and_trainCargo_previews_equal_naming_render()
    patternsTab.reset()
    help.reset()
    local state = newState()
    local root = patternsTab.build(state, function() end)

    local busFacts = naming.sampleFacts("bus")
    local expectedDefault = naming.render(state.settings.patterns.default, busFacts,
        { settings = state.settings, kind = "bus", scope = classify.scope(busFacts, state.settings), n = 2 })
    assert(fakeGui.find(root, function(w) return w.class == "comp.TextView" and fakeGui.text(w) == expectedDefault end),
        "default preview should equal naming.render of the default pattern for the bus sample")

    local cargoFacts = naming.sampleFacts("trainCargo")
    local expectedCargo = naming.render(state.settings.patterns.trainCargo, cargoFacts,
        { settings = state.settings, kind = "trainCargo", scope = classify.scope(cargoFacts, state.settings), n = 2 })
    assert(expectedCargo:find("Coal mine", 1, true) or expectedCargo:find("Steel mill", 1, true),
        "sanity: the shipped cargo pattern should mention an industry")
    assert(fakeGui.find(root, function(w) return w.class == "comp.TextView" and fakeGui.text(w) == expectedCargo end),
        "trainCargo preview should equal naming.render of the cargo pattern and show an industry")
end

-- 3. typing a new default pattern sends the change and updates dependent previews immediately. ---

function t.typing_new_default_pattern_updates_previews_without_refresh()
    patternsTab.reset()
    help.reset()
    local state = newState()
    local sent, send = sendRecorder()
    local root = patternsTab.build(state, send)

    local cargoFacts = naming.sampleFacts("trainCargo")
    local cargoPreviewBefore = naming.render(state.settings.patterns.trainCargo, cargoFacts,
        { settings = state.settings, kind = "trainCargo", scope = classify.scope(cargoFacts, state.settings), n = 2 })

    local defaultField = fakeGui.find(root, function(w)
        return w.class == "comp.TextInputField" and fakeGui.text(w) == state.settings.patterns.default
    end)
    assert(defaultField, "default field should start out showing the default pattern")

    local newPattern = "{type} {firstTown}"
    defaultField:setText(newPattern, true)

    eq(#sent, 1)
    eq(sent[1], { name = "set", param = { path = "patterns.default", value = newPattern } })

    local busFacts = naming.sampleFacts("bus")
    local expectedDefault = naming.render(newPattern, busFacts,
        { settings = state.settings, kind = "bus", scope = classify.scope(busFacts, state.settings), n = 2 })
    assert(fakeGui.find(root, function(w) return w.class == "comp.TextView" and fakeGui.text(w) == expectedDefault end),
        "default preview should update immediately, without a refresh")

    local tramFacts = naming.sampleFacts("tram")
    local expectedTram = naming.render(newPattern, tramFacts,
        { settings = state.settings, kind = "tram", scope = classify.scope(tramFacts, state.settings), n = 2 })
    assert(fakeGui.find(root, function(w) return w.class == "comp.TextView" and fakeGui.text(w) == expectedTram end),
        "tram inherits the default pattern, so its preview should update too")

    assert(fakeGui.find(root, function(w) return w.class == "comp.TextView" and fakeGui.text(w) == cargoPreviewBefore end),
        "trainCargo already has its own custom pattern; it should not react to the default changing")
end

-- 4. an unknown token renders literally, so a typo is visible. ------------------------------------

function t.unknown_token_is_shown_literally_in_preview()
    patternsTab.reset()
    help.reset()
    local state = newState()
    local root = patternsTab.build(state, function() end)

    local defaultField = fakeGui.find(root, function(w)
        return w.class == "comp.TextInputField" and fakeGui.text(w) == state.settings.patterns.default
    end)
    defaultField:setText("{bogus}", true)

    assert(fakeGui.find(root, function(w) return w.class == "comp.TextView" and fakeGui.text(w) == "{bogus}" end),
        "an unrecognised token should show up exactly as typed")
end

-- 5. ticking/unticking "Custom pattern" on bus sends the right value and (de)enables the field. --

function t.ticking_and_unticking_custom_on_bus()
    patternsTab.reset()
    help.reset()
    local state = newState()
    local sent, send = sendRecorder()
    local root = patternsTab.build(state, send)

    local busRow = kindRow(root, "bus")
    assert(busRow, "should find the bus row")
    local custom = checkboxIn(busRow, "Custom pattern")
    local field = textFieldIn(busRow)
    assert(custom and field)

    local defaultPattern = state.settings.patterns.default
    eq(custom:isSelected(), false)
    eq(field:isEnabled(), false)
    eq(fakeGui.text(field), defaultPattern)

    custom:setSelected(true, true)
    eq(#sent, 1)
    eq(sent[1], { name = "set", param = { path = "patterns.bus", value = defaultPattern } })
    eq(field:isEnabled(), true)
    eq(fakeGui.text(field), defaultPattern)

    custom:setSelected(false, true)
    eq(#sent, 2)
    eq(sent[2], { name = "set", param = { path = "patterns.bus", value = "" } })
    eq(field:isEnabled(), false)
    eq(fakeGui.text(field), defaultPattern)
end

-- 6. toggling "Rename automatically" sends the auto-rename path with a boolean. -------------------

function t.toggling_auto_rename_sends_boolean()
    patternsTab.reset()
    help.reset()
    local state = newState()
    local sent, send = sendRecorder()
    local root = patternsTab.build(state, send)

    local tramRow = kindRow(root, "tram")
    local autoRename = checkboxIn(tramRow, "Rename automatically")
    assert(autoRename)
    eq(autoRename:isSelected(), true)

    autoRename:setSelected(false, true)
    eq(#sent, 1)
    eq(sent[1], { name = "set", param = { path = "kinds.tram.autoRename", value = false } })
end

-- 7. preset: first click confirms, second sends; changing the combo resets the confirmation. ------

function t.preset_needs_two_clicks_and_combo_change_resets_it()
    patternsTab.reset()
    help.reset()
    local state = newState()
    local sent, send = sendRecorder()
    local root = patternsTab.build(state, send)

    local combo = fakeGui.find(root, function(w) return w.class == "comp.ComboBox" end)
    local applyLabel = fakeGui.find(root, function(w) return w.class == "comp.TextView" and fakeGui.text(w) == "Apply preset" end)
    local applyButton = fakeGui.find(root, function(w) return w.class == "comp.Button" and w.children[1] == applyLabel end)
    assert(combo and applyLabel and applyButton)

    fakeGui.click(applyButton)
    eq(#sent, 0)
    eq(fakeGui.text(applyLabel), "Click again to overwrite all patterns")

    fakeGui.click(applyButton)
    eq(#sent, 1)
    eq(sent[1], { name = "preset", param = { key = "simple" } })
    eq(fakeGui.text(applyLabel), "Apply preset")

    -- one click again, then change the combo box: the confirmation must reset without sending.
    fakeGui.click(applyButton)
    eq(fakeGui.text(applyLabel), "Click again to overwrite all patterns")
    combo:setSelected(1, true)
    eq(fakeGui.text(applyLabel), "Apply preset")
    eq(#sent, 1)

    -- a fresh two clicks against the new selection sends that preset's key.
    fakeGui.click(applyButton)
    eq(#sent, 1)
    fakeGui.click(applyButton)
    eq(#sent, 2)
    eq(sent[2], { name = "preset", param = { key = "upstream" } })
end

-- 8. a pattern that renders blank shows the "(blank ...)" placeholder. ----------------------------

function t.blank_pattern_shows_blank_placeholder()
    patternsTab.reset()
    help.reset()
    local state = newState()
    local root = patternsTab.build(state, function() end)

    local defaultField = fakeGui.find(root, function(w)
        return w.class == "comp.TextInputField" and fakeGui.text(w) == state.settings.patterns.default
    end)
    defaultField:setText("", true)

    assert(fakeGui.find(root, function(w)
        return w.class == "comp.TextView" and fakeGui.text(w) == "(blank: the line would be left alone)"
    end), "a blank rendered pattern should show the blank-pattern message")
end

-- 9. refresh reacts to a changed label without sending anything. ----------------------------------

function t.refresh_updates_preview_from_changed_label_without_sending()
    patternsTab.reset()
    help.reset()
    local state = newState()
    local sent, send = sendRecorder()
    local root = patternsTab.build(state, send)

    local nextState = newState()
    nextState.settings.label.kind.bus = "Coach"
    patternsTab.refresh(nextState)

    eq(#sent, 0)

    local busFacts = naming.sampleFacts("bus")
    local expected = naming.render(nextState.settings.patterns.default, busFacts,
        { settings = nextState.settings, kind = "bus", scope = classify.scope(busFacts, nextState.settings), n = 2 })
    assert(expected:find("Coach", 1, true), "sanity: the expected preview should mention the new label")
    assert(fakeGui.find(root, function(w) return w.class == "comp.TextView" and fakeGui.text(w) == expected end),
        "the bus-kind default preview should reflect the changed label after refresh")
end

-- 10. the token reference tooltip covers every naming.tokens token and the syntax topic text. -----

function t.token_reference_tooltip_contains_every_token_and_topic_text()
    patternsTab.reset()
    help.reset()
    local root = patternsTab.build(newState(), function() end)

    local topic = topics.get("patterns.tokens")
    local tokenButton = fakeGui.find(root, function(w)
        local tooltip = tooltipOf(w)
        return tooltip ~= nil and tooltip:find(topic.text, 1, true) ~= nil
    end)
    assert(tokenButton, "the token reference should have a help button whose tooltip includes the syntax topic text")

    local tooltip = tokenButton.tooltip
    for __, tokenInfo in ipairs(naming.tokens) do
        assert(tooltip:find(tokenInfo.token, 1, true), "tooltip should mention " .. tokenInfo.token)
    end
end

-- 11. every setText on a TextInputField in the build and refresh paths passes an explicit false,
-- so nothing is sent even if the game were to emit onChange by default (undocumented behaviour;
-- see the task brief). Hostility is injected by wrapping the constructor: a setText call whose
-- emit flag is nil (never one that is explicitly false) fires onChange, exactly as an emit-by-
-- default game would.
function t.building_and_refreshing_send_nothing_even_with_a_hostile_emit_default()
    patternsTab.reset()
    help.reset()

    local realNew = api.gui.comp.TextInputField.new
    api.gui.comp.TextInputField.new = function(...)
        local widget = realNew(...)
        local realSetText = widget.setText
        widget.setText = function(selfArg, text, emit)
            realSetText(selfArg, text, emit)
            if emit == nil and selfArg.handlers.onChange then
                selfArg.handlers.onChange(text)
            end
        end
        return widget
    end

    local state = newState()
    local sent, send = sendRecorder()
    local __ = patternsTab.build(state, send)
    eq(#sent, 0)

    local nextState = newState()
    nextState.settings.patterns.default = "{type} {n}"
    patternsTab.refresh(nextState)
    eq(#sent, 0)

    api.gui.comp.TextInputField.new = realNew
end

-- 12. build()'s scroll area is capped to the same size as the other tabs' scroll areas. --------------

function t.scroll_area_has_the_shared_maximum_size()
    patternsTab.reset()
    help.reset()
    local scrollArea = patternsTab.build(newState(), function() end)

    local sizeCall = nil
    for __, call in ipairs(scrollArea.calls) do
        if call.name == "setMaximumSize" then sizeCall = call end
    end
    assert(sizeCall, "expected a setMaximumSize call on the scroll area")
    eq(sizeCall.args[1].args[1], 860)
    eq(sizeCall.args[1].args[2], 380)
end

-- 13 (X11). Every proven use of comp.ScrollArea follows the constructor with setContent(content),
-- and both other tabs in this mod do too. Without it the tab can come up empty.

function t.scroll_area_is_given_its_content_explicitly()
    patternsTab.reset()
    help.reset()
    local scrollArea = patternsTab.build(newState(), function() end)

    local content = fakeGui.find(scrollArea, function(w)
        return w.class == "comp.Component" and w.args[1] == "alnpPatternsContent"
    end)
    assert(content, "expected the patterns content component")

    local setContentCall = nil
    for __, call in ipairs(scrollArea.calls) do
        if call.name == "setContent" then setContentCall = call end
    end
    assert(setContentCall, "expected a setContent call on the scroll area")
    assert(setContentCall.args[1] == content, "setContent must be given the tab's own content")
    eq(scrollArea.args[1], content, "the constructor argument stays as it is")
end

return t
