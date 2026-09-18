-- What a line would be called right now. Shared by the engine (which renames) and the Lines tab
-- (which previews), so the two can never disagree.
local classify = require "anujctrl/alnp/classify"
local naming = require "anujctrl/alnp/naming"
local settings = require "anujctrl/alnp/settings"

local propose = {}

-- Lines that share a key share one number sequence (spec §7.2).
local function numberKeyFor(scope, kind, baseName)
    if scope == "global" then return "*" end
    if scope == "kind" then return "kind:" .. kind end
    return "name:" .. baseName
end

-- { [numberKey] = { [n] = true } } for every line except one.
function propose.takenByKey(records, exceptLineId)
    local taken = {}
    for lineId, record in pairs(records or {}) do
        if lineId ~= exceptLineId and record.numberKey and record.number then
            taken[record.numberKey] = taken[record.numberKey] or {}
            taken[record.numberKey][record.number] = true
        end
    end
    return taken
end

-- Returns nil when the line should be left alone (too few stops, or a blank result);
-- otherwise name, n, numberKey (n and numberKey are nil when the pattern has no number token).
function propose.name(facts, record, tbl, takenByKey)
    if #(facts.stops or {}) < tbl.minStops then return nil end
    local kind = classify.kind(facts)
    local ctx = { settings = tbl, kind = kind, scope = classify.scope(facts, tbl) }
    local pattern = settings.patternFor(tbl, kind)

    local n, key
    if naming.usesNumber(pattern) then
        local baseName = naming.render(pattern, facts, ctx) -- ctx.n is nil, so the number renders empty
        key = numberKeyFor(tbl.number.scope, kind, baseName)
        local current = record and record.numberKey == key and record.number or nil
        n = naming.pickNumber(current, (takenByKey or {})[key] or {})
        ctx.n = n
    end

    local name = naming.render(pattern, facts, ctx)
    if name == "" then return nil end
    return name, n, key
end

return propose
