-- Builds the Patterns tab: a preset chooser, the default pattern, one row per line kind (an
-- auto-rename switch, a custom-pattern switch, a text field and a live preview), and the token
-- cheat-sheet. Every preview is naming.render() of whatever pattern is currently shown in a
-- field, evaluated against naming.sampleFacts(kind), so it can never drift from what a real line
-- would be named -- see spec sections 7, 8 and 10. GUI-only module: may call api.gui.
local kinds = require "anujctrl/alnp/kinds"
local naming = require "anujctrl/alnp/naming"
local classify = require "anujctrl/alnp/classify"
local settings = require "anujctrl/alnp/settings"
local help = require "anujctrl/alnp/gui/help"
local topics = require "anujctrl/alnp/help_topics"
local sync = require "anujctrl/alnp/gui/sync"

local patternsTab = {}

local BLANK_TEXT = "(blank: the line would be left alone)"

-- Forgotten by patternsTab.reset(); (re)created by patternsTab.build(). Holds every widget
-- reference the module's own handlers and patternsTab.refresh() need to reach later.
local current = nil

-- A horizontal row: one Component per logical line in the tab, so a row's own subtree can be
-- searched independently of its siblings.
local function newRow(...)
    local layout = api.gui.layout.BoxLayout.new("HORIZONTAL")
    for __, item in ipairs({ ... }) do
        layout:addItem(item)
    end
    local component = api.gui.comp.Component.new("alnpPatternsRow")
    component:setLayout(layout)
    return component
end

local function renderPreview(pattern, kind, settingsTbl)
    local facts = naming.sampleFacts(kind)
    local ctx = { settings = settingsTbl, kind = kind, scope = classify.scope(facts, settingsTbl), n = 2 }
    local rendered = naming.render(pattern, facts, ctx)
    if rendered == "" then return _(BLANK_TEXT) end
    return rendered
end

-- The default row always previews as kind "bus" (spec: "The default row previews as kind bus").
local function recomputeDefaultPreview()
    current.defaultPreview:setText(renderPreview(current.defaultField:getText(), "bus", current.state.settings))
end

-- The pattern a kind's row is currently previewing: its own field while custom is ticked,
-- otherwise the (possibly just-typed) default pattern -- never the last value sent to the engine.
local function patternForKind(kind)
    local kindRow = current.kindRows[kind]
    if kindRow.customCheckbox:isSelected() then return kindRow.patternField:getText() end
    return current.defaultField:getText()
end

local function recomputeKindPreview(kind)
    local kindRow = current.kindRows[kind]
    kindRow.preview:setText(renderPreview(patternForKind(kind), kind, current.state.settings))
end

-- Labels and separators may have changed even when no pattern text did, so every preview is
-- always recomputed together (called after every edit and after every refresh).
local function recomputeAllPreviews()
    recomputeDefaultPreview()
    for __, kind in ipairs(kinds.list) do recomputeKindPreview(kind) end
end

local function buildPresetRow()
    local combo = api.gui.comp.ComboBox.new()
    for __, preset in ipairs(settings.presets) do
        combo:addItem(_(preset.label))
    end
    combo:setSelected(0, false)

    local applyLabel = api.gui.comp.TextView.new(_("Apply preset"))
    local applyButton = api.gui.comp.Button.new(applyLabel, true)

    -- Changing the preset between the two confirmation clicks cancels the pending confirmation.
    combo:onIndexChanged(function(__)
        if current.pendingPresetKey then
            current.pendingPresetKey = nil
            applyLabel:setText(_("Apply preset"))
        end
    end)

    applyButton:onClick(function()
        local index = combo:getCurrentIndex() or 0
        local preset = settings.presets[index + 1]
        if not preset then return end
        if current.pendingPresetKey == preset.key then
            current.pendingPresetKey = nil
            applyLabel:setText(_("Apply preset"))
            current.send("preset", { key = preset.key })
        else
            current.pendingPresetKey = preset.key
            applyLabel:setText(_("Click again to overwrite all patterns"))
        end
    end)

    return newRow(help.labelled(_("Preset"), "patterns.preset"), combo, applyButton)
end

local function buildDefaultRow()
    local field = api.gui.comp.TextInputField.new("")
    local preview = api.gui.comp.TextView.new("")

    field:onChange(function(text)
        current.sync:sent("patterns.default", text)
        current.send("set", { path = "patterns.default", value = text })
        recomputeAllPreviews() -- every kind that inherits the default previews from it too
    end)

    current.defaultField = field
    current.defaultPreview = preview
    return newRow(help.labelled(_("Default pattern"), "patterns.default"), field, preview)
end

local function buildKindRow(kind)
    local label = api.gui.comp.TextView.new(_(kinds.label[kind]))
    local labelHelp = help.button("patterns.kind")

    local autoRename = api.gui.comp.CheckBox.new(_("Rename automatically"))
    local autoRenameHelp = help.button("patterns.autoRename")

    local custom = api.gui.comp.CheckBox.new(_("Custom pattern"))
    local customHelp = help.button("patterns.custom")

    local field = api.gui.comp.TextInputField.new("")
    local preview = api.gui.comp.TextView.new("")

    local path = "patterns." .. kind

    autoRename:onToggle(function(value)
        local autoPath = "kinds." .. kind .. ".autoRename"
        current.sync:sent(autoPath, value)
        current.send("set", { path = autoPath, value = value })
    end)

    -- Ticking sends the current default pattern text as this kind's own; unticking sends "" so
    -- it inherits again. The field mirrors whichever pattern is now in effect either way.
    custom:onToggle(function(value)
        local newValue = ""
        if value then newValue = current.defaultField:getText() end
        current.sync:sent(path, newValue)
        current.send("set", { path = path, value = newValue })
        field:setEnabled(value)
        if value then
            field:setText(newValue)
        else
            field:setText(current.defaultField:getText())
        end
        recomputeKindPreview(kind)
    end)

    field:onChange(function(text)
        current.sync:sent(path, text)
        current.send("set", { path = path, value = text })
        recomputeKindPreview(kind)
    end)

    current.kindRows[kind] = {
        customCheckbox = custom,
        autoRenameCheckbox = autoRename,
        patternField = field,
        preview = preview,
    }

    return newRow(label, labelHelp, autoRename, autoRenameHelp, custom, customHelp, field, preview)
end

local function buildTokenReference()
    local lines = {}
    for __, tokenInfo in ipairs(naming.tokens) do
        lines[#lines + 1] = tokenInfo.token .. "  " .. tokenInfo.example .. "  \226\128\148 " .. tokenInfo.help
    end
    local tokenLines = table.concat(lines, "\n")
    local topic = topics.get("patterns.tokens")

    local header = newRow(api.gui.comp.TextView.new(_("Tokens")), help.buttonFor(topic.title, topic.text .. "\n\n" .. tokenLines))
    local cheatSheet = api.gui.comp.TextView.new(tokenLines)

    local layout = api.gui.layout.BoxLayout.new("VERTICAL")
    layout:addItem(header)
    layout:addItem(cheatSheet)
    local component = api.gui.comp.Component.new("alnpTokenReference")
    component:setLayout(layout)
    return component
end

-- state = { settings = tbl, records = {...} }; send(name, param) sends the named C10 engine event.
function patternsTab.build(state, send)
    current = { kindRows = {}, pendingPresetKey = nil, sync = sync.new(), state = state, send = send }

    local layout = api.gui.layout.BoxLayout.new("VERTICAL")
    layout:addItem(buildPresetRow())
    layout:addItem(buildDefaultRow())
    for __, kind in ipairs(kinds.list) do
        layout:addItem(buildKindRow(kind))
    end
    layout:addItem(buildTokenReference())

    local content = api.gui.comp.Component.new("alnpPatternsContent")
    content:setLayout(layout)

    local scrollArea = api.gui.comp.ScrollArea.new(content, "alnpPatternsScroll")

    patternsTab.refresh(state) -- seeds every widget from the real starting values

    return scrollArea
end

-- Applies `state` to every widget where sync:shouldApply allows it and the widget differs (emit
-- false, so applying can never trigger a send), then recomputes every preview: labels and
-- separators may have changed even when no pattern or auto-rename value did.
function patternsTab.refresh(state)
    if not current then return end
    current.state = state
    local tbl = state.settings

    local defaultValue = settings.get(tbl, "patterns.default")
    if current.sync:shouldApply("patterns.default", defaultValue) then
        if current.defaultField:getText() ~= defaultValue then
            current.defaultField:setText(defaultValue)
        end
    end

    for __, kind in ipairs(kinds.list) do
        local kindRow = current.kindRows[kind]
        local path = "patterns." .. kind
        local patternValue = settings.get(tbl, path)
        if current.sync:shouldApply(path, patternValue) then
            local shouldBeCustom = patternValue ~= ""
            local desiredText = patternValue
            if not shouldBeCustom then desiredText = current.defaultField:getText() end
            if kindRow.customCheckbox:isSelected() ~= shouldBeCustom or kindRow.patternField:getText() ~= desiredText then
                kindRow.customCheckbox:setSelected(shouldBeCustom, false)
                kindRow.patternField:setEnabled(shouldBeCustom)
                kindRow.patternField:setText(desiredText)
            end
        end

        local autoPath = "kinds." .. kind .. ".autoRename"
        local autoValue = settings.get(tbl, autoPath)
        if current.sync:shouldApply(autoPath, autoValue) then
            if kindRow.autoRenameCheckbox:isSelected() ~= autoValue then
                kindRow.autoRenameCheckbox:setSelected(autoValue, false)
            end
        end
    end

    recomputeAllPreviews()
end

-- Forgets every widget and starts a fresh sync instance. patternsTab.build() creates both anew.
function patternsTab.reset()
    current = nil
end

return patternsTab
