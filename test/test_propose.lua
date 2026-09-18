local naming = require("anujctrl/alnp/naming")
local settings = require("anujctrl/alnp/settings")
local propose = require("anujctrl/alnp/propose")
local eq = require("fake_api").eq

local t = {}

-- naming.sampleFacts(kind) leaves facts.modes = {} regardless of `kind`, so classify.kind
-- (which propose.name calls internally) can never recover the intended kind from it alone.
-- Add the mode flag classify.kind actually reads, on top of the sample data.
local MODE_OF = {
    bus = "bus", tram = "tram", truck = "truck",
    trainPassenger = "train", trainCargo = "train",
    shipPassenger = "ship", shipCargo = "ship",
    airPassenger = "air", airCargo = "air",
}

local function factsFor(kind)
    local facts = naming.sampleFacts(kind)
    local mode = MODE_OF[kind]
    if mode then facts.modes = { [mode] = true } end
    return facts
end

local function busFacts()
    return factsFor("bus")
end

-- The base rendered name (no {n}) for busFacts() under the default pattern and settings.
local function baseBusName(tbl)
    return "Bus Springfield" .. tbl.sep.towns .. "Shelbyville"
end

function t.default_two_stop_bus_line()
    local tbl = settings.defaults()
    local name, n, key = propose.name(busFacts(), nil, tbl, nil)
    local expected = baseBusName(tbl)
    eq(name, expected)
    eq(n, 1)
    eq(key, "name:" .. expected)
end

function t.taken_first_number_bumps_the_second_line_to_two()
    local tbl = settings.defaults()
    local expected = baseBusName(tbl)
    local key = "name:" .. expected
    local taken = { [key] = { [1] = true } }
    local name, n = propose.name(busFacts(), nil, tbl, taken)
    eq(name, expected .. " 2")
    eq(n, 2)
end

function t.record_keeps_its_number_when_the_key_still_matches()
    local tbl = settings.defaults()
    local expected = baseBusName(tbl)
    local key = "name:" .. expected
    local record = { number = 3, numberKey = key }
    -- 1 and 2 are free (no takenByKey passed) but the record should still keep 3.
    local name, n = propose.name(busFacts(), record, tbl, nil)
    eq(name, expected .. " 3")
    eq(n, 3)
end

function t.record_with_a_stale_key_is_renumbered_to_the_lowest_free()
    local tbl = settings.defaults()
    local expected = baseBusName(tbl)
    -- The record's numberKey does not match the key freshly computed from the base name
    -- (as if the base name changed since the record was last assigned).
    local record = { number = 5, numberKey = "stale-key" }
    local name, n = propose.name(busFacts(), record, tbl, nil)
    eq(n, 1)
    eq(name, expected) -- n == 1 renders blank (number.first == "blank")
end

function t.number_scope_kind_and_global_change_the_key()
    local tbl = settings.defaults()
    assert(settings.set(tbl, "number.scope", "kind"))
    local kindKey = select(3, propose.name(busFacts(), nil, tbl, nil))
    eq(kindKey, "kind:bus")

    assert(settings.set(tbl, "number.scope", "global"))
    local globalKey = select(3, propose.name(busFacts(), nil, tbl, nil))
    eq(globalKey, "*")
end

function t.pattern_without_a_number_token_has_no_n_or_key()
    local tbl = settings.defaults()
    assert(settings.set(tbl, "patterns.default", "{type} {towns}"))
    local name, n, key = propose.name(busFacts(), nil, tbl, nil)
    eq(name, "Bus Springfield" .. tbl.sep.towns .. "Shelbyville")
    eq(n, nil)
    eq(key, nil)
end

function t.fewer_than_min_stops_is_left_alone()
    local tbl = settings.defaults()
    local oneStop = {
        modes = { bus = true },
        vehicleCount = 1,
        cargos = { "Passengers" },
        carriesPassengers = true,
        carriesCargo = false,
        towns = { "Springfield" },
        stops = { { stationGroup = 1, stop = "Springfield Central", town = "Springfield" } },
    }
    eq(propose.name(oneStop, nil, tbl, nil), nil)

    assert(settings.set(tbl, "minStops", 1))
    local name = propose.name(oneStop, nil, tbl, nil)
    assert(name ~= nil and name ~= "", "expected a name once minStops allows one stop")
end

function t.a_pattern_that_renders_blank_is_left_alone()
    local tbl = settings.defaults()
    -- {via} is empty on a two-town line (no intermediate towns), and the whole pattern is
    -- just that one token, so the render result is "".
    assert(settings.set(tbl, "patterns.default", "[{via}]"))
    eq(propose.name(busFacts(), nil, tbl, nil), nil)
end

function t.cargo_train_uses_its_own_pattern_then_falls_back_to_default()
    local tbl = settings.defaults()
    local facts = factsFor("trainCargo")

    local cargoName = propose.name(facts, nil, tbl, nil)
    assert(cargoName:find("Coal mine", 1, true), "expected the cargo pattern: got " .. tostring(cargoName))

    assert(settings.set(tbl, "patterns.trainCargo", ""))
    local defaultName = propose.name(facts, nil, tbl, nil)
    assert(not defaultName:find("Coal mine", 1, true), "expected the default pattern: got " .. tostring(defaultName))
    assert(defaultName:find("Freight", 1, true), "expected the Freight label: got " .. tostring(defaultName))
end

function t.takenByKey_skips_the_excluded_line_and_records_without_a_number_and_groups_by_key()
    local records = {
        [1] = { numberKey = "k1", number = 1 },
        [2] = { numberKey = "k1", number = 2 },
        [3] = { numberKey = "k2", number = 1 },
        [4] = {},
        [5] = { numberKey = "k3" },       -- no number
        [6] = { number = 9 },             -- no numberKey
        [7] = { numberKey = "k1", number = 99 }, -- excluded
    }
    eq(propose.takenByKey(records, 7), { k1 = { [1] = true, [2] = true }, k2 = { [1] = true } })
end

function t.takenByKey_handles_nil_records()
    eq(propose.takenByKey(nil, 1), {})
end

return t
