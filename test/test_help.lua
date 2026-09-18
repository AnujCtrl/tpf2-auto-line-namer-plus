-- Tests for the strict GUI fake (test/fake_gui.lua) and the help system
-- (help_topics.lua, gui/help.lua).
local fakeGui = require("fake_gui")
local eq = require("fake_api").eq
local log = require("anujctrl/alnp/log")
local topics = require("anujctrl/alnp/help_topics")
local help = require("anujctrl/alnp/gui/help")
local naming = require("anujctrl/alnp/naming")

local t = {}

-- Upstream alias -> its current name, per spec §7 / naming.lua's own ALIASES table (not exported,
-- so checked by behaviour below rather than by reaching into naming.lua's internals).
local UPSTREAM_ALIASES = {
    { alias = "{transportType}", canonical = "{type}" },
    { alias = "{lineType}", canonical = "{scope}" },
    { alias = "{cargoTypes}", canonical = "{cargo}" },
    { alias = "{townNames}", canonical = "{towns}" },
    { alias = "{lineNumber}", canonical = "{n}" },
}

local BUS_TOOL_PATH = "/home/anujp/Documents/personal/tpf2-mods/tpf2-bus-line-tool/res/scripts/bus_line_tool_window.lua"

local REQUIRED_KEYS = {
    "topbar.button", "window.overview", "tab.general", "tab.advanced", "tab.patterns", "tab.lines",
    "patterns.preset", "patterns.default", "patterns.kind", "patterns.autoRename", "patterns.custom",
    "patterns.tokens", "lines.col.apply", "lines.col.kind", "lines.col.current", "lines.col.proposed",
    "lines.col.lock", "lines.col.renameNow", "lines.previewAll", "lines.applyChecked",
    "reset.section", "reset.all", "advanced.apiCheck",
}

local function captureLog()
    log.reset()
    local lines = {}
    log.sink = function(s) lines[#lines + 1] = s end
    return lines
end

-- 1. fake: undocumented method / unknown class raise; inherited method works. -------------------

function t.fake_undocumented_method_raises_with_class_and_method_names()
    local button = api.gui.comp.Button.new(api.gui.comp.TextView.new("i"), true)
    local ok, err = pcall(function() button:setLabel("x") end)
    assert(not ok, "setLabel should not be a real Button method")
    assert(tostring(err):find("comp.Button", 1, true), err)
    assert(tostring(err):find("setLabel", 1, true), err)
end

function t.fake_unknown_class_raises()
    local ok = pcall(function() return api.gui.comp.Frobnicator.new() end)
    assert(not ok, "Frobnicator is not a documented class")
end

-- A class is documented (it has a heading in the API docs) but that does not mean it documents
-- its own :new -- an abstract base or a class the game hands out itself, never built by a mod.
-- new must not be inherited from a base class either way.
function t.fake_new_is_not_inherited_and_not_assumed()
    local noConstructor = {
        "comp.AbstractSlider", "comp.ContentView", "comp.GameUI",
        "comp.ILayoutItem", "comp.RendererComponent",
        "layout.ILayout", "layout.LayoutBase",
    }
    for __, className in ipairs(noConstructor) do
        local ns, name = className:match("^(%a+)%.(%a[%w]*)$")
        local ok, err = pcall(function() return api.gui[ns][name].new() end)
        assert(not ok, className .. ".new should not be constructible")
        assert(tostring(err):find(className, 1, true), err)
        assert(tostring(err):find("no method 'new'", 1, true), err)
    end

    -- Classes that DO document their own constructor must still work, including one (Slider)
    -- whose base (AbstractSlider) does not document a constructor at all.
    assert(api.gui.comp.Button.new(api.gui.comp.TextView.new("i"), true))
    assert(api.gui.layout.BoxLayout.new("VERTICAL"))
    assert(api.gui.comp.Slider.new())
end

function t.fake_inherited_method_works()
    -- setTooltip is documented on comp.Component, an ancestor of comp.Button.
    local button = api.gui.comp.Button.new(api.gui.comp.TextView.new("i"), true)
    button:setTooltip("hi")
    eq(button.tooltip, "hi")
end

-- 2. fake: handlers fire; find/allText traverse addItem/addTab/setLayout/addRow/constructors. ---

function t.fake_click_and_emit_signal_fire_handlers()
    local clicked = false
    local button = api.gui.comp.Button.new(api.gui.comp.TextView.new("go"), true)
    button:onClick(function() clicked = true end)
    fakeGui.click(button)
    assert(clicked, "fakeGui.click should fire onClick")

    local toggled = nil
    local checkbox = api.gui.comp.CheckBox.new("Enabled")
    checkbox:onToggle(function(v) toggled = v end)
    checkbox:setSelected(true, true)
    eq(toggled, true)
end

function t.fake_find_and_allText_see_nested_structure()
    local root = api.gui.comp.Component.new("root")
    local layout = api.gui.layout.BoxLayout.new("VERTICAL")
    root:setLayout(layout) -- setLayout

    local tabs = api.gui.comp.TabWidget.new("NORTH")
    layout:addItem(tabs) -- addItem
    tabs:addTab(api.gui.comp.TextView.new("Tab one"), api.gui.comp.TextView.new("Tab body")) -- addTab

    local table_ = api.gui.comp.Table.new(1, "NONE")
    layout:addItem(table_)
    table_:addRow({ api.gui.comp.TextView.new("Row text") }) -- addRow

    layout:addItem(api.gui.comp.Button.new(api.gui.comp.TextView.new("Click me"), true)) -- constructor arg

    local found = fakeGui.find(root, function(w)
        return w.class == "comp.TextView" and fakeGui.text(w) == "Row text"
    end)
    assert(found, "find should reach a TextView added via addRow")

    local text = fakeGui.allText(root)
    for __, expected in ipairs({ "Tab one", "Tab body", "Row text", "Click me" }) do
        assert(text:find(expected, 1, true), "allText missing '" .. expected .. "': " .. text)
    end
end

-- comp.ComboBox:addItem takes a plain string, so a widget's children can hold bare strings
-- alongside widgets (unlike every other addItem in the two proven files). allText must still see
-- them, and find/findAll must treat them as leaves rather than handing them to a predicate.
function t.fake_allText_and_find_handle_a_combobox_with_string_items()
    local root = api.gui.comp.Component.new("root")
    local layout = api.gui.layout.BoxLayout.new("VERTICAL")
    root:setLayout(layout)

    local combo = api.gui.comp.ComboBox.new()
    combo:addItem("First choice")
    combo:addItem("Second choice")
    layout:addItem(combo)

    local text = fakeGui.allText(root)
    assert(text:find("First choice", 1, true), text)
    assert(text:find("Second choice", 1, true), text)

    local everyPredicateArgWasATable = true
    local found = fakeGui.find(root, function(w)
        if type(w) ~= "table" then everyPredicateArgWasATable = false end
        return false
    end)
    assert(found == nil)
    assert(everyPredicateArgWasATable, "find must never hand a string to the predicate")

    local all = fakeGui.findAll(root, function(w)
        if type(w) ~= "table" then everyPredicateArgWasATable = false end
        return w.class == "comp.ComboBox"
    end)
    assert(#all == 1)
    assert(everyPredicateArgWasATable, "findAll must never hand a string to the predicate")
end

-- 3. fake: every api.gui.<ns>.<Class>.new and every :method( call in the two proven sources. -----

function t.fake_accepts_every_call_in_the_two_proven_source_files()
    local sources = {}

    local upstreamPipe = io.popen("git show 748b16c:res/scripts/abajuradam/auto_line_namer_gui.lua 2>/dev/null")
    local upstreamText = upstreamPipe and upstreamPipe:read("*a") or nil
    if upstreamPipe then upstreamPipe:close() end
    if upstreamText and #upstreamText > 0 then
        sources[#sources + 1] = upstreamText
    else
        print("note: could not read upstream auto_line_namer_gui.lua via git show; skipping that half of test 3")
    end

    local busToolFile = io.open(BUS_TOOL_PATH, "r")
    if busToolFile then
        sources[#sources + 1] = busToolFile:read("*a")
        busToolFile:close()
    else
        print("note: " .. BUS_TOOL_PATH .. " not found; skipping that half of test 3")
    end

    assert(#sources > 0, "neither proven source file could be read")

    -- The union of method names permitted on *some* class (own or inherited via the documented
    -- base chain, plus PROVEN). The receiver's real class is unknown to a regex, so this is the
    -- check the brief asks for.
    local anyClassAllows = {}
    for className, info in pairs(fakeGui.classes) do
        for method in pairs(info.methods) do
            anyClassAllows[method] = true
        end
    end

    for __, text in ipairs(sources) do
        -- Strip line comments: a commented-out call never runs in the game.
        local cleaned = text:gsub("%-%-[^\n]*", "")

        for ns, className in cleaned:gmatch("api%.gui%.(%a+)%.([%a][%w]*)%.new%(") do
            local ok = pcall(function() return api.gui[ns][className].new() end)
            assert(ok, "api.gui." .. ns .. "." .. className .. ".new should be accepted by the fake")
        end

        for method in cleaned:gmatch(":([%a_][%w_]*)%(") do
            assert(anyClassAllows[method], "no documented or PROVEN class allows method '" .. method .. "'")
        end

        -- Bare util functions, e.g. api.gui.util.getMouseScreenPos( -- not a :method( call (no
        -- receiver) and not a .new( class construction, so neither loop above would see it.
        for name in cleaned:gmatch("api%.gui%.util%.([%a][%w]*)%(") do
            assert(type(api.gui.util[name]) == "function",
                "api.gui.util." .. name .. " should be a callable function")
        end
    end
end

-- Extra: test 3 only checks that *some* class allows a method name, which would pass even if a
-- PROVEN entry were attributed to the wrong class. Exercise each one directly on its real class.
function t.fake_proven_entries_work_on_their_actual_classes()
    local layout = api.gui.layout.BoxLayout.new("VERTICAL")
    local child = api.gui.comp.TextView.new("x")
    layout:addItem(child)
    eq(layout:getNumItems(), 1)
    eq(layout:getItem(0), child)
    layout:removeItem(child)
    eq(layout:getNumItems(), 0)

    local imageView = api.gui.comp.ImageView.new(" ")
    eq(imageView.class, "comp.ImageView")

    local combo = api.gui.comp.ComboBox.new()
    combo:addItem("a")
    combo:setSelected(0, false)
    eq(combo:getCurrentIndex(), 0)
    combo:removeItem(0)
end

-- Extra: the util functions used unconditionally by the proven bus tool file (getGameUI's whole
-- chain down to a camera, and getMouseScreenPos) actually work, not just "exist as a function".
function t.fake_models_getGameUI_chain_and_getMouseScreenPos()
    local pos = api.gui.util.getMouseScreenPos()
    eq(type(pos.x), "number")
    eq(type(pos.y), "number")

    local gameUI = api.gui.util.getGameUI()
    eq(gameUI.class, "comp.GameUI")
    assert(api.gui.util.getGameUI() == gameUI, "getGameUI should return the same singleton")

    local renderer = gameUI:getMainRendererComponent()
    eq(renderer.class, "comp.RendererComponent")
    assert(gameUI:getMainRendererComponent() == renderer, "one renderer per GameUI")

    local rect = renderer:getContentRect()
    eq(type(rect.x), "number")
    eq(type(rect.w), "number")

    local camera = renderer:getCameraController()
    eq(camera.class, "util.CameraController")
    camera:focus("someEntity") -- must not raise
end

-- 4. topics: coverage, uniqueness, non-empty, line length, get("nope"). --------------------------

function t.topics_cover_every_required_key_with_valid_text()
    for __, key in ipairs(REQUIRED_KEYS) do
        local topic = topics.get(key)
        assert(topic, "missing topic '" .. key .. "'")
        assert(topic.title and #topic.title > 0, key .. " has no title")
        assert(topic.text and #topic.text > 0, key .. " has no text")
    end

    local seen = {}
    for __, topic in ipairs(topics.list) do
        assert(not seen[topic.key], "duplicate topic key '" .. topic.key .. "'")
        seen[topic.key] = true
        for line in (topic.text .. "\n"):gmatch("(.-)\n") do
            assert(#line <= 72, topic.key .. " has a line over 72 characters: '" .. line .. "'")
        end
    end

    assert(topics.get("nope") == nil)
end

-- The task brief requires the token cheat-sheet topic to name every upstream alias explicitly, so
-- a player migrating a pattern from the original mod can find the mapping. A plain (non-pattern)
-- find: both the braces and the alias name are literal text to look for, not Lua pattern syntax.
function t.tokens_topic_names_every_upstream_alias_with_its_new_name()
    local text = topics.get("patterns.tokens").text
    for __, pair in ipairs(UPSTREAM_ALIASES) do
        assert(text:find(pair.alias, 1, true),
            "patterns.tokens text does not mention the alias " .. pair.alias)
    end
end

-- help_topics.lua's list of aliases must not drift from naming.lua's actual ALIASES table.
-- naming.lua does not export that table, so this checks behaviour instead: rendering a pattern
-- built from the alias must equal rendering the same pattern built from the canonical token.
function t.tokens_topic_aliases_match_namings_actual_behaviour()
    local facts = naming.sampleFacts("bus")
    local settings = {
        label = { kind = { bus = "Bus" }, scope = { intercity = "Intercity" } },
        sep = { towns = " - ", via = ", ", cargo = ", " },
        cargo = { max = 2, mixedLabel = "Mixed", hidePassengers = true },
        via = { max = 2 },
        industry = { fallback = "stop" },
        number = { first = "blank", pad = 0 },
    }
    local ctx = { settings = settings, kind = "bus", scope = "intercity", n = nil }

    for __, pair in ipairs(UPSTREAM_ALIASES) do
        eq(naming.render(pair.alias, facts, ctx), naming.render(pair.canonical, facts, ctx),
            pair.alias .. " should render the same as " .. pair.canonical)
    end
end

-- 5. help: button shows topic in panel; a second button replaces it; Close hides; panel() caches. -

function t.help_button_shows_topic_and_next_click_replaces_it()
    help.reset()

    local lockTopic = topics.get("lines.col.lock")
    local lockButton = help.button("lines.col.lock")
    eq(lockButton.tooltip, lockTopic.text)

    fakeGui.click(lockButton)
    local panel = help.panel()
    eq(panel.visible, true)
    assert(fakeGui.find(panel, function(w) return w.class == "comp.TextView" and fakeGui.text(w) == lockTopic.title end))
    assert(fakeGui.find(panel, function(w) return w.class == "comp.TextView" and fakeGui.text(w) == lockTopic.text end))

    local applyTopic = topics.get("lines.col.apply")
    local applyButton = help.button("lines.col.apply")
    fakeGui.click(applyButton)
    eq(panel.visible, true)
    assert(fakeGui.find(panel, function(w) return w.class == "comp.TextView" and fakeGui.text(w) == applyTopic.text end))
    assert(not fakeGui.find(panel, function(w) return w.class == "comp.TextView" and fakeGui.text(w) == lockTopic.text end),
        "the previous topic's text should have been replaced")

    local closeLabel = fakeGui.find(panel, function(w) return w.class == "comp.TextView" and fakeGui.text(w) == "Close" end)
    assert(closeLabel, "panel should have a Close button")
    local closeButton = fakeGui.find(panel, function(w) return w.class == "comp.Button" and w.children[1] == closeLabel end)
    assert(closeButton)
    fakeGui.click(closeButton)
    eq(panel.visible, false)
end

function t.help_panel_returns_the_same_object_every_call()
    help.reset()
    local first = help.panel()
    local second = help.panel()
    assert(first == second)
end

-- 6. help: unknown topic key logs once and falls back; show before panel() does not raise. -------

function t.help_button_for_unknown_topic_logs_once_and_falls_back()
    help.reset()
    local lines = captureLog()

    local button = help.button("no.such.topic")
    eq(#lines, 1)
    assert(lines[1]:find("no help topic 'no.such.topic'", 1, true), lines[1])
    eq(button.tooltip, "No help has been written for this yet.")
end

function t.help_show_before_panel_created_does_not_raise()
    help.reset()
    local ok = pcall(function() help.show("Title", "Text") end)
    assert(ok, "help.show should create the panel lazily")
    eq(help.panel().visible, true)
end

-- 7. help: labelled contains a TextView with the label and an "i" info button. -------------------

function t.help_labelled_contains_text_view_and_info_button()
    help.reset()
    local component = help.labelled("Lock", "lines.col.lock")

    assert(fakeGui.find(component, function(w) return w.class == "comp.TextView" and fakeGui.text(w) == "Lock" end),
        "labelled should contain a TextView with the label text")

    local iLabel = fakeGui.find(component, function(w) return w.class == "comp.TextView" and fakeGui.text(w) == "i" end)
    assert(iLabel, "labelled should contain an 'i' info button")
    assert(fakeGui.find(component, function(w) return w.class == "comp.Button" and w.children[1] == iLabel end),
        "the 'i' TextView should be wrapped in a Button")
end

return t
