-- The "i" info button and the shared help panel it fills. This is the only place any GUI module
-- builds an info button, so help_topics.lua stays the single source of truth for what a button
-- says. GUI-only module: may call api.gui.
local log = require "anujctrl/alnp/log"
local topics = require "anujctrl/alnp/help_topics"

local help = {}

local FALLBACK_TEXT = "No help has been written for this yet."

local panelComponent = nil
local panelTitleView = nil
local panelBodyView = nil

-- Creates the panel on first use, in guiInit or in a test after fake.reset(); every later call
-- (including from help.show before help.panel() was ever called) returns the same component.
local function ensurePanel()
    if panelComponent then return panelComponent end

    local layout = api.gui.layout.BoxLayout.new("VERTICAL")
    panelTitleView = api.gui.comp.TextView.new("")
    panelBodyView = api.gui.comp.TextView.new("")
    local closeButton = api.gui.comp.Button.new(api.gui.comp.TextView.new(_("Close")), true)
    closeButton:onClick(log.wrap("help.closeButton", function()
        panelComponent:setVisible(false, false)
    end))

    layout:addItem(panelTitleView)
    layout:addItem(panelBodyView)
    layout:addItem(closeButton)

    panelComponent = api.gui.comp.Component.new("alnpHelpPanel")
    panelComponent:setLayout(layout)
    panelComponent:setVisible(false, false)

    return panelComponent
end

function help.panel()
    return ensurePanel()
end

-- Fills the panel with title/text (both translated at display time, per §10.1) and shows it.
function help.show(title, text)
    ensurePanel()
    panelTitleView:setText(_(title), false)
    panelBodyView:setText(_(text), false)
    panelComponent:setVisible(true, false)
end

local function buildButton(title, text)
    local button = api.gui.comp.Button.new(api.gui.comp.TextView.new("i"), true)
    button:setTooltip(_(text))
    button:onClick(log.wrap("help.infoButton", function()
        help.show(title, text)
    end))
    return button
end

-- An unknown key must not raise: that would take the whole settings window down in the game.
function help.button(topicKey)
    local topic = topics.get(topicKey)
    if not topic then
        log.error("no help topic '" .. tostring(topicKey) .. "'")
        return buildButton(tostring(topicKey), FALLBACK_TEXT)
    end
    return buildButton(topic.title, topic.text)
end

-- Same as help.button, for help text generated at runtime (schema rows) rather than looked up
-- by topic key.
function help.buttonFor(title, text)
    return buildButton(title, text)
end

function help.labelled(text, topicKey)
    local layout = api.gui.layout.BoxLayout.new("HORIZONTAL")
    layout:addItem(api.gui.comp.TextView.new(_(text)))
    layout:addItem(help.button(topicKey))

    local component = api.gui.comp.Component.new("alnpLabelled")
    component:setLayout(layout)
    return component
end

-- Forgets the panel. guiInit calls this once when the window is (re)built; tests call it after
-- fake.reset() so a stale panel from a previous test cannot leak in.
function help.reset()
    panelComponent = nil
    panelTitleView = nil
    panelBodyView = nil
end

return help
