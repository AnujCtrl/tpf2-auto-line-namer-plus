-- Tests for gui/window.lua: the window shell, the top-bar button, the four tabs and their info
-- buttons, and update()'s refresh-on-version-change behaviour.
local fakeGui = require("fake_gui")
local fake = require("fake_api")
local eq = fake.eq
local log = require("anujctrl/alnp/log")
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
    window.reset()
    window.init(noopSend)

    local gameInfo = api.gui.util.getById("gameInfo")
    local buttons = fakeGui.findAll(gameInfo, function(w) return w.class == "comp.Button" end)
    eq(#buttons, 1)
end

-- 2. clicking the top-bar button shows the window; clicking again hides it. -----------------------

function t.clicking_topbar_button_toggles_window_visibility()
    help.reset()
    window.reset()
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
    window.reset()
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
    window.reset() -- X4: init is a no-op while a window from an earlier test is still remembered
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
    window.reset() -- X4: init is a no-op while a window from an earlier test is still remembered
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
    window.reset()
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

    window.reset()
    window.init(noopSend) -- must not raise

    local sawError = false
    for __, line in ipairs(lines) do
        if line:find("gameInfo", 1, true) then sawError = true end
    end
    assert(sawError, "expected a logged error mentioning gameInfo")
end

-- 7 (X1). One tab builder raising costs that tab alone. ------------------------------------------

local FAILED_TAB_TEXT = "This tab could not be built; see stdout.txt for an aln_plus: line."

-- Replaces module[key] with one that raises. `only` (a schemaForm tabKey) narrows it to one of
-- the two tabs that share schemaForm.build. Returns the restore function.
local function breakMethod(module, key, only)
    local real = module[key]
    module[key] = function(first, ...)
        if only == nil or first == only then error("boom: " .. key) end
        return real(first, ...)
    end
    return function() module[key] = real end
end

local function captureLog()
    log.reset()
    local lines = {}
    log.sink = function(line) lines[#lines + 1] = line end
    return lines
end

local function countCalls(widget, name)
    local n = 0
    for __, call in ipairs(widget.calls) do
        if call.name == name then n = n + 1 end
    end
    return n
end

local function findText(root, text)
    return fakeGui.find(root, function(w)
        return w.class == "comp.TextView" and fakeGui.text(w) == text
    end)
end

local function topBarButton()
    return fakeGui.find(api.gui.util.getById("gameInfo"), function(w) return w.class == "comp.Button" end)
end

function t.a_failing_tab_builder_costs_only_its_own_tab()
    local cases = {
        { module = schemaForm, key = "build", only = "general" },
        { module = schemaForm, key = "build", only = "advanced" },
        { module = patternsTab, key = "build" },
        { module = linesTab, key = "build" },
    }
    for __, case in ipairs(cases) do
        fake.reset()
        local lines = captureLog()
        help.reset()
        window.reset()
        local getWindow = fakeGui.captureNew("comp.Window")
        local restore = breakMethod(case.module, case.key, case.only)
        local ok, err = pcall(window.init, noopSend)
        restore()
        assert(ok, "window.init must not raise: " .. tostring(err))

        local root = getWindow()
        assert(root, "the window must still be built")
        local tabWidget = fakeGui.find(root, function(w) return w.class == "comp.TabWidget" end)
        assert(tabWidget, "the window must still have a TabWidget")
        eq(countCalls(tabWidget, "addTab"), 4)
        assert(topBarButton(), "the top-bar button must still be added")
        assert(findText(root, FAILED_TAB_TEXT), "the failing tab must show the notice")
        eq(#lines, 1, "exactly one error should be logged")
    end
end

-- 8 (X2). The top-bar button is not hostage to the window build. ---------------------------------

-- Makes `method` raise on every widget of `className` built from now on, by wrapping that class's
-- own "new" (as fakeGui.captureNew does) and rawsetting the method on each instance, which
-- shadows the fake's strict __index. Returns the restore function.
local function breakWidgetMethod(className, method)
    local ns, name = className:match("^(%a+)%.([%w]+)$")
    local target = api.gui[ns][name]
    local realNew = target.new
    target.new = function(...)
        local widget = realNew(...)
        widget[method] = function() error("boom: " .. className .. ":" .. method) end
        return widget
    end
    return function() target.new = realNew end
end

function t.the_topbar_button_survives_a_failing_window_constructor()
    fake.reset()
    local lines = captureLog()
    help.reset()
    window.reset()
    local target = api.gui.comp.Window
    local realNew = target.new
    target.new = function() error("boom: comp.Window.new") end
    local ok, err = pcall(window.init, noopSend)
    target.new = realNew
    assert(ok, "window.init must not raise: " .. tostring(err))

    local button = topBarButton()
    assert(button, "the top-bar button must be added before the window is built")
    eq(#lines, 1, "the failing constructor should be the only thing logged so far")
    fakeGui.click(button)
    fakeGui.click(button)
    eq(#lines, 2, "a click with no window logs once and does nothing")
end

function t.a_failing_setSize_or_setResizable_does_not_lose_the_window()
    for __, method in ipairs({ "setSize", "setResizable" }) do
        fake.reset()
        local lines = captureLog()
        help.reset()
        window.reset()
        local getWindow = fakeGui.captureNew("comp.Window")
        local restore = breakWidgetMethod("comp.Window", method)
        local ok, err = pcall(window.init, noopSend)
        restore()
        assert(ok, "window.init must not raise on " .. method .. ": " .. tostring(err))

        assert(getWindow(), "the window must survive a failing " .. method)
        eq(#lines, 1, "only the failing " .. method .. " should be logged")
        local button = topBarButton()
        assert(button, "the top-bar button must still be there")
        fakeGui.click(button)
        eq(getWindow():isVisible(), true, "the window must still toggle after a failing " .. method)
    end
end

-- 9 (X3). A failing tab refresh costs that tab's refresh alone, and is not replayed forever. -----

function t.a_failing_tab_refresh_does_not_block_the_other_two()
    fake.reset()
    help.reset()
    window.reset()
    window.setState(newState(0))
    local getWindow = fakeGui.captureNew("comp.Window")
    window.init(noopSend)
    getWindow():setVisible(true, false)

    local lines = captureLog()
    local counts = countRefreshes()
    local restore = breakMethod(schemaForm, "refresh")
    window.setState(newState(1))
    local ok, err = pcall(window.update)
    restore()
    assert(ok, "window.update must not raise: " .. tostring(err))

    eq(counts.schemaForm, 0, "the broken refresh never reached the real one")
    eq(counts.patternsTab, 1, "the patterns tab must still refresh")
    eq(counts.linesTab, 1, "the lines tab must still refresh")
    eq(#lines, 1, "exactly one error should be logged")

    -- The version still counts as refreshed, so the next frame does no work at all.
    window.update()
    eq(counts.patternsTab, 1)
    eq(counts.linesTab, 1)
end

-- 10 (X4). A second init in the same Lua state is a no-op, not a second window. ------------------

function t.init_twice_builds_one_window_and_one_button()
    fake.reset()
    help.reset()
    window.reset()
    local built = 0
    local target = api.gui.comp.Window
    local realNew = target.new
    target.new = function(...)
        built = built + 1
        return realNew(...)
    end

    window.init(noopSend)
    window.init(noopSend)
    target.new = realNew

    eq(built, 1, "the second init must not build a second window")
    local gameInfo = api.gui.util.getById("gameInfo")
    eq(#fakeGui.findAll(gameInfo, function(w) return w.class == "comp.Button" end), 1)

    -- reset() still puts the module back to "no window", so the next init builds again.
    window.reset()
    target.new = function(...)
        built = built + 1
        return realNew(...)
    end
    window.init(noopSend)
    target.new = realNew
    eq(built, 2, "after reset() a fresh init must build again")
end

return t
