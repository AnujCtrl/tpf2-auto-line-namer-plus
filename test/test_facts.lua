local facts = require("anujctrl/alnp/facts")
local fakeGame = require("fake_game")
local eq = require("fake_api").eq

local t = {}

-- facts.lua caches industry lookups across the whole process (require caches the module), so
-- every test starts by forgetting whatever an earlier test found.

function t.playerLines_returns_ids_and_name_defaults_to_empty_string()
    facts.clearCache()
    fakeGame.world{
        lines = {
            [5] = { name = "Line 5", stops = {}, modes = { "BUS" }, vehicles = {} },
            [3] = { name = "Line 3", stops = {}, modes = { "BUS" }, vehicles = {} },
        },
        player = 1,
    }
    eq(facts.playerLines(), { 3, 5 }, "playerLines")
    eq(facts.name(3), "Line 3", "name of line 3")
    eq(facts.name(999), "", "name of an entity with no NAME component")
end

function t.forLine_on_a_two_town_bus_line_matches_the_c3_shape_exactly()
    facts.clearCache()
    fakeGame.world{
        towns = { [900] = "Springfield", [901] = "Shelbyville" },
        stationGroups = {
            [11] = { name = "Springfield Central", station = 111, town = 900, position = { 0, 0, 0 } },
            [12] = { name = "Shelbyville East", station = 112, town = 901, position = { 500, 0, 0 } },
        },
        vehicles = { [501] = { capacities = { PASSENGERS = 40 } } },
        lines = { [1] = { name = "Line 7", stops = { 11, 12 }, modes = { "BUS" }, vehicles = { 501 } } },
        player = 1,
    }
    eq(facts.forLine(1, nil), {
        id = 1,
        name = "Line 7",
        modes = { bus = true },
        vehicleCount = 1,
        cargos = { "Passengers" },
        carriesPassengers = true,
        carriesCargo = false,
        towns = { "Springfield", "Shelbyville" },
        stops = {
            { stationGroup = 11, stop = "Springfield Central", town = "Springfield" },
            { stationGroup = 12, stop = "Shelbyville East", town = "Shelbyville" },
        },
    }, "forLine")
end

function t.repeated_stops_collapse_and_towns_are_distinct_in_first_seen_order()
    facts.clearCache()
    fakeGame.world{
        towns = { [910] = "Alpha", [911] = "Beta", [912] = "Gamma" },
        stationGroups = {
            [21] = { name = "A", station = 211, town = 910 },
            [22] = { name = "B", station = 212, town = 911 },
            [23] = { name = "C", station = 213, town = 912 },
        },
        lines = { [2] = { name = "Loop", stops = { 21, 22, 23, 22 }, modes = { "BUS" }, vehicles = {} } },
        player = 1,
    }
    local f = facts.forLine(2, nil)
    eq(#f.stops, 3, "distinct stops")
    eq(f.stops[1].stationGroup, 21)
    eq(f.stops[2].stationGroup, 22)
    eq(f.stops[3].stationGroup, 23)
    eq(f.towns, { "Alpha", "Beta", "Gamma" }, "towns in first-seen order")
end

function t.a_stop_whose_group_has_no_town_leaves_town_nil_and_out_of_towns()
    facts.clearCache()
    fakeGame.world{
        towns = { [920] = "Alpha" },
        stationGroups = {
            [31] = { name = "A", station = 311, town = 920 },
            [32] = { name = "Middle of nowhere", station = 312 }, -- no town field: getTown returns -1
        },
        lines = { [3] = { name = "Rural", stops = { 31, 32 }, modes = { "BUS" }, vehicles = {} } },
        player = 1,
    }
    local f = facts.forLine(3, nil)
    eq(f.stops[2].stationGroup, 32)
    eq(f.stops[2].town, nil, "no-town stop has no town")
    eq(f.towns, { "Alpha" }, "the no-town stop contributes nothing")
end

function t.mode_variants_fold_into_their_group()
    facts.clearCache()
    fakeGame.world{
        lines = {
            [41] = { name = "T1", stops = {}, modes = { "ELECTRIC_TRAIN" }, vehicles = {} },
            [42] = { name = "T2", stops = {}, modes = { "SMALL_SHIP" }, vehicles = {} },
            [43] = { name = "T3", stops = {}, modes = { "SMALL_AIRCRAFT" }, vehicles = {} },
            [44] = { name = "T4", stops = {}, modes = { "ELECTRIC_TRAM" }, vehicles = {} },
        },
        player = 1,
    }
    eq(facts.forLine(41, nil).modes, { train = true }, "electric train")
    eq(facts.forLine(42, nil).modes, { ship = true }, "small ship")
    eq(facts.forLine(43, nil).modes, { air = true }, "small aircraft")
    eq(facts.forLine(44, nil).modes, { tram = true }, "electric tram")
end

function t.cargo_names_and_flags_by_vehicle_mix()
    facts.clearCache()
    fakeGame.world{
        vehicles = {
            [50] = { capacities = { COAL = 10 } },
            [51] = { capacities = { IRON_ORE = 5 } },
            [52] = { capacities = { PASSENGERS = 20, COAL = 3 } },
        },
        lines = {
            [51] = { name = "Cargo", stops = {}, modes = { "TRUCK" }, vehicles = { 50, 51 } },
            [52] = { name = "Mixed", stops = {}, modes = { "TRUCK" }, vehicles = { 52 } },
            [53] = { name = "Empty", stops = {}, modes = { "TRUCK" }, vehicles = {} },
        },
        player = 1,
    }
    local cargo = facts.forLine(51, nil)
    eq(cargo.cargos, { "Coal", "Iron ore" }, "cargo names")
    eq(cargo.carriesCargo, true)
    eq(cargo.carriesPassengers, false)

    local mixed = facts.forLine(52, nil)
    eq(mixed.carriesCargo, true)
    eq(mixed.carriesPassengers, true)

    local empty = facts.forLine(53, nil)
    eq(empty.cargos, {}, "no vehicles: no cargos")
    eq(empty.carriesCargo, false)
    eq(empty.carriesPassengers, false)
    eq(empty.vehicleCount, 0)
end

function t.industry_nearest_wins_and_out_of_radius_is_nil_and_passenger_lines_never_look()
    facts.clearCache()
    local world = fakeGame.world{
        towns = { [930] = "Springfield" },
        stationGroups = {
            [61] = { name = "Near Stop", station = 611, town = 930, position = { 0, 0, 0 } },
            [62] = { name = "Far Stop", station = 612, town = 930, position = { 2000, 0, 0 } },
        },
        industries = {
            [701] = { name = "Near Mine", position = { 50, 0, 0 } },
            [702] = { name = "Far Mine", position = { 100, 0, 0 } },
        },
        vehicles = { [601] = { capacities = { COAL = 10 } } },
        lines = {
            [6] = { name = "Cargo Line", stops = { 61, 62 }, modes = { "TRUCK" }, vehicles = { 601 } },
            [7] = { name = "Bus Line", stops = { 61 }, modes = { "BUS" }, vehicles = {} },
        },
        player = 1,
    }
    local f = facts.forLine(6, nil)
    eq(f.stops[1].industry, "Near Mine", "nearest of two within radius")
    eq(f.stops[2].industry, nil, "nothing within radius")

    eq(world.counts.getEntities > 0, true, "cargo line did look up industries")

    facts.clearCache()
    world.counts.getEntities = 0
    facts.forLine(7, nil)
    eq(world.counts.getEntities, 0, "a passenger-only line never calls getEntities")
end

function t.industry_lookups_are_cached_per_stop_until_clearCache()
    facts.clearCache()
    local world = fakeGame.world{
        towns = { [940] = "Springfield" },
        stationGroups = {
            [71] = { name = "Stop", station = 711, town = 940, position = { 0, 0, 0 } },
        },
        industries = { [703] = { name = "Mine", position = { 10, 0, 0 } } },
        vehicles = { [602] = { capacities = { COAL = 10 } } },
        lines = { [8] = { name = "Cargo Line", stops = { 71 }, modes = { "TRUCK" }, vehicles = { 602 } } },
        player = 1,
    }
    facts.forLine(8, nil)
    local afterFirst = world.counts.getEntities
    assert(afterFirst > 0, "first call looks up industries")

    facts.forLine(8, nil)
    eq(world.counts.getEntities, afterFirst, "second call is served from cache")

    facts.clearCache()
    facts.forLine(8, nil)
    assert(world.counts.getEntities > afterFirst, "clearCache forces a fresh lookup")
end

function t.a_broken_industry_lookup_does_not_raise_and_industry_is_nil()
    facts.clearCache()
    local world = fakeGame.world{
        towns = { [950] = "Springfield" },
        stationGroups = {
            [81] = { name = "Stop", station = 811, town = 950, position = { 0, 0, 0 } },
        },
        industries = { [704] = { name = "Mine", position = { 10, 0, 0 } } },
        vehicles = { [603] = { capacities = { COAL = 10 } } },
        lines = { [9] = { name = "Cargo Line", stops = { 81 }, modes = { "TRUCK" }, vehicles = { 603 } } },
        player = 1,
    }
    world.breakGetEntities()
    local f = facts.forLine(9, nil)
    assert(f ~= nil, "forLine still returns facts")
    eq(f.stops[1].industry, nil, "a broken lookup just means no industry")
end

function t.signature_changes_with_stops_vehicles_and_name_and_is_stable_otherwise()
    facts.clearCache()
    local world = fakeGame.world{
        stationGroups = { [91] = { name = "A", station = 911 } },
        vehicles = { [604] = { capacities = { PASSENGERS = 10 } }, [605] = { capacities = { PASSENGERS = 10 } } },
        lines = { [10] = { name = "Line 10", stops = { 91 }, modes = { "BUS" }, vehicles = { 604 } } },
        player = 1,
    }
    local sig1 = facts.signature(10)
    eq(facts.signature(10), sig1, "unchanged: identical signature")

    world.setStops(10, { 91, 92 })
    local sig2 = facts.signature(10)
    assert(sig2 ~= sig1, "adding a stop changes the signature")

    world.setVehicles(10, { 604, 605 })
    local sig3 = facts.signature(10)
    assert(sig3 ~= sig2, "adding a vehicle changes the signature")

    world.renameLine(10, "Renamed")
    local sig4 = facts.signature(10)
    assert(sig4 ~= sig3, "renaming changes the signature")
end

function t.a_removed_line_has_no_signature_or_facts()
    facts.clearCache()
    local world = fakeGame.world{
        lines = { [11] = { name = "Gone soon", stops = {}, modes = { "BUS" }, vehicles = {} } },
        player = 1,
    }
    world.removeLine(11)
    eq(facts.signature(11), nil, "removed line: no signature")
    eq(facts.forLine(11, nil), nil, "removed line: no facts")
end

function t.only_the_first_eight_vehicles_are_sampled_for_cargo()
    facts.clearCache()
    local vehicles = {}
    local vehicleIds = {}
    for i = 1, 8 do
        vehicles[i] = { capacities = { PASSENGERS = 10 } }
        vehicleIds[i] = i
    end
    vehicles[9] = { capacities = { STEEL = 10 } } -- unique cargo, must not be sampled
    vehicleIds[9] = 9
    fakeGame.world{
        vehicles = vehicles,
        lines = { [12] = { name = "Nine Vehicles", stops = {}, modes = { "BUS" }, vehicles = vehicleIds } },
        player = 1,
    }
    local f = facts.forLine(12, nil)
    eq(f.vehicleCount, 9, "vehicleCount counts every vehicle")
    eq(f.cargos, { "Passengers" }, "only the first 8 vehicles are sampled")
    eq(f.carriesCargo, false, "the 9th vehicle's steel never shows up")
end

function t.apiCheck_reports_the_translated_word_and_one_line_per_cargo_stop()
    facts.clearCache()
    fakeGame.world{
        towns = { [960] = "Springfield" },
        stationGroups = {
            [101] = { name = "Coal Yard", station = 1011, town = 960, position = { 0, 0, 0 } },
        },
        industries = { [705] = { name = "Coal Mine", position = { 10, 0, 0 } } },
        vehicles = { [606] = { capacities = { COAL = 10 } } },
        lines = { [13] = { name = "Cargo Line", stops = { 101 }, modes = { "TRUCK" }, vehicles = { 606 } } },
        player = 1,
    }
    local report = facts.apiCheck(nil)
    assert(report[1]:find('_("Line")', 1, true), report[1])
    eq(#report, 2, "one header line plus one entry for the single cargo stop")
    assert(report[2]:find("Coal Yard", 1, true), report[2])
end

-- Y4: on a dead id the real api.engine.getComponent raises "Invalid entity" instead of returning
-- nil, and entities do vanish between two reads (a previewed line deleted while the Lines tab
-- refreshes). Every read of an id the mod did not just prove alive must be checked first.

local function strictWorld()
    facts.clearCache()
    return fakeGame.world{
        strictEntities = true,
        towns = { [900] = "Springfield", [901] = "Shelbyville" },
        stationGroups = {
            [11] = { name = "Springfield Central", station = 111, town = 900, position = { 0, 0, 0 } },
            [12] = { name = "Shelbyville East", station = 112, town = 901, position = { 500, 0, 0 } },
        },
        vehicles = { [501] = { capacities = { PASSENGERS = 40 } } },
        lines = { [1] = { name = "Line 7", stops = { 11, 12 }, modes = { "BUS" }, vehicles = { 501 } } },
        player = 1,
    }
end

function t.name_of_a_line_deleted_between_two_calls_is_empty()
    local world = strictWorld()
    eq(facts.name(1), "Line 7")
    world.removeLine(1)
    eq(facts.name(1), "", "a deleted line must read as an empty name, not raise")
    eq(facts.signature(1), nil)
    eq(facts.forLine(1, nil), nil)
end

function t.a_vehicle_deleted_between_two_calls_does_not_break_the_line()
    local world = strictWorld()
    world.removeEntity(501)
    local f = facts.forLine(1, nil)
    assert(f, "forLine must still describe the line")
    eq(f.cargos, {})
    eq(f.carriesPassengers, false)
end

function t.a_station_group_deleted_between_two_calls_is_skipped()
    local world = strictWorld()
    world.removeEntity(12)
    local f = facts.forLine(1, nil)
    assert(f, "forLine must still describe the line")
    eq(#f.stops, 1, "the dead stop is skipped")
    eq(f.stops[1].stop, "Springfield Central")
    eq(f.towns, { "Springfield" })
end

function t.a_station_deleted_under_a_live_group_is_skipped()
    local world = strictWorld()
    world.removeEntity(112)
    local f = facts.forLine(1, nil)
    assert(f, "forLine must still describe the line")
    eq(#f.stops, 2)
    eq(f.towns, { "Springfield" })
end

-- Y5: apiCheck runs a full forLine per line on one tick, with the industry cache cleared each
-- time, so a big network would freeze the game. It stops early and says that it did.
local function manyLineWorld(count, cargo)
    facts.clearCache()
    local vehicles, lines = {}, {}
    for i = 1, count do
        vehicles[5000 + i] = { capacities = cargo and { COAL = 10 } or { PASSENGERS = 10 } }
        lines[i] = { name = "Line " .. i, stops = {}, modes = { cargo and "TRUCK" or "BUS" },
            vehicles = { 5000 + i } }
    end
    return fakeGame.world{ vehicles = vehicles, lines = lines, player = 1 }
end

function t.apiCheck_stops_after_a_hundred_lines_and_says_so()
    manyLineWorld(140, false)
    local report = facts.apiCheck(nil)
    local last = report[#report]
    assert(last:find("100", 1, true), last)
    assert(last:find("140", 1, true), last)
end

function t.apiCheck_stops_after_ten_cargo_lines_and_says_so()
    manyLineWorld(30, true)
    local report = facts.apiCheck(nil)
    local last = report[#report]
    assert(last:find("10 cargo lines", 1, true), last)
end

function t.apiCheck_says_nothing_about_caps_when_it_examined_every_line()
    manyLineWorld(3, false)
    local report = facts.apiCheck(nil)
    local last = report[#report]
    assert(not last:find("stopped", 1, true), last)
end

function t.apiCheck_reports_when_there_are_no_cargo_lines()
    facts.clearCache()
    fakeGame.world{
        lines = { [14] = { name = "Bus Line", stops = {}, modes = { "BUS" }, vehicles = {} } },
        player = 1,
    }
    local report = facts.apiCheck(nil)
    assert(report[#report]:find("no cargo lines found", 1, true), report[#report])
end

return t
