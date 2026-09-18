local classify = require("anujctrl/alnp/classify")
local kinds = require("anujctrl/alnp/kinds")
local eq = require("fake_api").eq
local t = {}

local function line(modes, passengers, cargo, vehicles, towns)
    return { modes = modes, carriesPassengers = passengers, carriesCargo = cargo,
        vehicleCount = vehicles == nil and 1 or vehicles, towns = towns or {} }
end

-- classify.kind: one row per line of the case table in task-04-classify.md.
local KIND_CASES = {
    { label = "bus_with_passengers_is_bus",
        modes = { bus = true }, passengers = true, cargo = false, vehicles = 1, expected = "bus" },
    { label = "bus_and_truck_with_cargo_only_is_truck",
        modes = { bus = true, truck = true }, passengers = false, cargo = true, vehicles = 1, expected = "truck" },
    { label = "truck_alone_with_cargo_is_truck",
        modes = { truck = true }, passengers = false, cargo = true, vehicles = 1, expected = "truck" },
    { label = "bus_and_truck_with_passengers_and_cargo_is_bus",
        modes = { bus = true, truck = true }, passengers = true, cargo = true, vehicles = 1, expected = "bus" },
    { label = "truck_with_no_vehicles_infers_cargo_from_modes",
        modes = { truck = true }, passengers = false, cargo = false, vehicles = 0, expected = "truck" },
    { label = "bus_and_truck_with_no_vehicles_infers_passenger_from_modes",
        modes = { bus = true, truck = true }, passengers = false, cargo = false, vehicles = 0, expected = "bus" },
    { label = "tram_with_passengers_is_tram",
        modes = { tram = true }, passengers = true, cargo = false, vehicles = 1, expected = "tram" },
    { label = "tram_wins_over_bus",
        modes = { tram = true, bus = true }, passengers = true, cargo = false, vehicles = 1, expected = "tram" },
    { label = "train_with_passengers_is_train_passenger",
        modes = { train = true }, passengers = true, cargo = false, vehicles = 1, expected = "trainPassenger" },
    { label = "train_with_cargo_is_train_cargo",
        modes = { train = true }, passengers = false, cargo = true, vehicles = 1, expected = "trainCargo" },
    { label = "train_with_passengers_and_cargo_is_train_passenger",
        modes = { train = true }, passengers = true, cargo = true, vehicles = 1, expected = "trainPassenger" },
    { label = "train_with_no_vehicles_defaults_to_passenger",
        modes = { train = true }, passengers = false, cargo = false, vehicles = 0, expected = "trainPassenger" },
    { label = "ship_with_cargo_is_ship_cargo",
        modes = { ship = true }, passengers = false, cargo = true, vehicles = 1, expected = "shipCargo" },
    { label = "ship_with_passengers_is_ship_passenger",
        modes = { ship = true }, passengers = true, cargo = false, vehicles = 1, expected = "shipPassenger" },
    { label = "air_with_cargo_is_air_cargo",
        modes = { air = true }, passengers = false, cargo = true, vehicles = 1, expected = "airCargo" },
    { label = "air_with_passengers_is_air_passenger",
        modes = { air = true }, passengers = true, cargo = false, vehicles = 1, expected = "airPassenger" },
    { label = "empty_modes_is_unknown",
        modes = {}, passengers = true, cargo = false, vehicles = 1, expected = "unknown" },
    { label = "nil_modes_is_unknown",
        modes = nil, passengers = true, cargo = false, vehicles = 1, expected = "unknown" },
}

for __, case in ipairs(KIND_CASES) do
    t["kind_" .. case.label] = function()
        eq(classify.kind(line(case.modes, case.passengers, case.cargo, case.vehicles)), case.expected, case.label)
    end
end

function t.every_kind_case_result_is_a_member_of_kinds_list()
    local known = {}
    for __, k in ipairs(kinds.list) do known[k] = true end
    for __, case in ipairs(KIND_CASES) do
        local result = classify.kind(line(case.modes, case.passengers, case.cargo, case.vehicles))
        assert(known[result], case.label .. ": " .. tostring(result) .. " is not in kinds.list")
    end
end

-- classify.scope
local SCOPE = { scope = { localMaxTowns = 1, regionalMinTowns = 3 } }
local SCOPE_WIDE = { scope = { localMaxTowns = 2, regionalMinTowns = 4 } }
local SCOPE_OVERLAP = { scope = { localMaxTowns = 3, regionalMinTowns = 2 } }

local SCOPE_CASES = {
    { label = "zero_towns_is_local", towns = {}, tbl = SCOPE, expected = "local" },
    { label = "one_town_is_local", towns = { "A" }, tbl = SCOPE, expected = "local" },
    { label = "two_towns_is_intercity", towns = { "A", "B" }, tbl = SCOPE, expected = "intercity" },
    { label = "three_towns_is_regional", towns = { "A", "B", "C" }, tbl = SCOPE, expected = "regional" },
    { label = "five_towns_is_regional", towns = { "A", "B", "C", "D", "E" }, tbl = SCOPE, expected = "regional" },
    { label = "two_towns_is_local_with_wider_thresholds", towns = { "A", "B" }, tbl = SCOPE_WIDE, expected = "local" },
    { label = "three_towns_is_intercity_with_wider_thresholds", towns = { "A", "B", "C" }, tbl = SCOPE_WIDE, expected = "intercity" },
    { label = "four_towns_is_regional_with_wider_thresholds", towns = { "A", "B", "C", "D" }, tbl = SCOPE_WIDE, expected = "regional" },
    { label = "overlapping_thresholds_favour_regional", towns = { "A", "B" }, tbl = SCOPE_OVERLAP, expected = "regional" },
}

for __, case in ipairs(SCOPE_CASES) do
    t["scope_" .. case.label] = function()
        eq(classify.scope({ towns = case.towns }, case.tbl), case.expected, case.label)
    end
end

function t.scope_nil_towns_is_local()
    eq(classify.scope({}, SCOPE), "local")
end

return t
