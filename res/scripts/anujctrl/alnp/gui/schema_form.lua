-- Builds the General and Advanced settings tabs straight from settings.schema: one loop over
-- settings.sections / settings.rowsIn produces every heading, row, editor and info button, so a
-- new setting needs only a schema row in settings.lua, never hand-written GUI code (spec §9, §10,
-- §10.1). GUI-only module: may call api.gui.
local settings = require "anujctrl/alnp/settings"
local help = require "anujctrl/alnp/gui/help"
local sync = require "anujctrl/alnp/gui/sync"
local log = require "anujctrl/alnp/log"

local schemaForm = {}

-- [path] = { get = function() -> value currently shown, set = function(value) -> writes the
-- widget without emitting a change event }. Remembered across every build() call so refresh() can
-- walk both tabs' editors together.
local editorsByPath = {}
-- Tracks a pending player edit per path so a refresh that has not caught up with the engine yet
-- cannot clobber it; see gui/sync.lua.
local syncInstance = sync.new()
-- The slider fallback (buildNumericEditor) logs once per form lifetime, not once per row: many
-- rows can fail the same way in one build() call, and only one line is useful to the player.
local loggedSliderFallback = false

-- Forgets every remembered editor and starts a fresh sync instance. guiInit calls this once when
-- the window is (re)built; tests call it after fake.reset(). clock: optional, forwarded to
-- sync.new() (defaults to os.time there); lets a test control sync's timeout without sleeping.
function schemaForm.reset(clock)
    editorsByPath = {}
    syncInstance = sync.new(clock)
    loggedSliderFallback = false
end

-- Sends a "set" event for a row and remembers it was sent, so a refresh that arrives before the
-- engine has echoed the change back does not overwrite what the player just did.
local function commitValue(path, value, send)
    syncInstance:sent(path, value)
    send("set", { path = path, value = value })
end

local function buildBoolEditor(row, value, send)
    local checkbox = api.gui.comp.CheckBox.new()
    checkbox:setSelected(value, false)
    checkbox:onToggle(function(v)
        commitValue(row.path, v, send)
    end)
    return checkbox, {
        get = function() return checkbox:isSelected() end,
        set = function(newValue) checkbox:setSelected(newValue, false) end,
    }
end

local function buildStringEditor(row, value, send)
    local field = api.gui.comp.TextInputField.new()
    field:setText(value, false)
    field:onChange(function(text)
        commitValue(row.path, text, send)
    end)
    return field, {
        get = function() return field:getText() end,
        set = function(newValue) field:setText(newValue, false) end,
    }
end

local function buildEnumEditor(row, value, send)
    local combo = api.gui.comp.ComboBox.new()
    local selected = 0
    for i, choice in ipairs(row.values) do
        combo:addItem(_(choice))
        if choice == value then selected = i - 1 end
    end
    combo:setSelected(selected, false)
    combo:onIndexChanged(function(index)
        commitValue(row.path, row.values[index + 1], send)
    end)
    return combo, {
        get = function() return row.values[combo:getCurrentIndex() + 1] end,
        set = function(newValue)
            for i, choice in ipairs(row.values) do
                if choice == newValue then
                    combo:setSelected(i - 1, false)
                    return
                end
            end
        end,
    }
end

-- The one widget nothing in the two proven sources uses (see the task brief), so its real
-- behaviour is unverified. Kept as its own function so buildNumericEditor can pcall it and fall
-- back to a text field if construction or any setup call raises. new(true): the docs give no
-- argument list for comp.Slider:new(), but common Transport Fever 2 mod usage passes a boolean,
-- true for horizontal (controller ruling, fix round 1 / F2).
local function buildSliderEditor(row, value, send)
    local slider = api.gui.comp.Slider.new(true)
    slider:setMinimum(row.min)
    slider:setMaximum(row.max)
    if row.type == "int" then slider:setStep(1) end
    slider:setValue(value, false)

    local valueView = api.gui.comp.TextView.new(tostring(value))
    slider:onValueChanged(function(v)
        local newValue = v
        if row.type == "int" then newValue = math.floor(v + 0.5) end
        valueView:setText(tostring(newValue))
        commitValue(row.path, newValue, send)
    end)

    local layout = api.gui.layout.BoxLayout.new("HORIZONTAL")
    layout:addItem(slider)
    layout:addItem(valueView)
    local component = api.gui.comp.Component.new("alnpSlider:" .. row.path)
    component:setLayout(layout)

    return component, {
        get = function() return slider:getValue() end,
        set = function(newValue)
            slider:setValue(newValue, false)
            valueView:setText(tostring(newValue))
        end,
    }
end

-- Bus Line Tool Plus falls back the same way for its colour chooser: a plain text field that only
-- ever forwards a value it can actually parse as a number.
--
-- Fix round 1 / F1: onChange must mark the path pending on EVERY keystroke, not only the ones
-- that parse. While the player is mid-edit on text that is not (yet) a number -- most commonly
-- because they cleared the field to type a fresh one, so it is briefly "" -- nothing was pending,
-- so sync:shouldApply returned true and a refresh clobbered the field back to the old engine
-- value. Marking pending with the raw text (which can never equal the engine's numeric state)
-- means sync's own timeout is what eventually lets a refresh through instead.
local function buildFallbackNumberEditor(row, value, send)
    local field = api.gui.comp.TextInputField.new()
    field:setText(tostring(value), false)
    field:onChange(function(text)
        local number = tonumber(text)
        if number ~= nil then
            commitValue(row.path, number, send)
        else
            syncInstance:sent(row.path, text)
        end
    end)
    return field, {
        get = function() return tonumber(field:getText()) end,
        set = function(newValue) field:setText(tostring(newValue), false) end,
    }
end

local function buildNumericEditor(row, value, send)
    local ok, componentOrError, accessors = pcall(buildSliderEditor, row, value, send)
    if ok then return componentOrError, accessors end
    if not loggedSliderFallback then
        log.info("slider widget unavailable, using a text field for numeric settings: " .. tostring(componentOrError))
        loggedSliderFallback = true
    end
    return buildFallbackNumberEditor(row, value, send)
end

local function buildEditor(row, value, send)
    if row.type == "bool" then return buildBoolEditor(row, value, send) end
    if row.type == "string" then return buildStringEditor(row, value, send) end
    if row.type == "enum" then return buildEnumEditor(row, value, send) end
    if row.type == "int" or row.type == "number" then return buildNumericEditor(row, value, send) end
    error("schema_form: unknown row type '" .. tostring(row.type) .. "' for " .. row.path)
end

local function buildRow(row, state, send)
    local layout = api.gui.layout.BoxLayout.new("HORIZONTAL")
    layout:addItem(api.gui.comp.TextView.new(_(row.label)))

    local value = settings.get(state.settings, row.path)
    local editor, accessors = buildEditor(row, value, send)
    layout:addItem(editor)
    layout:addItem(help.buttonFor(row.label, settings.helpText(row)))

    editorsByPath[row.path] = accessors

    local component = api.gui.comp.Component.new("alnpRow:" .. row.path)
    component:setLayout(layout)
    return component
end

local function buildSectionHeading(section, send)
    local layout = api.gui.layout.BoxLayout.new("HORIZONTAL")
    layout:addItem(api.gui.comp.TextView.new(_(section.label)))
    -- Raw section.label, not _(section.label): help.show translates the title again when it
    -- displays it, so translating here would double-translate (fix round 1 / F3, correcting the
    -- brief -- buildRow already passed row.label raw for the same reason).
    layout:addItem(help.buttonFor(section.label, section.help))

    local resetButton = api.gui.comp.Button.new(api.gui.comp.TextView.new(_("Reset section")), true)
    resetButton:onClick(function()
        send("resetSection", { section = section.key })
    end)
    layout:addItem(resetButton)
    layout:addItem(help.button("reset.section"))

    local component = api.gui.comp.Component.new("alnpSectionHeading:" .. section.key)
    component:setLayout(layout)
    return component
end

local function buildFooterButton(label, topicKey, onClick)
    local layout = api.gui.layout.BoxLayout.new("HORIZONTAL")
    local button = api.gui.comp.Button.new(api.gui.comp.TextView.new(label), true)
    button:onClick(onClick)
    layout:addItem(button)
    layout:addItem(help.button(topicKey))

    local component = api.gui.comp.Component.new("alnpSchemaFooter:" .. topicKey)
    component:setLayout(layout)
    return component
end

-- tabKey: "general" or "advanced". state = { settings = tbl, records = {...} }.
function schemaForm.build(tabKey, state, send)
    local rootLayout = api.gui.layout.BoxLayout.new("VERTICAL")

    for __, section in ipairs(settings.sections) do
        if section.tab == tabKey then
            rootLayout:addItem(buildSectionHeading(section, send))
            for __, row in ipairs(settings.rowsIn(section.key)) do
                rootLayout:addItem(buildRow(row, state, send))
            end
        end
    end

    if tabKey == "general" then
        rootLayout:addItem(buildFooterButton(_("Reset everything"), "reset.all", function()
            send("resetAll", {})
        end))
    elseif tabKey == "advanced" then
        rootLayout:addItem(buildFooterButton(_("Run API check"), "advanced.apiCheck", function()
            send("apiCheck", {})
        end))
    end

    local content = api.gui.comp.Component.new("alnpSchemaForm:" .. tabKey)
    content:setLayout(rootLayout)

    local scrollArea = api.gui.comp.ScrollArea.new(api.gui.comp.Component.new(" "), " ")
    scrollArea:setContent(content)
    return scrollArea
end

-- Walks every editor built so far (either tab) and, where the player has no pending edit still in
-- flight and the widget disagrees with the given state, writes the state value with the "do not
-- emit" flag so a refresh never echoes back to the engine.
function schemaForm.refresh(state)
    for path, accessors in pairs(editorsByPath) do
        local stateValue = settings.get(state.settings, path)
        if syncInstance:shouldApply(path, stateValue) then
            if accessors.get() ~= stateValue then
                accessors.set(stateValue)
            end
        end
    end
end

return schemaForm
