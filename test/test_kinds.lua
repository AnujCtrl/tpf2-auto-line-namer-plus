local kinds = require("anujctrl/alnp/kinds")
local eq = require("fake_api").eq
local t = {}

function t.there_are_ten_kinds_ending_in_unknown()
    eq(#kinds.list, 10)
    eq(kinds.list[#kinds.list], "unknown")
end

function t.every_kind_has_a_label()
    for __, kind in ipairs(kinds.list) do
        assert(type(kinds.label[kind]) == "string" and kinds.label[kind] ~= "", "no label for " .. kind)
    end
end

function t.cargo_kinds_are_real_kinds()
    local known = {}
    for __, kind in ipairs(kinds.list) do known[kind] = true end
    for kind in pairs(kinds.cargo) do assert(known[kind], kind .. " is not in kinds.list") end
    eq(kinds.cargo, { truck = true, trainCargo = true, shipCargo = true, airCargo = true })
end

function t.scopes_are_local_intercity_regional()
    eq(kinds.scopes, { "local", "intercity", "regional" })
end

return t
