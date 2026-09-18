-- Strict fake of the Transport Fever 2 GUI API (api.gui), parsed from the bundled docs at
-- tf2-api/docs/modules/api.gui.md. A widget rejects any method that is not documented for its
-- class or an ancestor, so a GUI task cannot pass its tests on a call the real game would reject.
--
-- Public API (used by later GUI tasks' tests):
--   require("fake_gui")                    -- registers the reset hook; installs api.gui
--   fakeGui.find(root, predicate)          -- first widget in the tree (depth-first) matching
--   fakeGui.findAll(root, predicate)       -- every widget in the tree matching
--   fakeGui.text(widget)                   -- getText() value, or the constructor's first string
--   fakeGui.click(widget)                  -- fires widget.handlers.onClick, if any
--   fakeGui.allText(root)                  -- every text in the tree, joined by "\n"
local fake = require("fake_api")

local fakeGui = {}

local DOC_PATH = "tf2-api/docs/modules/api.gui.md"

-- ---------------------------------------------------------------------------------------------
-- Part A: parse the docs into classes[fullName] = { methods = { [name] = true, ... }, base = "" }
-- ---------------------------------------------------------------------------------------------

local function readFile(path)
    local file = assert(io.open(path, "r"), "cannot open " .. path)
    local text = file:read("*a")
    file:close()
    return text
end

local function parseDocs(text)
    local classes = {}

    -- Class headings: ## <span id="Class_comp_Slider2"></span>Class comp.Slider2
    local headings = {}
    for pos, ns, name in text:gmatch('()##%s*<span id="Class_[%w_]+"></span>Class%s+(%a+)%.([%w]+)') do
        headings[#headings + 1] = { pos = pos, class = ns .. "." .. name }
    end

    for i, heading in ipairs(headings) do
        local stop = headings[i + 1] and headings[i + 1].pos or (#text + 1)
        local chunk = text:sub(heading.pos, stop - 1)
        classes[heading.class] = classes[heading.class] or { methods = {}, base = nil }

        -- Base class: [comp.Component](api.gui.html#Class_comp_Component).
        -- The bracketed text is the class name; %s matches the newline some entries wrap on.
        local base = chunk:match("Base class:%s*%[([%w%.]+)%]")
        if base then classes[heading.class].base = base end

        -- Methods: <span id="comp.Slider2:getValue"></span> (also layout.BoxLayout:addItem,
        -- util.Size:new). The colon distinguishes a method id from a field id (util.Size.h).
        for cls, method in chunk:gmatch('<span id="([%w_]+%.[%w_]+):([%w_]+)"></span>') do
            if cls == heading.class then
                classes[heading.class].methods[method] = true
            end
        end
    end

    return classes
end

-- PROVEN: methods absent from the docs (confirmed above) but used, unconditionally (never inside
-- a pcall guarding an unverified call), by code that runs in the game. Each entry cites the file
-- and the call that proves it.
local PROVEN = {
    ["layout.BoxLayout"] = {
        -- The doc's own "Base class:" line for BoxLayout reads
        -- "Base class: [layout.AbstractLayout](api.gui.html#Class_layout_AbstractLayout)", but no
        -- class named layout.AbstractLayout is ever defined anywhere in the doc (the class that
        -- documents addItem/getNumItems/getItem/removeItem is named layout.LayoutBase /
        -- layout.ILayout instead). Walking the *documented* base chain therefore never reaches
        -- those methods for a BoxLayout, even though BoxLayout is the layout both proven files
        -- build almost everything around.
        addItem = "bus_line_tool_window.lua:74 boxLayout:addItem(api.gui.comp.TextView.new(...)); "
            .. "also upstream auto_line_namer_gui.lua, e.g. generalLabelLayout:addItem(header_EnableLineManager)",
        getNumItems = "bus_line_tool_window.lua:131 for i = chooserLayout:getNumItems() - 1, 0, -1 do",
        getItem = "bus_line_tool_window.lua:132 chooserLayout:removeItem(chooserLayout:getItem(i))",
        removeItem = "bus_line_tool_window.lua:132 chooserLayout:removeItem(chooserLayout:getItem(i))",
    },
    ["comp.ImageView"] = {
        -- comp.ImageView documents only setImage() and setText() (the setText entry's own
        -- description, "Creates a new imageview with a texture," is a copy-paste leftover from a
        -- missing :new() entry) -- there is no comp.ImageView:new in the docs at all.
        new = 'bus_line_tool_window.lua:75 local selectedVehicle = api.gui.comp.ImageView.new(" ")',
    },
    ["comp.ComboBox"] = {
        -- comp.ComboBox documents addItem/addItemFactory/clear/getCurrentIndex/getNumItems/new/
        -- onIndexChanged. Neither removeItem nor setSelected is documented on ComboBox or on its
        -- base comp.Component, yet both are used unconditionally (not inside a pcall).
        removeItem = "bus_line_tool_window.lua:431 for i = combo:getNumItems() - 1, 0, -1 do combo:removeItem(i) end",
        setSelected = "upstream auto_line_namer_gui.lua:369 combobox_CargoTypeShowType:setSelected(State.getCargoTypeShowType(), false)",
    },
}

local classes = parseDocs(readFile(DOC_PATH))
for className, methods in pairs(PROVEN) do
    classes[className] = classes[className] or { methods = {}, base = nil }
    for method in pairs(methods) do
        classes[className].methods[method] = true
    end
end

fakeGui.classes = classes -- exposed read-only for diagnostics; tests should not mutate it

local function isAllowed(className, method)
    local name = className
    local guard = 0
    while name and guard < 30 do
        guard = guard + 1
        local info = classes[name]
        if not info then return false end
        if info.methods[method] then return true end
        name = info.base
    end
    return false
end

-- ---------------------------------------------------------------------------------------------
-- Widget behaviour
-- ---------------------------------------------------------------------------------------------

-- Structural calls: recorded into widget.children so fakeGui.find/findAll/allText can traverse
-- into whatever a builder attached, however it attached it.
local STRUCTURAL = {
    addItem = function(self, args)
        self.children[#self.children + 1] = args[1]
    end,
    addTab = function(self, args)
        self.children[#self.children + 1] = args[1]
        self.children[#self.children + 1] = args[2]
    end,
    setLayout = function(self, args)
        self.layoutRef = args[1]
        self.children[#self.children + 1] = args[1]
    end,
    getLayout = function(self)
        return rawget(self, "layoutRef")
    end,
    setContent = function(self, args)
        self.contentRef = args[1]
        self.children[#self.children + 1] = args[1]
    end,
    getContent = function(self)
        return rawget(self, "contentRef")
    end,
    addRow = function(self, args)
        local row = args[1] or {}
        self.rows[#self.rows + 1] = row
        for __, item in ipairs(row) do
            self.children[#self.children + 1] = item
        end
    end,
    setHeader = function(self, args)
        self.header = args[1] or {}
        for __, item in ipairs(self.header) do
            self.children[#self.children + 1] = item
        end
    end,
    -- Table:deleteAll "Remove all rows and all components": clears only what addRow added, not
    -- the header (matching the brief: "deleteAll() clears the rows it added").
    deleteAll = function(self)
        for __, row in ipairs(self.rows) do
            for __, item in ipairs(row) do
                for i = #self.children, 1, -1 do
                    if self.children[i] == item then
                        table.remove(self.children, i)
                        break
                    end
                end
            end
        end
        self.rows = {}
    end,
    getNumItems = function(self)
        return #self.children
    end,
    getItem = function(self, args)
        return self.children[(args[1] or 0) + 1] -- the real API is 0-indexed
    end,
    removeItem = function(self, args)
        local item = args[1]
        for i, c in ipairs(self.children) do
            if c == item then
                table.remove(self.children, i)
                return c
            end
        end
        return nil
    end,
    invokeLater = function(self, args)
        if args[1] then args[1]() end
    end,
    setTooltip = function(self, args)
        self.tooltip = args[1]
    end,
}

-- Simple get/set state. setSelected doubles as ComboBox's "current index" (getCurrentIndex reads
-- the same field): both are just "the one value this widget currently holds".
local GET_FIELD = {
    getText = "text",
    isVisible = "visible",
    isSelected = "selected",
    getCurrentIndex = "selected",
    getValue = "value",
    isEnabled = "enabled",
}
local SET_FIELD = {
    setText = "text",
    setVisible = "visible",
    setSelected = "selected",
    setValue = "value",
    setEnabled = "enabled",
}
-- When the emit-signal argument is true, fire the first of these handlers that is registered.
local EMIT_HANDLERS = {
    setText = { "onChange" },
    setSelected = { "onToggle", "onIndexChanged" },
    setValue = { "onChange", "onValueChanged" },
}

local function dispatch(self, key, args)
    if STRUCTURAL[key] then
        return STRUCTURAL[key](self, args)
    end
    if SET_FIELD[key] then
        self[SET_FIELD[key]] = args[1]
        if args[2] == true and EMIT_HANDLERS[key] then
            for __, name in ipairs(EMIT_HANDLERS[key]) do
                if self.handlers[name] then
                    self.handlers[name](args[1])
                    break
                end
            end
        end
        return
    end
    if GET_FIELD[key] then
        -- rawget: the field is legitimately absent until the matching setter is first called,
        -- and a plain missing-field read must not be mistaken for an unmodelled method call.
        return rawget(self, GET_FIELD[key])
    end
    if key:match("^on%u") then
        self.handlers[key] = args[1]
        return
    end
    return nil -- a real but unmodelled method: allowed, recorded, no further behaviour
end

local WIDGET_MT = {}
WIDGET_MT.__index = function(widget, key)
    if not isAllowed(widget.class, key) then
        error(widget.class .. " has no method '" .. key .. "'", 2)
    end
    return function(selfArg, ...)
        local args = { ... }
        selfArg.calls[#selfArg.calls + 1] = { name = key, args = args }
        return dispatch(selfArg, key, args)
    end
end

local function newWidget(className, args)
    local widget = {
        class = className,
        args = args,
        calls = {},
        children = {},
        handlers = {},
        rows = {},
    }
    for __, a in ipairs(args) do
        if type(a) == "table" and a.class then
            widget.children[#widget.children + 1] = a
        end
    end
    return setmetatable(widget, WIDGET_MT)
end

-- ---------------------------------------------------------------------------------------------
-- api.gui installation (reset every fake.reset())
-- ---------------------------------------------------------------------------------------------

local function namespaceTable(prefix)
    return setmetatable({}, {
        __index = function(__, name)
            error("unknown class '" .. prefix .. "." .. name .. "'", 2)
        end,
    })
end

local function installGui()
    local compNs = namespaceTable("comp")
    local layoutNs = namespaceTable("layout")

    for className in pairs(classes) do
        local ns, name = className:match("^(%a+)%.([%w]+)$")
        local function ctor(...)
            return newWidget(className, { ... })
        end
        if ns == "comp" then
            compNs[name] = { new = ctor }
        elseif ns == "layout" then
            layoutNs[name] = { new = ctor }
        end
    end

    local byId = {}
    api.gui = {
        comp = compNs,
        layout = layoutNs,
        util = {
            Size = { new = function(...) return newWidget("util.Size", { ... }) end },
            getById = function(id)
                if not byId[id] then
                    local component = newWidget("comp.Component", { id })
                    local layout = newWidget("layout.BoxLayout", { "VERTICAL" })
                    component.layoutRef = layout
                    component.children[#component.children + 1] = layout
                    byId[id] = component
                end
                return byId[id]
            end,
        },
    }
end

fake.addReset(installGui)

-- ---------------------------------------------------------------------------------------------
-- Part A: test helpers
-- ---------------------------------------------------------------------------------------------

function fakeGui.find(root, predicate)
    if root == nil then return nil end
    if predicate(root) then return root end
    for __, child in ipairs(root.children or {}) do
        local found = fakeGui.find(child, predicate)
        if found then return found end
    end
    return nil
end

function fakeGui.findAll(root, predicate)
    local out = {}
    local function walk(node)
        if predicate(node) then out[#out + 1] = node end
        for __, child in ipairs(node.children or {}) do walk(child) end
    end
    if root then walk(root) end
    return out
end

function fakeGui.text(widget)
    -- rawget: "text" is only set once setText has actually been called, and reading it before
    -- then must return nil quietly rather than being mistaken for an unmodelled method call.
    local text = rawget(widget, "text")
    if text ~= nil then return text end
    for __, a in ipairs(widget.args or {}) do
        if type(a) == "string" then return a end
    end
    return nil
end

function fakeGui.click(widget)
    if widget.handlers.onClick then widget.handlers.onClick() end
end

function fakeGui.allText(root)
    local parts = {}
    local function walk(node)
        local t = fakeGui.text(node)
        if t then parts[#parts + 1] = t end
        for __, child in ipairs(node.children or {}) do walk(child) end
    end
    if root then walk(root) end
    return table.concat(parts, "\n")
end

return fakeGui
