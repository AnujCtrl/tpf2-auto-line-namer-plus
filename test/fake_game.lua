-- Fake game world for facts.lua (and, later, engine.lua and gui/lines_tab.lua). Installs just the
-- api.engine / api.res / game.interface surface those modules use, on top of fake_api's empty
-- api/game globals.
--
-- fakeGame.world(spec) builds one line/town/station/industry/vehicle graph and installs it:
--
--   fakeGame.world{
--       towns = {[900]="Springfield"},
--       stationGroups = {[11]={name="Springfield Central", station=111, town=900, position={0,0,0}}},
--       industries = {[700]={name="Coal mine", position={120,0,0}}},
--       vehicles = {[501]={capacities={PASSENGERS=40}}},          -- cargo id name -> capacity
--       lines = {[1]={name="Line 1", stops={11,12,11}, modes={"BUS"}, vehicles={501}}},
--       player = 1,
--   }
--
-- Cargo types are fixed: PASSENGERS=0 "Passengers", COAL=1 "Coal", IRON_ORE=2 "Iron ore",
-- STEEL=3 "Steel".
local fake = require("fake_api")
local fakeGame = {}

-- TransportMode enum name -> value, exactly as the real api.type.enum.TransportMode.
fakeGame.TRANSPORT_MODE = {
    BUS = 0, TRUCK = 1, TRAM = 2, ELECTRIC_TRAM = 3, TRAIN = 4,
    ELECTRIC_TRAIN = 5, AIRCRAFT = 6, SHIP = 7, SMALL_AIRCRAFT = 8, SMALL_SHIP = 9,
}

fakeGame.CARGO_IDS = { PASSENGERS = 0, COAL = 1, IRON_ORE = 2, STEEL = 3 }
fakeGame.CARGO_NAMES = { [0] = "Passengers", [1] = "Coal", [2] = "Iron ore", [3] = "Steel" }

local COMPONENT_TYPE = { NAME = 1, LINE = 2, STATION_GROUP = 3, TRANSPORT_VEHICLE = 4 }

local currentWorld = nil
fake.addReset(function() currentWorld = nil end)

-- The world last built with fakeGame.world(), if any. Convenience for later tasks' tests.
function fakeGame.current()
    return currentWorld
end

function fakeGame.world(spec)
    spec = spec or {}
    local world = {}

    local exists = {}          -- any registered entity id -> true
    local names = {}           -- line id / station group id / town id -> name
    local townOf = {}          -- station id -> town id
    local groupStations = {}   -- station group id -> {station ids}
    local positions = {}       -- station id or group id -> {x, y, z}
    local industries = {}      -- industry id -> {name=, position=}
    local vehicleCaps = {}     -- vehicle id -> capacities array, index = cargo id + 1
    local lineStops = {}       -- line id -> {{stationGroup=id}, ...}
    local lineModes = {}       -- line id -> 16-slot flags array
    local lineVehicles = {}    -- line id -> {vehicle ids}

    world.counts = { getEntities = 0 }
    local getEntitiesBroken = false

    for townId, townName in pairs(spec.towns or {}) do
        exists[townId] = true
        names[townId] = townName
    end

    for groupId, g in pairs(spec.stationGroups or {}) do
        exists[groupId] = true
        names[groupId] = g.name
        groupStations[groupId] = g.station and { g.station } or {}
        if g.station then
            exists[g.station] = true
            if g.town then townOf[g.station] = g.town end
        end
        if g.position then
            positions[groupId] = g.position
            if g.station then positions[g.station] = g.position end
        end
    end

    for industryId, ind in pairs(spec.industries or {}) do
        exists[industryId] = true
        industries[industryId] = { name = ind.name, position = ind.position }
    end

    local function capacitiesFor(caps)
        local out = { 0, 0, 0, 0 }
        for name, amount in pairs(caps or {}) do
            local cargoId = fakeGame.CARGO_IDS[name]
            if cargoId then out[cargoId + 1] = amount end
        end
        return out
    end

    for vehicleId, v in pairs(spec.vehicles or {}) do
        exists[vehicleId] = true
        vehicleCaps[vehicleId] = capacitiesFor(v.capacities)
    end

    local function stopsFor(groupIds)
        local stops = {}
        for __, groupId in ipairs(groupIds or {}) do
            stops[#stops + 1] = { stationGroup = groupId }
        end
        return stops
    end

    local function modesFor(modeNames)
        local flags = {}
        for i = 1, 16 do flags[i] = 0 end
        for __, modeName in ipairs(modeNames or {}) do
            local index = fakeGame.TRANSPORT_MODE[modeName]
            if index ~= nil then flags[index + 1] = 1 end
        end
        return flags
    end

    local function vehiclesFor(vehicleIds)
        local list = {}
        for __, vehicleId in ipairs(vehicleIds or {}) do list[#list + 1] = vehicleId end
        return list
    end

    for lineId, l in pairs(spec.lines or {}) do
        exists[lineId] = true
        names[lineId] = l.name or ""
        lineStops[lineId] = stopsFor(l.stops)
        lineModes[lineId] = modesFor(l.modes)
        lineVehicles[lineId] = vehiclesFor(l.vehicles)
    end

    local player = spec.player or 1

    -- Install the API surface.
    api.type.ComponentType = COMPONENT_TYPE
    api.type.enum = api.type.enum or {}
    api.type.enum.TransportMode = fakeGame.TRANSPORT_MODE

    api.engine.entityExists = function(entity)
        return exists[entity] == true
    end

    api.engine.getComponent = function(entity, componentType)
        if componentType == COMPONENT_TYPE.NAME then
            local name = names[entity]
            if name == nil then return nil end
            return { name = name }
        elseif componentType == COMPONENT_TYPE.LINE then
            if not (exists[entity] and lineStops[entity]) then return nil end
            return { stops = lineStops[entity], vehicleInfo = { transportModes = lineModes[entity] } }
        elseif componentType == COMPONENT_TYPE.STATION_GROUP then
            local stations = groupStations[entity]
            if not stations then return nil end
            return { stations = stations }
        elseif componentType == COMPONENT_TYPE.TRANSPORT_VEHICLE then
            local caps = vehicleCaps[entity]
            if not caps then return nil end
            return { config = { capacities = caps } }
        end
        return nil
    end

    api.engine.util = api.engine.util or {}
    api.engine.util.getPlayer = function() return player end

    api.engine.system = api.engine.system or {}
    api.engine.system.lineSystem = api.engine.system.lineSystem or {}
    api.engine.system.lineSystem.getLinesForPlayer = function(p)
        local ids = {}
        if p ~= player then return ids end
        for lineId in pairs(lineStops) do ids[#ids + 1] = lineId end
        table.sort(ids)
        return ids
    end

    api.engine.system.transportVehicleSystem = api.engine.system.transportVehicleSystem or {}
    api.engine.system.transportVehicleSystem.getLineVehicles = function(lineId)
        return lineVehicles[lineId] or {}
    end

    api.engine.system.stationSystem = api.engine.system.stationSystem or {}
    api.engine.system.stationSystem.getTown = function(stationId)
        return townOf[stationId] or -1
    end

    api.res.cargoTypeRep = {}
    api.res.cargoTypeRep.find = function(name) return fakeGame.CARGO_IDS[name] end
    api.res.cargoTypeRep.get = function(id)
        local name = fakeGame.CARGO_NAMES[id]
        if name == nil then return nil end
        return { name = name }
    end

    game.interface.getEntity = function(id)
        local pos = positions[id]
        if not pos then return nil end
        return { position = pos }
    end

    game.interface.getEntities = function(filter, __)
        world.counts.getEntities = world.counts.getEntities + 1
        if getEntitiesBroken then error("fake game.interface.getEntities is broken") end
        local result = {}
        local px, py = filter.pos[1], filter.pos[2]
        local radius = filter.radius or 0
        for industryId, industry in pairs(industries) do
            local dx, dy = industry.position[1] - px, industry.position[2] - py
            if dx * dx + dy * dy <= radius * radius then
                result[industryId] = { name = industry.name, position = industry.position }
            end
        end
        return result
    end

    -- World helpers for tests, and for later tasks that reuse this fake.
    function world.removeLine(id)
        exists[id] = nil
        names[id] = nil
        lineStops[id] = nil
        lineModes[id] = nil
        lineVehicles[id] = nil
    end

    function world.renameLine(id, name)
        names[id] = name
    end

    function world.setStops(id, stops)
        lineStops[id] = stopsFor(stops)
    end

    function world.setVehicles(id, vehicleIds)
        lineVehicles[id] = vehiclesFor(vehicleIds)
    end

    function world.breakGetEntities()
        getEntitiesBroken = true
    end

    currentWorld = world
    return world
end

return fakeGame
