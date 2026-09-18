-- Pure pattern-rendering: turns a pattern like "{type} {towns}[ {n}]" plus a facts table (C3)
-- into a line's name. No game API calls; see spec section 7.
local kinds = require("anujctrl/alnp/kinds")

local naming = {}

-- Upstream alias -> canonical token name.
local ALIASES = {
    transportType = "type",
    lineType = "scope",
    cargoTypes = "cargo",
    townNames = "towns",
    lineNumber = "n",
}

-- One UTF-8 character, as the brief's pattern (bytes: 1 lead byte, 0+ continuation bytes).
local UTF8_CHAR = "[\1-\127\194-\244][\128-\191]*"

local function utf8Chars(s)
    local chars = {}
    for c in s:gmatch(UTF8_CHAR) do chars[#chars + 1] = c end
    return chars
end

-- Keep the leading `n` UTF-8 characters of a single word.
local function truncateWord(word, n)
    local chars = utf8Chars(word)
    local kept = {}
    for i = 1, math.min(n, #chars) do kept[i] = chars[i] end
    return table.concat(kept)
end

-- Keep the leading `n` characters of each ASCII-space-separated word, concatenated without
-- spaces: "New York" with n=3 -> "NewYor".
local function truncate(value, n)
    local out = {}
    for word in value:gmatch("%S+") do out[#out + 1] = truncateWord(word, n) end
    return table.concat(out)
end

-- mods is the text after the colon, e.g. "3", "u", "l", "3u", "u3", or nil/"" for none.
local function applyModifiers(value, mods)
    if not mods or mods == "" then return value end
    local digits = mods:match("(%d+)")
    if digits then value = truncate(value, tonumber(digits)) end
    local upper, lower = false, false
    for letter in mods:gmatch("%a") do
        if letter == "u" then upper = true
        elseif letter == "l" then lower = true end
    end
    if upper then value = value:upper()
    elseif lower then value = value:lower() end
    return value
end

-- facts.stops[i].industry, or a fallback (tbl.industry.fallback) when it is nil.
local function industryOf(stop, tbl)
    if not stop then return "" end
    if stop.industry then return stop.industry end
    local fallback = tbl.industry.fallback
    if fallback == "stop" then return stop.stop or ""
    elseif fallback == "town" then return stop.town or "" end
    return ""
end

local function formatNumber(n, numberCfg)
    if n == nil then return "" end
    if n == 1 and numberCfg.first == "blank" then return "" end
    local pad = numberCfg.pad or 0
    if pad > 0 then return ("%0" .. pad .. "d"):format(n) end
    return tostring(n)
end

-- Each entry: canonical token name -> function(facts, ctx) -> elements (array of strings),
-- separator (string to join them with). Single-value tokens return a one-element array.
local VALUES = {
    type = function(__, ctx)
        return { ctx.settings.label.kind[ctx.kind] or "" }, ""
    end,
    scope = function(__, ctx)
        return { ctx.settings.label.scope[ctx.scope] or "" }, ""
    end,
    cargo = function(facts, ctx)
        local tbl = ctx.settings
        if tbl.cargo.hidePassengers and facts.carriesCargo == false then
            return { "" }, tbl.sep.cargo
        end
        local cargos = facts.cargos or {}
        if #cargos > tbl.cargo.max then
            return { tbl.cargo.mixedLabel or "" }, tbl.sep.cargo
        end
        local elements = {}
        for i, cargoName in ipairs(cargos) do elements[i] = cargoName end
        return elements, tbl.sep.cargo
    end,
    towns = function(facts, ctx)
        local towns = facts.towns or {}
        local elements
        if #towns == 0 then elements = {}
        elseif #towns == 1 then elements = { towns[1] }
        else elements = { towns[1], towns[#towns] } end
        return elements, ctx.settings.sep.towns
    end,
    firstTown = function(facts, __)
        local towns = facts.towns or {}
        return { towns[1] or "" }, ""
    end,
    lastTown = function(facts, __)
        local towns = facts.towns or {}
        return { towns[#towns] or "" }, ""
    end,
    via = function(facts, ctx)
        local towns = facts.towns or {}
        local middle = {}
        for i = 2, #towns - 1 do middle[#middle + 1] = towns[i] end
        local max = ctx.settings.via.max or 0
        local elements = {}
        for i = 1, math.min(max, #middle) do elements[i] = middle[i] end
        return elements, ctx.settings.sep.via
    end,
    firstStop = function(facts, __)
        local stops = facts.stops or {}
        local stop = stops[1]
        return { (stop and stop.stop) or "" }, ""
    end,
    lastStop = function(facts, __)
        local stops = facts.stops or {}
        local stop = stops[#stops]
        return { (stop and stop.stop) or "" }, ""
    end,
    firstIndustry = function(facts, ctx)
        local stops = facts.stops or {}
        return { industryOf(stops[1], ctx.settings) }, ""
    end,
    lastIndustry = function(facts, ctx)
        local stops = facts.stops or {}
        return { industryOf(stops[#stops], ctx.settings) }, ""
    end,
    n = function(__, ctx)
        return { formatNumber(ctx.n, ctx.settings.number) }, ""
    end,
}

-- Renders every {token} in `text`. Returns the substituted text and whether any known token
-- inside it rendered "" (an unknown token never counts as empty).
local function renderSegment(text, facts, ctx)
    local anyEmpty = false
    local rendered = text:gsub("%b{}", function(token)
        local inner = token:sub(2, -2)
        local name, mods = inner:match("^([^:]*):(.*)$")
        if not name then name = inner end
        local canonical = ALIASES[name] or name
        local valueFn = VALUES[canonical]
        if not valueFn then return token end
        local elements, sep = valueFn(facts, ctx)
        local parts = {}
        for i, element in ipairs(elements) do parts[i] = applyModifiers(element or "", mods) end
        local joined = table.concat(parts, sep or "")
        if joined == "" then anyEmpty = true end
        return joined
    end)
    return rendered, anyEmpty
end

-- pattern -> facts (C3) -> ctx { settings, kind, scope, n } -> string. See spec section 7.
function naming.render(pattern, facts, ctx)
    local out = {}
    local i, len = 1, #pattern
    while i <= len do
        local openPos = pattern:find("[", i, true)
        if not openPos then
            out[#out + 1] = renderSegment(pattern:sub(i), facts, ctx)
            break
        end
        if openPos > i then
            out[#out + 1] = renderSegment(pattern:sub(i, openPos - 1), facts, ctx)
        end
        local closePos = pattern:find("]", openPos + 1, true)
        if not closePos then
            -- Unclosed "[": literal text; keep scanning for tokens after it.
            out[#out + 1] = "["
            i = openPos + 1
        else
            local inner = pattern:sub(openPos + 1, closePos - 1)
            local rendered, anyEmpty = renderSegment(inner, facts, ctx)
            if not anyEmpty then out[#out + 1] = rendered end
            i = closePos + 1
        end
    end
    local result = table.concat(out):gsub("%s+", " ")
    return result:match("^%s*(.-)%s*$")
end

-- true if `pattern` contains {n} or {lineNumber}, with or without modifiers.
function naming.usesNumber(pattern)
    for token in pattern:gmatch("%b{}") do
        local inner = token:sub(2, -2)
        local name = inner:match("^([^:]*)")
        if (ALIASES[name] or name) == "n" then return true end
    end
    return false
end

-- current if it is set and free; else the lowest integer >= 1 not in `taken`.
function naming.pickNumber(current, taken)
    taken = taken or {}
    if current ~= nil and not taken[current] then return current end
    local n = 1
    while taken[n] do n = n + 1 end
    return n
end

-- classify.kind's transport-mode key for each kind; "unknown" has none, so its modes stay {}.
local MODE_BY_KIND = {
    bus = "bus",
    tram = "tram",
    truck = "truck",
    trainPassenger = "train",
    trainCargo = "train",
    shipPassenger = "ship",
    shipCargo = "ship",
    airPassenger = "air",
    airCargo = "air",
}

-- Plausible facts (C3) for previewing a pattern for `kind`, without reading the game. Built so
-- that classify.kind(naming.sampleFacts(kind)) == kind for every entry of kinds.list (this module
-- does not require classify itself; that equivalence is exercised in the test).
function naming.sampleFacts(kind)
    local isCargo = kinds.cargo[kind] == true
    local stops
    if isCargo then
        stops = {
            { stationGroup = 1, stop = "Springfield Yard", town = "Springfield", industry = "Coal mine" },
            { stationGroup = 2, stop = "Shelbyville Docks", town = "Shelbyville", industry = "Steel mill" },
        }
    else
        stops = {
            { stationGroup = 1, stop = "Springfield Central", town = "Springfield" },
            { stationGroup = 2, stop = "Shelbyville East", town = "Shelbyville" },
        }
    end
    local modes = {}
    local modeKey = MODE_BY_KIND[kind]
    if modeKey then modes[modeKey] = true end
    return {
        id = 0,
        name = "",
        modes = modes,
        vehicleCount = 2,
        cargos = isCargo and { "Coal", "Steel" } or { "Passengers" },
        carriesPassengers = not isCargo,
        carriesCargo = isCargo,
        towns = { "Springfield", "Shelbyville" },
        stops = stops,
    }
end

-- Cheat-sheet order, matching spec section 7's token table.
naming.tokens = {
    { token = "{type}", example = "Bus", help = "The line's kind, from the label settings." },
    { token = "{scope}", example = "Intercity", help = "The line's scope: Local, Intercity or Regional." },
    { token = "{cargo}", example = "Coal, Iron ore",
        help = "Cargo carried, or the mixed label past the maximum. Hidden on passenger-only lines by default." },
    { token = "{towns}", example = "Springfield – Shelbyville",
        help = "The first and last town on the line, or the one town when there is only one." },
    { token = "{firstTown}", example = "Springfield", help = "The first town on the line." },
    { token = "{lastTown}", example = "Shelbyville", help = "The last town on the line." },
    { token = "{via}", example = "Ogdenville, North Haverbrook",
        help = "Intermediate towns between the first and last, up to the configured maximum." },
    { token = "{firstStop}", example = "Springfield Central", help = "The name of the first stop." },
    { token = "{lastStop}", example = "Shelbyville East", help = "The name of the last stop." },
    { token = "{firstIndustry}", example = "Coal mine",
        help = "The industry at the first stop, or a fallback (stop, town or empty) when there is none." },
    { token = "{lastIndustry}", example = "Steel mill",
        help = "The industry at the last stop, or a fallback (stop, town or empty) when there is none." },
    { token = "{n}", example = "2", help = "A sequence number that tells apart otherwise-identical names." },
}

return naming
