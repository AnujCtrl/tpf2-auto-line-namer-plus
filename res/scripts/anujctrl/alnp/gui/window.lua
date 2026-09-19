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

local function defaultState()
    return { settings = settings.defaults(), records = {}, version = -1 }
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
        button:setTooltip(_(help_topics.get("topbar.button").text))
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

-- Back to "nothing delivered yet". The game gives every loaded save fresh Lua states, so nothing
-- in the mod needs this; tests use it, because require caches this module between them.
function window.reset()
    state, windowComponent, lastRefreshedVersion = nil, nil, nil
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
    help.reset()
    schemaForm.reset()
    patternsTab.reset()
    linesTab.reset()

    local buildState = state or defaultState()
    state = buildState

    local rootLayout = api.gui.layout.BoxLayout.new("VERTICAL")
    rootLayout:addItem(help.labelled(_("How this works"), "window.overview"))

    local tabWidget = api.gui.comp.TabWidget.new("NORTH")
    buildTab(tabWidget, "tab.general", "General", schemaForm.build("general", buildState, send))
    buildTab(tabWidget, "tab.advanced", "Advanced", schemaForm.build("advanced", buildState, send))
    buildTab(tabWidget, "tab.patterns", "Patterns", patternsTab.build(buildState, send))
    buildTab(tabWidget, "tab.lines", "Lines", linesTab.build(buildState, send))
    rootLayout:addItem(tabWidget)

    rootLayout:addItem(help.panel())

    local content = api.gui.comp.Component.new("alnpWindowContent")
    content:setLayout(rootLayout)

    windowComponent = api.gui.comp.Window.new(_("Auto Line Namer Plus"), content)
    windowComponent:addHideOnCloseHandler()
    -- Without an explicit size the game opens the window collapsed around its content. Upstream
    -- used 850 by 500; the Lines table wants more room, and the player can resize from there.
    windowComponent:setSize(api.gui.util.Size.new(900, 600))
    windowComponent:setResizable(true)
    windowComponent:setVisible(false, false)
    lastRefreshedVersion = buildState.version

    addTopBarButton(function()
        windowComponent:setVisible(not windowComponent:isVisible(), false)
    end)
end

-- Cheap when the window is hidden: linesTab.update() returns immediately when no scan is running,
-- and nothing else runs at all.
function window.update()
    linesTab.update()
    if not (windowComponent and windowComponent:isVisible()) then return end
    if not state or state.version == lastRefreshedVersion then return end
    lastRefreshedVersion = state.version
    schemaForm.refresh(state)
    patternsTab.refresh(state)
    linesTab.refresh(state)
end

return window
