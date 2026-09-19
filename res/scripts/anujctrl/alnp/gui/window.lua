-- The window shell: the top-bar button, the window itself, its four tabs and the shared help
-- panel docked at the bottom. Owns no naming logic: every tab's content comes from its own
-- builder module. GUI-only module: may call api.gui.
local log = require "anujctrl/alnp/log"
local settings = require "anujctrl/alnp/settings"
local help = require "anujctrl/alnp/gui/help"
local help_topics = require "anujctrl/alnp/help_topics"
local schemaForm = require "anujctrl/alnp/gui/schema_form"
local patternsTab = require "anujctrl/alnp/gui/patterns_tab"
local linesTab = require "anujctrl/alnp/gui/lines_tab"

local window = {}

-- The most recently delivered state (window.setState), or nil until load() has reached the GUI
-- thread at least once. May already be non-nil when window.init runs, if load() got here first.
local state = nil
local windowComponent = nil
local lastRefreshedVersion = nil
-- The button is added before the window is built (hardening X2), so it can outlive a build that
-- never produced one; the player then gets one line in the log per session, not one per click.
local reportedMissingWindow = false

local function defaultState()
    return { settings = settings.defaults(), records = {}, version = -1 }
end

-- The top-bar button's own click handler. windowComponent is read at click time, so the button
-- may be created before -- or entirely without -- a window.
local function toggleWindow()
    if not windowComponent then
        if not reportedMissingWindow then
            reportedMissingWindow = true
            log.error("no window was built, so the [ALN+] button has nothing to show.")
        end
        return
    end
    windowComponent:setVisible(not windowComponent:isVisible(), false)
end

-- Guards against a nil gameInfo bar or a nil layout on it, exactly as upstream did, since the
-- game hands this component out and a failure here must not take the whole window build down.
local function addTopBarButton(toggleWindow)
    local gameInfo = api.gui.util.getById("gameInfo")
    if not gameInfo then
        return log.error("gameInfo component is nil.")
    end
    -- The game runs this on a later frame, after guiInit's own guard has returned, so it needs its own.
    gameInfo:invokeLater(log.wrap("window.addTopBarButton", function()
        local layout = gameInfo:getLayout()
        if not layout then
            return log.error("gameInfo layout is nil.")
        end
        local button = api.gui.comp.Button.new(api.gui.comp.TextView.new("[ALN+]"), true)
        button:onClick(log.wrap("window.topBarButton", toggleWindow))
        -- A tooltip is a nicety: neither a missing topic nor a failing setTooltip may cost the button.
        log.guard("window.topBarTooltip", function()
            local topic = help_topics.get("topbar.button")
            if topic then button:setTooltip(_(topic.text)) end
        end)
        layout:addItem(api.gui.comp.Component.new("VerticalLine"))
        layout:addItem(button)
        layout:addItem(api.gui.comp.Component.new("VerticalLine"))
    end))
end

-- The proven idiom (upstream auto_line_namer_gui.lua) passes a plain TextView as a tab's label;
-- the tab's own info button goes inside its content instead, as the first item, rather than
-- risking a compound help.labelled() component where the game may expect a simple label widget.
local function buildTab(tabWidget, topicKey, labelText, tabContent)
    local label = api.gui.comp.TextView.new(_(labelText))
    local layout = api.gui.layout.BoxLayout.new("VERTICAL")
    layout:addItem(help.button(topicKey))
    layout:addItem(tabContent)
    local wrapper = api.gui.comp.Component.new("alnpTabWrap:" .. topicKey)
    wrapper:setLayout(layout)
    tabWidget:addTab(label, wrapper)
end

-- Stands in for a tab whose content builder raised, so one bad widget call costs that tab rather
-- than the whole window (hardening X1).
local FAILED_TAB_TEXT = "This tab could not be built; see stdout.txt for an aln_plus: line."

-- Builds one tab's content under its own guard, then adds the tab under a second one: a raise in
-- either place leaves the other three tabs, the window and the top-bar button untouched.
local function addGuardedTab(tabWidget, topicKey, labelText, builder, ...)
    local content = log.guard("window.tabContent:" .. topicKey, builder, ...)
    if content == nil then
        content = api.gui.comp.TextView.new(_(FAILED_TAB_TEXT))
    end
    log.guard("window.buildTab:" .. topicKey, buildTab, tabWidget, topicKey, labelText, content)
end

-- Back to "nothing delivered yet". The game gives every loaded save fresh Lua states, so nothing
-- in the mod needs this; tests use it, because require caches this module between them.
function window.reset()
    state, windowComponent, lastRefreshedVersion = nil, nil, nil
    reportedMissingWindow = false
end

-- What load() delivers is not trusted: the game has passed non-tables here, and a state written by
-- an older version of the mod can lack settings that exist now. The tabs index the state freely,
-- so they only ever see a complete one: settings merged over the defaults, records keyed by number.
function window.setState(newState)
    if type(newState) ~= "table" or type(newState.settings) ~= "table" then return end
    if state and newState.version ~= nil and newState.version == state.version then return end
    local records = {}
    for lineId, record in pairs(type(newState.records) == "table" and newState.records or {}) do
        local id = tonumber(lineId) -- keys may arrive as strings after the trip between threads
        if id and type(record) == "table" then records[id] = record end
    end
    state = { settings = settings.merge(nil, newState.settings), records = records, version = newState.version }
end

function window.init(send)
    -- The game calls guiInit once per Lua state, but a second call has been seen in the wild and
    -- used to leave two windows and two top-bar buttons behind (hardening X4). window.reset()
    -- clears this, so a test -- or a fresh save -- still builds.
    if windowComponent then
        return log.info("the window already exists; not building a second one.")
    end
    help.reset()
    schemaForm.reset()
    patternsTab.reset()
    linesTab.reset()

    local buildState = state or defaultState()
    state = buildState

    -- First, and under its own guard: whatever the rest of this function does to itself, the
    -- player keeps the one control that opens the mod (hardening X2).
    log.guard("window.topBar", addTopBarButton, toggleWindow)

    local rootLayout = api.gui.layout.BoxLayout.new("VERTICAL")
    log.guard("window.header", function()
        rootLayout:addItem(help.labelled(_("How this works"), "window.overview"))
    end)

    local tabWidget = api.gui.comp.TabWidget.new("NORTH")
    addGuardedTab(tabWidget, "tab.general", "General", schemaForm.build, "general", buildState, send)
    addGuardedTab(tabWidget, "tab.advanced", "Advanced", schemaForm.build, "advanced", buildState, send)
    addGuardedTab(tabWidget, "tab.patterns", "Patterns", patternsTab.build, buildState, send)
    addGuardedTab(tabWidget, "tab.lines", "Lines", linesTab.build, buildState, send)
    log.guard("window.tabs", function() rootLayout:addItem(tabWidget) end)

    log.guard("window.helpPanel", function()
        rootLayout:addItem(help.panel())
    end)

    local content = api.gui.comp.Component.new("alnpWindowContent")
    log.guard("window.content", function() content:setLayout(rootLayout) end)

    local built = log.guard("window.new", function()
        return api.gui.comp.Window.new(_("Auto Line Namer Plus"), content)
    end)
    if not built then return end
    windowComponent = built
    log.guard("window.hideOnClose", function() built:addHideOnCloseHandler() end)
    -- Without an explicit size the game opens the window collapsed around its content. Upstream
    -- used 850 by 500; the Lines table wants more room, and the player can resize from there.
    -- Each call is guarded on its own: an unhappy size or a refused setResizable is a cosmetic
    -- loss, never the window (hardening X2).
    log.guard("window.setSize", function() built:setSize(api.gui.util.Size.new(900, 600)) end)
    log.guard("window.setResizable", function() built:setResizable(true) end)
    log.guard("window.setVisible", function() built:setVisible(false, false) end)
    lastRefreshedVersion = buildState.version
end

-- Cheap when the window is hidden: linesTab.update() returns immediately when no scan is running,
-- and nothing else runs at all.
function window.update()
    log.guard("window.linesUpdate", linesTab.update)
    if not (windowComponent and windowComponent:isVisible()) then return end
    if not state or state.version == lastRefreshedVersion then return end
    -- Three guards, one per tab: a refresh that raises costs that tab this frame and nothing else
    -- (hardening X3). The version is only recorded once all three have had their turn, but it is
    -- recorded even when one failed -- a tab that cannot refresh would otherwise retry, and log,
    -- on every frame for the rest of the session.
    local refreshedVersion = state.version
    log.guard("window.refresh.schemaForm", schemaForm.refresh, state)
    log.guard("window.refresh.patternsTab", patternsTab.refresh, state)
    log.guard("window.refresh.linesTab", linesTab.refresh, state)
    lastRefreshedVersion = refreshedVersion
end

return window
