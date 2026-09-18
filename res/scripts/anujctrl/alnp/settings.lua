-- Schema-driven settings: one table of rows is the single source of truth for defaults,
-- validation, merge-on-load and the generated help text. Pure Lua: no `api`, no `game`, no `_()`.
local kinds = require("anujctrl/alnp/kinds")

local settings = {}

-- Text substituted for {type}. Deliberately shorter than kinds.label (which names the kind
-- itself, e.g. "Passenger train"), since this is what shows up inside a rendered line name.
local KIND_TYPE_TEXT = {
    bus = "Bus",
    tram = "Tram",
    truck = "Truck",
    trainPassenger = "Train",
    trainCargo = "Freight",
    shipPassenger = "Ferry",
    shipCargo = "Ship",
    airPassenger = "Air",
    airCargo = "Air Cargo",
    unknown = "Line",
}

-- Text substituted for {scope}. The default value and its own display text happen to match.
local SCOPE_TYPE_TEXT = {
    ["local"] = "Local",
    intercity = "Intercity",
    regional = "Regional",
}

local DEFAULT_PATTERN = "{type} {towns}[ {n}]"
local CARGO_PATTERN = "{cargo}: {firstIndustry} \226\134\146 {lastIndustry}[ {n}]"
local UPSTREAM_PATTERN = "{type} {cargo}-{towns:3}-{scope}-{n}"
local DETAILED_PATTERN = "{type} {firstStop} \226\128\147 {lastStop}[ via {via}][ {n}]"
local DETAILED_CARGO_PATTERN = "{cargo}: {firstIndustry} \226\134\146 {lastIndustry}[ via {via}][ {n}]"

settings.sections = {
    { key = "general", tab = "general", label = "General",
      help = "Controls whether the mod is active at all, which names are\n"
          .. "protected from renaming, and how to force a one-off rename." },
    { key = "eligibility", tab = "general", label = "Which lines get renamed",
      help = "Decides which lines are candidates for automatic\n"
          .. "renaming: which names count as defaults, and how many\n"
          .. "stops a line needs before the mod touches it." },
    { key = "labels", tab = "general", label = "Labels",
      help = "Text used for {type} and {scope} in patterns: the name\n"
          .. "shown for each line kind and each scope." },
    { key = "scope", tab = "advanced", label = "Local, intercity, regional",
      help = "Distinguishes local, intercity and regional lines by how\n"
          .. "many distinct towns they serve, for the {scope} token." },
    { key = "separators", tab = "advanced", label = "Separators",
      help = "Small pieces of punctuation used to join parts of a\n"
          .. "generated name: town pairs, via towns and cargo lists." },
    { key = "cargo", tab = "advanced", label = "Cargo names",
      help = "Controls how the {cargo} token lists what a line carries,\n"
          .. "including when to collapse a long list to one word." },
    { key = "via", tab = "advanced", label = "Via towns",
      help = "Controls how many intermediate towns the {via} token\n"
          .. "lists between a line's first and last stop." },
    { key = "industry", tab = "advanced", label = "Industry lookup",
      help = "Controls how {firstIndustry} and {lastIndustry} find a\n"
          .. "nearby industry, and what they show when none is found." },
    { key = "numbering", tab = "advanced", label = "Numbering",
      help = "Controls the {n} token: which lines share a numbering\n"
          .. "sequence, where it starts, and how it is padded." },
    { key = "performance", tab = "advanced", label = "Performance",
      help = "Controls how much work the mod does per game tick and\n"
          .. "per GUI frame, trading reaction speed for smoothness." },
    { key = "logging", tab = "advanced", label = "Logging",
      help = "Controls how much detail the mod writes to the game's\n"
          .. "log file, for troubleshooting." },
    { key = "patterns", tab = "patterns", label = "Patterns",
      help = "The naming patterns themselves: one default pattern plus\n"
          .. "an optional override and an auto-rename switch per kind." },
}

local schema = {}
local byPath = {}

local function addRow(row)
    schema[#schema + 1] = row
    byPath[row.path] = row
end

addRow({ path = "enabled", type = "bool", default = true, section = "general",
    label = "Enabled",
    help = "Turns the whole mod on or off. Example: switch it off\n"
        .. "to rename every line by hand without interference." })
addRow({ path = "lock.prefix", type = "string", default = "", section = "general",
    label = "Never-rename prefix",
    help = "Lines whose name starts with this text are always left\n"
        .. "alone. Example: prefix \"Cst\" protects \"Cst Feeder 1\"." })
addRow({ path = "lock.autoLockEdited", type = "bool", default = true, section = "general",
    label = "Auto-lock hand-edited names",
    help = "Locks a name that looks hand-typed so the mod leaves it\n"
        .. "alone. Example: renaming a line to \"Airport Express\"\n"
        .. "locks it automatically." })
addRow({ path = "reload.names", type = "string", default = "r,reload", section = "general",
    label = "Reload trigger names",
    help = "Rename a line once by naming it one of these words.\n"
        .. "Comma-separated, e.g. renaming a line to \"r\" reloads it." })

addRow({ path = "eligible.defaultNames", type = "bool", default = true, section = "eligibility",
    label = "Rename game default names",
    help = "Renames lines still named like the game's default, for\n"
        .. "example \"Line 12\" or its translated equivalent." })
addRow({ path = "eligible.modAssigned", type = "bool", default = true, section = "eligibility",
    label = "Re-rename mod-assigned names",
    help = "Re-renames a line the mod already named when it changes.\n"
        .. "Example: adding a stop updates the name again; off\n"
        .. "keeps the first name the mod ever gave it." })
addRow({ path = "defaults.extraPrefixes", type = "string", default = "", section = "eligibility",
    label = "Extra default-name words",
    help = "Comma-separated words also treated as default names,\n"
        .. "for other languages, e.g. \"Linie,Ligne\"." })
addRow({ path = "minStops", type = "int", default = 2, min = 1, max = 10, section = "eligibility",
    label = "Minimum stops",
    help = "Lines with fewer distinct stops than this are left\n"
        .. "alone. Example: at 2, a single-stop shuttle is skipped." })

for __, kind in ipairs(kinds.list) do
    addRow({ path = "label.kind." .. kind, type = "string", default = KIND_TYPE_TEXT[kind], section = "labels",
        label = kinds.label[kind] .. " label",
        help = "Text substituted for {type} on " .. kinds.label[kind] .. " lines.\n"
            .. "Example: {type} {towns} becomes \"" .. KIND_TYPE_TEXT[kind] .. " Springfield\"." })
end
for __, scope in ipairs(kinds.scopes) do
    addRow({ path = "label.scope." .. scope, type = "string", default = SCOPE_TYPE_TEXT[scope], section = "labels",
        label = SCOPE_TYPE_TEXT[scope] .. " label",
        help = "Text substituted for {scope} on " .. scope .. "-scope lines.\n"
            .. "Example: {scope} {towns} becomes \"" .. SCOPE_TYPE_TEXT[scope] .. " Springfield\"." })
end

addRow({ path = "scope.localMaxTowns", type = "int", default = 1, min = 1, max = 5, section = "scope",
    label = "Local: max towns",
    help = "A line serving this many distinct towns or fewer counts\n"
        .. "as local. Example: 1 means only single-town lines." })
addRow({ path = "scope.regionalMinTowns", type = "int", default = 3, min = 2, max = 10, section = "scope",
    label = "Regional: min towns",
    help = "A line serving this many distinct towns or more counts\n"
        .. "as regional. Example: at 3, a 3-town line is regional." })

addRow({ path = "sep.towns", type = "string", default = " \226\128\147 ", section = "separators",
    label = "Town separator",
    help = "Text placed between the first and last town in {towns}.\n"
        .. "Example: joins \"Springfield\" and \"Shelbyville\"." })
addRow({ path = "sep.via", type = "string", default = ", ", section = "separators",
    label = "Via separator",
    help = "Text placed between intermediate towns listed in {via}.\n"
        .. "Example: with \", \" a line via two towns reads\n"
        .. "\"via Ogdenville, North Haverbrook\"." })
addRow({ path = "sep.cargo", type = "string", default = ", ", section = "separators",
    label = "Cargo separator",
    help = "Text placed between individual cargo names listed in\n"
        .. "{cargo}. Example: with \", \", two cargo types read\n"
        .. "\"Coal, Steel\"." })

addRow({ path = "cargo.max", type = "int", default = 2, min = 1, max = 6, section = "cargo",
    label = "Max cargo names shown",
    help = "More distinct cargo types than this collapse {cargo} to\n"
        .. "the mixed-cargo label. Example: at 2, three cargo types\n"
        .. "collapse to \"Mixed\"." })
addRow({ path = "cargo.mixedLabel", type = "string", default = "Mixed", section = "cargo",
    label = "Mixed-cargo label",
    help = "Text shown for {cargo} once a line carries more distinct\n"
        .. "cargo types than the maximum above, e.g. \"Mixed\" for a\n"
        .. "line hauling coal, steel and ore." })
addRow({ path = "cargo.hidePassengers", type = "bool", default = true, section = "cargo",
    label = "Hide passengers on passenger-only lines",
    help = "Omits the word for passengers from {cargo} on a\n"
        .. "passengers-only line, so it renders empty instead of\n"
        .. "\"Passengers\"." })

addRow({ path = "via.max", type = "int", default = 2, min = 0, max = 4, section = "via",
    label = "Max via towns shown",
    help = "Intermediate towns beyond this count are left out of\n"
        .. "{via}. Example: at 2, a line through four towns shows\n"
        .. "only the middle two towns." })

addRow({ path = "industry.radius", type = "int", default = 400, min = 50, max = 2000, section = "industry",
    label = "Search radius",
    help = "How far from each end stop the mod looks for a nearby\n"
        .. "industry, in game distance units. Example: at 400, a\n"
        .. "coal mine 300 units from the stop is found." })
addRow({ path = "industry.fallback", type = "enum", default = "stop", values = { "stop", "town", "empty" }, section = "industry",
    label = "When no industry is found",
    help = "\"stop\" shows the station name, \"town\" shows the town\n"
        .. "name, \"empty\" leaves that part of the pattern blank." })

addRow({ path = "number.scope", type = "enum", default = "sameName", values = { "sameName", "kind", "global" }, section = "numbering",
    label = "Numbering scope",
    help = "\"sameName\" numbers lines with the same rendered name\n"
        .. "together; \"kind\" by line kind; \"global\" across all lines." })
addRow({ path = "number.first", type = "enum", default = "blank", values = { "blank", "one" }, section = "numbering",
    label = "First number",
    help = "\"blank\" leaves the first line in a group unnumbered;\n"
        .. "\"one\" always shows a number, starting at 1." })
addRow({ path = "number.pad", type = "int", default = 0, min = 0, max = 4, section = "numbering",
    label = "Zero-pad width",
    help = "Pads {n} with leading zeros to this many digits.\n"
        .. "Example: a width of 2 turns 3 into \"03\"." })

addRow({ path = "scan.linesPerTick", type = "int", default = 5, min = 1, max = 50, section = "performance",
    label = "Lines checked per tick",
    help = "How many lines the mod examines on each game tick.\n"
        .. "Example: at 5, a save with 300 lines is fully checked\n"
        .. "about every 12 seconds." })
addRow({ path = "scan.settleSeconds", type = "int", default = 5, min = 0, max = 60, section = "performance",
    label = "Settle delay",
    help = "How long, in real seconds, a line's stops, vehicle count\n"
        .. "and current name must all stay the same before the mod\n"
        .. "reads it and considers a rename; changing any of them\n"
        .. "restarts the wait, e.g. adding a vehicle or renaming it." })
addRow({ path = "preview.linesPerFrame", type = "int", default = 25, min = 1, max = 200, section = "performance",
    label = "Lines previewed per frame",
    help = "How many lines the Lines tab reads per GUI frame while\n"
        .. "building a full preview. Example: at 25, previewing 250\n"
        .. "lines takes about 10 frames." })

addRow({ path = "log.level", type = "enum", default = "info", values = { "error", "info", "debug" }, section = "logging",
    label = "Log level",
    help = "\"error\" logs failures only, \"info\" adds normal activity,\n"
        .. "\"debug\" adds fine detail for diagnosing a problem." })

addRow({ path = "patterns.default", type = "string", default = DEFAULT_PATTERN, nonEmpty = true, section = "patterns",
    label = "Default pattern",
    help = "Naming pattern used for any line kind without its own\n"
        .. "custom pattern below. Example: {type} {towns} renders\n"
        .. "as \"Bus Springfield\" for a one-town bus line." })
for __, kind in ipairs(kinds.list) do
    local default = kinds.cargo[kind] and CARGO_PATTERN or ""
    local lowerLabel = kinds.label[kind]:lower()
    addRow({ path = "patterns." .. kind, type = "string", default = default, section = "patterns",
        label = kinds.label[kind] .. " pattern",
        help = "Naming pattern used only for " .. lowerLabel .. " lines.\n"
            .. "Example: leaving it blank makes " .. lowerLabel .. " lines\n"
            .. "use the default pattern above instead." })
end
for __, kind in ipairs(kinds.list) do
    addRow({ path = "kinds." .. kind .. ".autoRename", type = "bool", default = true, section = "patterns",
        label = kinds.label[kind] .. " auto-rename",
        help = "Turns automatic renaming on or off for just this kind.\n"
            .. "Example: turn off " .. kinds.label[kind] .. " to rename\n"
            .. "them yourself while every other kind keeps auto-renaming." })
end

settings.schema = schema

-- A preset's pattern table: the given default, plus the given cargo pattern for every cargo kind.
local function cargoPatterns(defaultPattern, cargoPattern)
    local patterns = { default = defaultPattern }
    for __, kind in ipairs(kinds.list) do
        if kinds.cargo[kind] then patterns[kind] = cargoPattern end
    end
    return patterns
end

settings.presets = {
    { key = "simple", label = "Simple",
      help = "The shipped defaults: town names for passenger lines,\n"
          .. "cargo and industries for freight.",
      patterns = cargoPatterns(DEFAULT_PATTERN, CARGO_PATTERN) },
    { key = "upstream", label = "Upstream",
      help = "The original Auto Line Namer style: type, cargo, towns,\n"
          .. "scope and a number, all in one.",
      patterns = { default = UPSTREAM_PATTERN } },
    { key = "detailed", label = "Detailed",
      help = "Station names instead of town names, with the via towns\n"
          .. "shown in between.",
      patterns = cargoPatterns(DETAILED_PATTERN, DETAILED_CARGO_PATTERN) },
}

local function splitPath(path)
    local parts = {}
    for part in path:gmatch("[^.]+") do parts[#parts + 1] = part end
    return parts
end

-- Writes value at the dotted path, creating intermediate tables. Does not validate.
local function rawSet(tbl, path, value)
    local parts = splitPath(path)
    local cur = tbl
    for i = 1, #parts - 1 do
        local key = parts[i]
        if type(cur[key]) ~= "table" then cur[key] = {} end
        cur = cur[key]
    end
    cur[parts[#parts]] = value
end

function settings.row(path)
    return byPath[path]
end

function settings.rowsIn(sectionKey)
    local rows = {}
    for __, row in ipairs(schema) do
        if row.section == sectionKey then rows[#rows + 1] = row end
    end
    return rows
end

function settings.get(tbl, path)
    if type(tbl) ~= "table" then return nil end
    local cur = tbl
    for __, key in ipairs(splitPath(path)) do
        if type(cur) ~= "table" then return nil end
        cur = cur[key]
    end
    return cur
end

function settings.validate(row, value)
    if row.type == "bool" then
        if type(value) ~= "boolean" then return false, "must be true or false" end
        return true
    elseif row.type == "int" then
        if type(value) ~= "number" then return false, "must be a number" end
        if value ~= math.floor(value) then return false, "must be a whole number" end
        if row.min and value < row.min then return false, "must be at least " .. tostring(row.min) end
        if row.max and value > row.max then return false, "must be at most " .. tostring(row.max) end
        return true
    elseif row.type == "number" then
        if type(value) ~= "number" then return false, "must be a number" end
        if row.min and value < row.min then return false, "must be at least " .. tostring(row.min) end
        if row.max and value > row.max then return false, "must be at most " .. tostring(row.max) end
        return true
    elseif row.type == "string" then
        if type(value) ~= "string" then return false, "must be text" end
        if #value > 200 then return false, "must be at most 200 bytes" end
        if row.nonEmpty and value == "" then return false, "must not be empty" end
        return true
    elseif row.type == "enum" then
        if type(value) ~= "string" then return false, "must be one of: " .. table.concat(row.values, ", ") end
        for __, choice in ipairs(row.values) do
            if choice == value then return true end
        end
        return false, "must be one of: " .. table.concat(row.values, ", ")
    end
    return false, "unknown setting type: " .. tostring(row.type)
end

function settings.defaults()
    local result = {}
    for __, row in ipairs(schema) do
        rawSet(result, row.path, row.default)
    end
    return result
end

function settings.set(tbl, path, value)
    local row = byPath[path]
    if not row then return false, "unknown setting: " .. path end
    local ok, reason = settings.validate(row, value)
    if not ok then return false, reason end
    rawSet(tbl, path, value)
    return true
end

function settings.merge(userDefaults, saved)
    if type(userDefaults) ~= "table" then userDefaults = {} end
    if type(saved) ~= "table" then saved = {} end
    local result = settings.defaults()
    for __, row in ipairs(schema) do
        local savedValue = settings.get(saved, row.path)
        if savedValue ~= nil and settings.validate(row, savedValue) then
            rawSet(result, row.path, savedValue)
        else
            local userValue = settings.get(userDefaults, row.path)
            if userValue ~= nil and settings.validate(row, userValue) then
                rawSet(result, row.path, userValue)
            end
        end
    end
    return result
end

function settings.patternFor(tbl, kind)
    local pattern = tbl.patterns and tbl.patterns[kind]
    if type(pattern) == "string" and pattern ~= "" then return pattern end
    return tbl.patterns and tbl.patterns.default
end

local function defaultText(row)
    local d = row.default
    if row.type == "bool" then return d and "on" or "off" end
    if row.type == "string" then
        if d == "" then return "(empty)" end
        return "\"" .. d .. "\""
    end
    return tostring(d)
end

function settings.helpText(row)
    local text = row.help .. "\n\nDefault: " .. defaultText(row)
    if row.type == "int" or row.type == "number" then
        text = text .. "   Range: " .. tostring(row.min) .. " to " .. tostring(row.max)
    elseif row.type == "enum" then
        text = text .. "   Choices: " .. table.concat(row.values, ", ")
    end
    return text
end

local presetByKey = {}
for __, preset in ipairs(settings.presets) do presetByKey[preset.key] = preset end

function settings.applyPreset(tbl, key)
    local preset = presetByKey[key]
    if not preset then return false end
    if type(tbl.patterns) ~= "table" then tbl.patterns = {} end
    tbl.patterns.default = preset.patterns.default
    for __, kind in ipairs(kinds.list) do
        tbl.patterns[kind] = preset.patterns[kind] or ""
    end
    return true
end

function settings.resetSection(tbl, sectionKey)
    for __, row in ipairs(settings.rowsIn(sectionKey)) do
        rawSet(tbl, row.path, row.default)
    end
end

return settings
