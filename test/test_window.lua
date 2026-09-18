-- Tests for gui/window.lua: the window shell, the top-bar button, the four tabs and their info
-- buttons, and update()'s refresh-on-version-change behaviour.
local fakeGui = require("fake_gui")
local eq = require("fake_api").eq
local help = require("anujctrl/alnp/gui/help")
local topics = require("anujctrl/alnp/help_topics")
local settings = require("anujctrl/alnp/settings")
local schemaForm = require("anujctrl/alnp/gui/schema_form")
local patternsTab = require("anujctrl/alnp/gui/patterns_tab")
local linesTab = require("anujctrl/alnp/gui/lines_tab")
local window = require("anujctrl/alnp/gui/window")

local t = {}

-- Wraps refresh(state) on all three tab modules to count calls, so update()'s "refresh only when
-- visible and the version changed" rule can be checked without inspecting widget values.
local function countRefreshes()
    local counts = { schemaForm = 0, patternsTab = 0, linesTab = 0 }
    local originals = { schemaForm = schemaForm.refresh, patternsTab = patternsTab.refresh, linesTab = linesTab.refresh }
    schemaForm.refresh = function(...)
        counts.schemaForm = counts.schemaForm + 1
        return originals.schemaForm(...)
    end
    patternsTab.refresh = function(...)
        counts.patternsTab = counts.patternsTab + 1
        return originals.patternsTab(...)
    end
    linesTab.refresh = function(...)
        counts.linesTab = counts.linesTab + 1
        return originals.linesTab(...)
    end
    return counts
end

local function newState(version)
    return { settings = settings.defaults(), records = {}, version = version }
end

-- Every help.button (real topic key or generated helpText) sets a tooltip; count how many buttons
-- in the tree carry the given topic's exact text somewhere in their tooltip.
local function countButtonsWithTooltip(root, key)
    local text = topics.get(key).text
    return #fakeGui.findAll(root, function(w)
        return w.class == "comp.Button" and rawget(w, "tooltip") == _(text)
    end)
end

local function noopSend(__, ___) end

-- 1. init adds exactly one button to the game-info bar. -------------------------------------------

function t.init_adds_exactly_one_button_to_gameInfo()
    help.reset()
    window.setState(nil)
    window.init(noopSend)

    local gameInfo = api.gui.util.getById("gameInfo")
    local buttons = fakeGui.findAll(gameInfo, function(w) return w.class == "comp.Button" end)
    eq(#buttons, 1)
end

-- 2. clicking the top-bar button shows the window; clicking again hides it. -----------------------

function t.clicking_topbar_button_toggles_window_visibility()
    help.reset()
    window.setState(nil)
    local getWindow = fakeGui.captureNew("comp.Window")
    window.init(noopSend)

    local windowWidget = getWindow()
    assert(windowWidget, "window.init should construct a comp.Window")
    eq(windowWidget:isVisible(), false)

    local gameInfo = api.gui.util.getById("gameInfo")
    local button = fakeGui.find(gameInfo, function(w) return w.class == "comp.Button" end)
    fakeGui.click(button)
    eq(windowWidget:isVisible(), true)
    fakeGui.click(button)
    eq(windowWidget:isVisible(), false)
end

-- 3. the window has four tabs; the overview and each tab carry their info buttons. ----------------

function t.window_has_four_tabs_with_info_buttons_on_overview_and_each_tab()
    help.reset()
    window.setState(nil)
    local getWindow = fakeGui.captureNew("comp.Window")
    window.init(noopSend)
    local root = getWindow()

    eq(countButtonsWithTooltip(root, "window.overview"), 1)

    local tabWidget = fakeGui.find(root, function(w) return w.class == "comp.TabWidget" end)
    assert(tabWidget, "window should contain a TabWidget")
    local addTabCalls = 0
    for __, call in ipairs(tabWidget.calls) do
        if call.name == "addTab" then addTabCalls = addTabCalls + 1 end
    end
    eq(addTabCalls, 4)

    for __, entry in ipairs({
        { text = "General", topic = "tab.general" },
        { text = "Advanced", topic = "tab.advanced" },
        { text = "Patterns", topic = "tab.patterns" },
        { text = "Lines", topic = "tab.lines" },
    }) do
        assert(fakeGui.find(root, function(w) return w.class == "comp.TextView" and fakeGui.text(w) == entry.text end),
            "missing tab label " .. entry.text)
        eq(countButtonsWithTooltip(root, entry.topic), 1)
    end
end

-- 4. update() with the window hidden refreshes nothing, even when the version changed. -----------

function t.update_with_window_hidden_refreshes_nothing()
    help.reset()
    window.setState(newState(0))
    window.init(noopSend)
    local counts = countRefreshes()

    window.setState(newState(1))
    window.update()

    eq(counts.schemaForm, 0)
    eq(counts.patternsTab, 0)
    eq(counts.linesTab, 0)
end

-- 5. with the window visible, a new version refreshes each tab once; the same version again does
-- not (linesTab.update() still runs every time, visible or not -- it is cheap when idle). --------

function t.update_with_window_visible_refreshes_once_per_new_version()
    help.reset()
    window.setState(newState(0))
    local getWindow = fakeGui.captureNew("comp.Window")
    window.init(noopSend)
    getWindow():setVisible(true, false)

    local counts = countRefreshes()

    window.setState(newState(1))
    window.update()
    eq(counts.schemaForm, 1)
    eq(counts.patternsTab, 1)
    eq(counts.linesTab, 1)

    window.update() -- same version (still 1): no further refresh
    eq(counts.schemaForm, 1)
    eq(counts.patternsTab, 1)
    eq(counts.linesTab, 1)
end

-- 5b (A4). The window is given a size; without one the game opens it collapsed around its
-- content. Upstream used 850 by 500; this mod's Lines table needs more room, so 900 by 600.

function t.window_is_given_a_size_of_900_by_600()
    help.reset()
    window.setState(nil)
    local getWindow = fakeGui.captureNew("comp.Window")
    window.init(noopSend)

    local sizeCall = nil
    for __, call in ipairs(getWindow().calls) do
        if call.name == "setSize" then sizeCall = call end
    end
    assert(sizeCall, "window.init must call setSize on the window")
    local size = sizeCall.args[1]
    assert(type(size) == "table" and size.class == "util.Size", "setSize takes an api.gui.util.Size")
    eq(size.args[1], 900)
    eq(size.args[2], 600)
end

-- 6. a nil gameInfo logs an error and does not raise. ----------------------------------------------

function t.nil_gameInfo_logs_an_error_and_does_not_raise()
    help.reset()
    local log = require("anujctrl/alnp/log")
    log.reset()
    local lines = {}
    log.sink = function(line) lines[#lines + 1] = line end

    local realGetById = api.gui.util.getById
    api.gui.util.getById = function(id)
        if id == "gameInfo" then return nil end
        return realGetById(id)
    end

    window.setState(nil)
    window.init(noopSend) -- must not raise

    local sawError = false
    for __, line in ipairs(lines) do
        if line:find("gameInfo", 1, true) then sawError = true end
    end
    assert(sawError, "expected a logged error mentioning gameInfo")
end

return t
