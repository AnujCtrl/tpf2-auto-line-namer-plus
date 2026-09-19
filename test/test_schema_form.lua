-- Tests for gui/schema_form.lua: the General and Advanced tabs, generated from settings.schema.
local fakeGui = require("fake_gui")
local eq = require("fake_api").eq
local log = require("anujctrl/alnp/log")
local help = require("anujctrl/alnp/gui/help")
local settings = require("anujctrl/alnp/settings")
local sync = require("anujctrl/alnp/gui/sync")
local schemaForm = require("anujctrl/alnp/gui/schema_form")

local t = {}

-- Finds the layout.BoxLayout whose first child's displayed text is exactly `label`: every row and
-- section heading this module builds is a horizontal layout starting with that label's TextView.
local function findLayoutByFirstLabel(root, label)
    return fakeGui.find(root, function(w)
        return w.class == "layout.BoxLayout" and w.children[1] ~= nil and fakeGui.text(w.children[1]) == label
    end)
end

local function findButtonLabelled(root, label)
    return fakeGui.find(root, function(w)
        return w.class == "comp.Button" and w.children[1] and fakeGui.text(w.children[1]) == label
    end)
end

local function infoButtonsWithTooltip(root, tooltip)
    return fakeGui.findAll(root, function(w)
        return w.class == "comp.Button" and w.children[1] and fakeGui.text(w.children[1]) == "i" and w.tooltip == tooltip
    end)
end

local function recordingSend()
    local calls = {}
    local send = function(name, param) calls[#calls + 1] = { name = name, param = param } end
    return calls, send
end

-- clock: optional, forwarded to schemaForm.reset() -> sync.new(), so a test can advance sync's
-- timeout deterministically instead of sleeping.
local function resetAll(clock)
    schemaForm.reset(clock)
    help.reset()
end

-- A clock you advance by hand, matching test_sync.lua's helper: clock.now is what sync.new wants.
local function newClock(t0)
    local now = t0 or 0
    return {
        now = function() return now end,
        advance = function(dt) now = now + dt end,
    }
end

-- 1. build() shows only its own tab's rows; the patterns section shows on neither. -----------------

function t.general_and_advanced_show_only_their_own_rows_patterns_shows_nowhere()
    resetAll()
    local state = { settings = settings.defaults() }
    local __, send = recordingSend()

    local generalComp = schemaForm.build("general", state, send)
    local advancedComp = schemaForm.build("advanced", state, send)

    -- Not fakeGui.allText(): it unconditionally calls fakeGui.text() on every node, including the
    -- plain-string items a comp.ComboBox's addItem stores as children (see enum rows below), and
    -- fakeGui.text() rawgets a field on that node assuming it is a widget table, not a string.
    -- fakeGui.find() is safe here: its predicate only inspects .class, which is nil (not an
    -- error) on a plain string, so it short-circuits before ever reaching a ComboBox's items.
    for __, section in ipairs(settings.sections) do
        for __, row in ipairs(settings.rowsIn(section.key)) do
            local label = _(row.label)
            local inGeneral = findLayoutByFirstLabel(generalComp, label) ~= nil
            local inAdvanced = findLayoutByFirstLabel(advancedComp, label) ~= nil
            if section.tab == "general" then
                assert(inGeneral, "general tab missing row " .. row.path)
                assert(not inAdvanced, "advanced tab should not show general row " .. row.path)
            elseif section.tab == "advanced" then
                assert(inAdvanced, "advanced tab missing row " .. row.path)
                assert(not inGeneral, "general tab should not show advanced row " .. row.path)
            else
                assert(not inGeneral, "general tab should not show patterns row " .. row.path)
                assert(not inAdvanced, "advanced tab should not show patterns row " .. row.path)
            end
        end
    end
end

-- 2. exactly one correct info button per row and per section heading. ------------------------------

function t.every_row_and_section_has_exactly_one_correct_info_button()
    resetAll()
    local state = { settings = settings.defaults() }
    local __, send = recordingSend()

    local generalComp = schemaForm.build("general", state, send)
    local advancedComp = schemaForm.build("advanced", state, send)
    local roots = { general = generalComp, advanced = advancedComp }

    for __, section in ipairs(settings.sections) do
        local root = roots[section.tab]
        if root then
            eq(#infoButtonsWithTooltip(root, section.help), 1,
                "section " .. section.key .. " should have exactly one info button showing its own help")

            for __, row in ipairs(settings.rowsIn(section.key)) do
                local expected = settings.helpText(row)
                assert(expected:find(row.help, 1, true), row.path .. ": helpText should contain the row's own help")
                assert(expected:find("Default:", 1, true), row.path .. ": helpText should contain a Default: line")
                eq(#infoButtonsWithTooltip(root, expected), 1,
                    "row " .. row.path .. " should have exactly one info button showing its generated help")
            end
        end
    end
end

-- 3. interacting with each editor kind sends the right "set" event. --------------------------------

function t.toggling_a_bool_sends_set_with_path_and_boolean()
    resetAll()
    local state = { settings = settings.defaults() }
    local calls, send = recordingSend()
    local generalComp = schemaForm.build("general", state, send)

    local row = findLayoutByFirstLabel(generalComp, _(settings.row("enabled").label))
    local checkbox = row.children[2]
    checkbox:setSelected(false, true)

    eq(#calls, 1)
    eq(calls[1].name, "set")
    eq(calls[1].param.path, "enabled")
    eq(calls[1].param.value, false)
end

function t.typing_in_a_string_field_sends_the_text()
    resetAll()
    local state = { settings = settings.defaults() }
    local calls, send = recordingSend()
    local generalComp = schemaForm.build("general", state, send)

    local row = findLayoutByFirstLabel(generalComp, _(settings.row("lock.prefix").label))
    local field = row.children[2]
    field:setText("Cst", true)

    eq(#calls, 1)
    eq(calls[1].name, "set")
    eq(calls[1].param.path, "lock.prefix")
    eq(calls[1].param.value, "Cst")
end

function t.choosing_enum_index_2_of_log_level_sends_debug()
    resetAll()
    local state = { settings = settings.defaults() }
    local calls, send = recordingSend()
    local advancedComp = schemaForm.build("advanced", state, send)

    local row = findLayoutByFirstLabel(advancedComp, _(settings.row("log.level").label))
    local combo = row.children[2]
    combo:setSelected(2, true)

    eq(#calls, 1)
    eq(calls[1].name, "set")
    eq(calls[1].param.path, "log.level")
    eq(calls[1].param.value, "debug")
end

function t.moving_an_int_slider_to_7_6_sends_8()
    resetAll()
    local state = { settings = settings.defaults() }
    local calls, send = recordingSend()
    local advancedComp = schemaForm.build("advanced", state, send)

    local row = findLayoutByFirstLabel(advancedComp, _(settings.row("scan.linesPerTick").label))
    local slider = fakeGui.find(row.children[2], function(w) return w.class == "comp.Slider" end)
    slider:setValue(7.6, true)

    eq(#calls, 1)
    eq(calls[1].name, "set")
    eq(calls[1].param.path, "scan.linesPerTick")
    eq(calls[1].param.value, 8)
end

-- 4. editors show the state's values at build time. -------------------------------------------------

function t.editors_show_the_states_values_at_build_time()
    resetAll()
    local defaults = settings.defaults()
    eq(settings.get(defaults, "scan.linesPerTick"), 5) -- the shipped default, per the task brief
    assert(settings.set(defaults, "enabled", false))
    assert(settings.set(defaults, "lock.prefix", "Cst"))
    assert(settings.set(defaults, "log.level", "debug"))
    assert(settings.set(defaults, "scan.linesPerTick", 9))
    local state = { settings = defaults }
    local __, send = recordingSend()

    local generalComp = schemaForm.build("general", state, send)
    local advancedComp = schemaForm.build("advanced", state, send)

    local enabledRow = findLayoutByFirstLabel(generalComp, _(settings.row("enabled").label))
    eq(enabledRow.children[2]:isSelected(), false)

    local prefixRow = findLayoutByFirstLabel(generalComp, _(settings.row("lock.prefix").label))
    eq(prefixRow.children[2]:getText(), "Cst")

    local logRow = findLayoutByFirstLabel(advancedComp, _(settings.row("log.level").label))
    eq(logRow.children[2]:getCurrentIndex(), 2) -- "debug" is values[3]

    local ticksRow = findLayoutByFirstLabel(advancedComp, _(settings.row("scan.linesPerTick").label))
    local slider = fakeGui.find(ticksRow.children[2], function(w) return w.class == "comp.Slider" end)
    eq(slider:getValue(), 9)
end

-- 5. reset-section, reset-everything (general only) and run-API-check (advanced only) buttons. ------

function t.reset_section_sends_resetSection_with_that_sections_key_and_has_an_info_button()
    resetAll()
    local state = { settings = settings.defaults() }
    local calls, send = recordingSend()
    local generalComp = schemaForm.build("general", state, send)

    local eligibility
    for __, section in ipairs(settings.sections) do
        if section.key == "eligibility" then eligibility = section end
    end
    assert(eligibility, "settings.sections should contain 'eligibility'")

    local heading = findLayoutByFirstLabel(generalComp, _(eligibility.label))
    eq(heading.children[2].tooltip, eligibility.help) -- the section's own info button
    local resetButton = heading.children[3]
    local resetInfoButton = heading.children[4]

    local topics = require("anujctrl/alnp/help_topics")
    eq(resetInfoButton.tooltip, topics.get("reset.section").text)

    fakeGui.click(resetButton)
    eq(#calls, 1)
    eq(calls[1].name, "resetSection")
    eq(calls[1].param.section, "eligibility")
end

function t.reset_everything_exists_only_on_general_and_sends_resetAll()
    resetAll()
    local state = { settings = settings.defaults() }
    local calls, send = recordingSend()
    local generalComp = schemaForm.build("general", state, send)
    local advancedComp = schemaForm.build("advanced", state, send)

    local onGeneral = findButtonLabelled(generalComp, _("Reset everything"))
    local onAdvanced = findButtonLabelled(advancedComp, _("Reset everything"))
    assert(onGeneral, "general tab should have a Reset everything button")
    assert(not onAdvanced, "advanced tab should not have a Reset everything button")

    local footer = fakeGui.find(generalComp, function(w) return w.class == "layout.BoxLayout" and w.children[1] == onGeneral end)
    assert(footer and footer.children[2], "Reset everything should carry its own info button")
    eq(#infoButtonsWithTooltip(generalComp, require("anujctrl/alnp/help_topics").get("reset.all").text), 1)

    fakeGui.click(onGeneral)
    eq(#calls, 1)
    eq(calls[1].name, "resetAll")
    eq(calls[1].param, {})
end

function t.run_api_check_exists_only_on_advanced_and_sends_apiCheck()
    resetAll()
    local state = { settings = settings.defaults() }
    local calls, send = recordingSend()
    local generalComp = schemaForm.build("general", state, send)
    local advancedComp = schemaForm.build("advanced", state, send)

    local onAdvanced = findButtonLabelled(advancedComp, _("Run API check"))
    local onGeneral = findButtonLabelled(generalComp, _("Run API check"))
    assert(onAdvanced, "advanced tab should have a Run API check button")
    assert(not onGeneral, "general tab should not have a Run API check button")

    local footer = fakeGui.find(advancedComp, function(w) return w.class == "layout.BoxLayout" and w.children[1] == onAdvanced end)
    assert(footer and footer.children[2], "Run API check should carry its own info button")
    eq(#infoButtonsWithTooltip(advancedComp, require("anujctrl/alnp/help_topics").get("advanced.apiCheck").text), 1)

    fakeGui.click(onAdvanced)
    eq(#calls, 1)
    eq(calls[1].name, "apiCheck")
    eq(calls[1].param, {})
end

-- 6. refresh() with a changed state updates the widget and sends nothing. --------------------------

function t.refresh_updates_a_changed_widget_and_sends_nothing()
    resetAll()
    local state = { settings = settings.defaults() }
    local calls, send = recordingSend()
    local advancedComp = schemaForm.build("advanced", state, send)

    local row = findLayoutByFirstLabel(advancedComp, _(settings.row("scan.linesPerTick").label))
    local slider = fakeGui.find(row.children[2], function(w) return w.class == "comp.Slider" end)
    eq(slider:getValue(), 5)

    assert(settings.set(state.settings, "scan.linesPerTick", 20))
    schemaForm.refresh(state)

    eq(slider:getValue(), 20)
    eq(#calls, 0, "refresh must never send an event")
end

-- 7. refresh() never clobbers a field the player is mid-typing; it catches up once the state agrees.

function t.refresh_does_not_clobber_a_field_being_typed_then_catches_up()
    resetAll()
    local state = { settings = settings.defaults() }
    local calls, send = recordingSend()
    local generalComp = schemaForm.build("general", state, send)

    local row = findLayoutByFirstLabel(generalComp, _(settings.row("lock.prefix").label))
    local field = row.children[2]

    field:setText("ab", true) -- the player types; the engine has not echoed this back yet
    eq(calls[#calls].param.value, "ab")

    schemaForm.refresh(state) -- state.settings.lock.prefix is still "" here
    eq(field:getText(), "ab", "refresh must not overwrite what the player just typed")

    assert(settings.set(state.settings, "lock.prefix", "ab")) -- the engine echoes it back
    schemaForm.refresh(state)
    eq(field:getText(), "ab")

    assert(settings.set(state.settings, "lock.prefix", "Cst")) -- then a preset changes it further
    schemaForm.refresh(state)
    eq(field:getText(), "Cst", "refresh should show the newer value once the echo caught up")
end

-- 8. slider construction failure falls back to a text field; exactly one info log line is written. -

function t.slider_construction_failure_falls_back_to_a_text_field()
    resetAll()
    api.gui.comp.Slider.new = function() error("no slider in this build") end

    log.reset()
    local lines = {}
    log.sink = function(s) lines[#lines + 1] = s end

    local state = { settings = settings.defaults() }
    local calls, send = recordingSend()
    local advancedComp = schemaForm.build("advanced", state, send)

    local row = findLayoutByFirstLabel(advancedComp, _(settings.row("scan.linesPerTick").label))
    local field = row.children[2]
    eq(field.class, "comp.TextInputField")

    field:setText("12", true)
    eq(#calls, 1)
    eq(calls[1].param.path, "scan.linesPerTick")
    eq(calls[1].param.value, 12)

    local before = #calls
    field:setText("abc", true)
    eq(#calls, before, "an unparsable number must not send anything")

    eq(#lines, 1, "exactly one info log line should have been written for the whole build, not one per row")
end

-- 9. fix round 1 / F1: the slider fallback's text field must not be clobbered while the player is
-- mid-edit on text that does not parse yet (most commonly: they cleared it to type a fresh
-- number), and must catch up once sync's own timeout lets a refresh through. -----------------------

function t.fallback_field_survives_unparsable_text_until_sync_times_out_then_catches_up()
    local clock = newClock()
    resetAll(clock.now)
    api.gui.comp.Slider.new = function() error("no slider in this build") end

    log.reset() -- silence the (expected, already covered by case 8) slider-fallback log line
    log.sink = function() end

    local state = { settings = settings.defaults() }
    local calls, send = recordingSend()
    local advancedComp = schemaForm.build("advanced", state, send)

    local row = findLayoutByFirstLabel(advancedComp, _(settings.row("scan.linesPerTick").label))
    local field = row.children[2]
    eq(field.class, "comp.TextInputField")
    eq(field:getText(), "5")

    -- Reproduces the bug: clearing the field to type a fresh number must not let an immediate
    -- refresh (with the unchanged old state) snap it back.
    field:setText("", true)
    eq(#calls, 0, "clearing to type a fresh number must not send anything")
    schemaForm.refresh(state) -- state.settings.scan.linesPerTick is still 5 here
    eq(field:getText(), "", "refresh must not overwrite text the player is still typing")

    -- Typing a real number still sends it, and the engine's echo is still accepted cleanly.
    field:setText("12", true)
    eq(#calls, 1)
    eq(calls[1].name, "set")
    eq(calls[1].param.path, "scan.linesPerTick")
    eq(calls[1].param.value, 12)
    assert(settings.set(state.settings, "scan.linesPerTick", 12)) -- the engine echoes it back
    schemaForm.refresh(state)
    eq(field:getText(), "12")

    -- Clear it again (unparsable) and let sync's timeout elapse: only then may a refresh win.
    field:setText("", true)
    clock.advance(sync.TIMEOUT)
    schemaForm.refresh(state)
    eq(field:getText(), "12", "once the timeout passes, a refresh may show the real value again")
end

-- 10. build()'s scroll area is capped to the same size as the other tabs' scroll areas. --------------

function t.scroll_area_has_the_shared_maximum_size()
    resetAll()
    local state = { settings = settings.defaults() }
    local __, send = recordingSend()
    local scrollArea = schemaForm.build("general", state, send)

    local sizeCall = nil
    for __, call in ipairs(scrollArea.calls) do
        if call.name == "setMaximumSize" then sizeCall = call end
    end
    assert(sizeCall, "expected a setMaximumSize call on the scroll area")
    eq(sizeCall.args[1].args[1], 860)
    eq(sizeCall.args[1].args[2], 380)
end

-- 11 (X5). Every CheckBox and TextInputField is constructed with a string. Both classes document
-- a :new(text) taking one, and every call proven in the game passes one (this mod's own Lines tab
-- and Patterns tab included); a bare new() is the unproven shape, and this form had three.

function t.checkboxes_and_text_fields_are_constructed_with_a_string()
    local function checkAll(root)
        local widgets = fakeGui.findAll(root, function(w)
            return w.class == "comp.CheckBox" or w.class == "comp.TextInputField"
        end)
        for __, widget in ipairs(widgets) do
            eq(type(widget.args[1]), "string", widget.class .. " must be constructed with a string")
        end
        return #widgets
    end

    resetAll()
    local state = { settings = settings.defaults() }
    local __, send = recordingSend()
    local found = checkAll(schemaForm.build("general", state, send))
        + checkAll(schemaForm.build("advanced", state, send))
    assert(found >= 2, "expected a checkbox and a text field among the built rows")

    -- And the third site: the text field every numeric row falls back to with no Slider.
    resetAll()
    log.reset()
    log.sink = function() end
    api.gui.comp.Slider.new = function() error("no slider in this build") end
    assert(checkAll(schemaForm.build("advanced", state, send)) >= 1)
end

-- 12 (X6). One editor that cannot be read or written costs its own row, not the refresh. The
-- Slider's getValue/setValue are the unproven pair, so that is the one broken here.

local function captureLog()
    log.reset()
    local lines = {}
    log.sink = function(s) lines[#lines + 1] = s end
    return lines
end

function t.a_failing_editor_does_not_stop_the_other_rows_refreshing()
    resetAll()
    local lines = captureLog()
    local state = { settings = settings.defaults() }
    local __, send = recordingSend()
    local advancedComp = schemaForm.build("advanced", state, send)

    local sliderRow = findLayoutByFirstLabel(advancedComp, _(settings.row("scan.linesPerTick").label))
    local slider = fakeGui.find(sliderRow.children[2], function(w) return w.class == "comp.Slider" end)
    assert(slider, "expected a slider on the numeric row")
    slider.getValue = function() error("boom: Slider:getValue") end

    local sepRow = findLayoutByFirstLabel(advancedComp, _(settings.row("sep.towns").label))
    local sepField = fakeGui.find(sepRow, function(w) return w.class == "comp.TextInputField" end)
    assert(sepField, "expected a text field on the separator row")

    assert(settings.set(state.settings, "sep.towns", " / "))
    assert(settings.set(state.settings, "scan.linesPerTick", 9))
    local ok, err = pcall(schemaForm.refresh, state)
    assert(ok, "refresh must not raise: " .. tostring(err))
    eq(sepField:getText(), " / ", "every other row must still refresh")
    eq(#lines, 1, "the failing editor should be logged once")
end

-- 13 (X6). A row that cannot be built is replaced by a notice; the rest of the tab still builds.

function t.a_row_that_cannot_be_built_is_replaced_by_a_notice()
    resetAll()
    local lines = captureLog()
    local state = { settings = settings.defaults() }
    local __, send = recordingSend()

    local targetLabel = settings.row("sep.towns").label
    local realButtonFor = help.buttonFor
    help.buttonFor = function(label, text)
        if label == targetLabel then error("boom: this row") end
        return realButtonFor(label, text)
    end
    local ok, advancedComp = pcall(schemaForm.build, "advanced", state, send)
    help.buttonFor = realButtonFor
    assert(ok, "build must not raise: " .. tostring(advancedComp))

    local notice = fakeGui.find(advancedComp, function(w)
        return w.class == "comp.TextView" and (fakeGui.text(w) or ""):find("(could not be shown)", 1, true)
    end)
    assert(notice, "the failing row must be replaced by a notice")
    assert(fakeGui.text(notice):find(_(targetLabel), 1, true), "the notice must name the row")
    assert(findLayoutByFirstLabel(advancedComp, _(settings.row("sep.via").label)),
        "the rows after the failing one must still be built")
    eq(#lines, 1, "the failing row should be logged once")
end

return t
