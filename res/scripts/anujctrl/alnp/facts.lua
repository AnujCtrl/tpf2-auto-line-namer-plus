-- Reads a line out of the game into a plain table. The only module that touches api.engine,
-- api.res or game.interface; everything downstream works on the table.
local log = require "anujctrl/alnp/log"

local facts = {}

-- Cargo is read from at most this many vehicles per line; a line's vehicles almost always share it.
local MAX_VEHICLES_SAMPLED = 8

-- facts.apiCheck runs a full forLine per line, on one tick, with the industry cache cleared each
-- time. On a large network that would visibly freeze the game, so the walk itself is capped too.
local MAX_LINES_EXAMINED = 100
local MAX_CARGO_LINES_REPORTED = 10

-- TransportMode enum name -> the mode group the rest of the mod uses.
local MODE_GROUPS = {
    BUS = "bus", TRUCK = "truck",
    TRAM = "tram", ELECTRIC_TRAM = "tram",
    TRAIN = "train", ELECTRIC_TRAIN = "train",
    SHIP = "ship", SMALL_SHIP = "ship",
    AIRCRAFT = "air", SMALL_AIRCRAFT = "air",
}

local industryCache = {} -- [stationGroupId] = industry name, or false when none was found

-- getComponent "must be given a valid, existing entity": on a dead id it RAISES "Invalid entity",
-- it does not return nil. Entities die between two reads all the time (a line deleted while the
-- Lines tab refreshes its preview), so every read goes through this existence check.
local function component(entity, typeName)
    if entity == nil or not api.engine.entityExists(entity) then return nil end
    return api.engine.getComponent(entity, api.type.ComponentType[typeName])
end

local function entityName(entity)
    local nameComp = component(entity, "NAME")
    if nameComp and type(nameComp.name) == "string" then return nameComp.name end
    return ""
end

function facts.playerLines()
    local ids = {}
    local lines = api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())
    for __, id in ipairs(lines or {}) do ids[#ids + 1] = id end
    return ids
end

function facts.name(lineId)
    return entityName(lineId)
end

local function lineComponent(lineId)
    if not api.engine.entityExists(lineId) then return nil end
    return component(lineId, "LINE")
end

local function vehiclesOf(lineId)
    return api.engine.system.transportVehicleSystem.getLineVehicles(lineId) or {}
end

function facts.signature(lineId)
    local lineComp = lineComponent(lineId)
    if not lineComp then return nil end
    local parts = {}
    for __, stop in ipairs(lineComp.stops) do parts[#parts + 1] = tostring(stop.stationGroup) end
    return table.concat(parts, ",") .. "|" .. #vehiclesOf(lineId) .. "|" .. facts.name(lineId)
end

local function modesOf(lineComp)
    local modes = {}
    local flags = lineComp.vehicleInfo and lineComp.vehicleInfo.transportModes
    if not flags then return modes end
    for enumName, group in pairs(MODE_GROUPS) do
        local index = api.type.enum.TransportMode[enumName]
        if index ~= nil and flags[index + 1] == 1 then modes[group] = true end
    end
    return modes
end

-- Returns cargo display names (distinct, first-seen order), carriesPassengers, carriesCargo, vehicle count.
local function cargosOf(lineId)
    local names, seen, passengers, cargo = {}, {}, false, false
    local vehicles = vehiclesOf(lineId)
    local passengerId = api.res.cargoTypeRep.find("PASSENGERS")
    for i = 1, math.min(#vehicles, MAX_VEHICLES_SAMPLED) do
        local vehicle = component(vehicles[i], "TRANSPORT_VEHICLE")
        local capacities = vehicle and vehicle.config and vehicle.config.capacities
        if capacities then
            for index, capacity in ipairs(capacities) do
                if capacity and capacity > 0 then
                    local cargoId = index - 1
                    if cargoId == passengerId then passengers = true else cargo = true end
                    if not seen[cargoId] then
                        seen[cargoId] = true
                        local rep = api.res.cargoTypeRep.get(cargoId)
                        names[#names + 1] = (rep and rep.name) and _(rep.name) or tostring(cargoId)
                    end
                end
            end
        end
    end
    return names, passengers, cargo, #vehicles
end

-- Nearest industry to a stop, by position. Unverified API, so any failure just means "none".
local function industryNear(group, station, radius)
    if industryCache[group] ~= nil then return industryCache[group] or nil end
    local found = false
    local ok, err = pcall(function()
        local entity = game.interface.getEntity(station) or game.interface.getEntity(group)
        local pos = entity and entity.position
        if not pos then return end
        local nearby = game.interface.getEntities(
            { pos = { pos[1], pos[2] }, radius = radius },
            { type = "SIM_BUILDING", includeData = true })
        local bestDistance
        for __, data in pairs(nearby or {}) do
            if type(data) == "table" and data.position and type(data.name) == "string" and data.name ~= "" then
                local dx, dy = data.position[1] - pos[1], data.position[2] - pos[2]
                local distance = dx * dx + dy * dy
                if not bestDistance or distance < bestDistance then
                    bestDistance, found = distance, data.name
                end
            end
        end
    end)
    if not ok then log.debug("industry lookup failed for stop " .. tostring(group) .. ": " .. tostring(err)) end
    industryCache[group] = found
    return found or nil
end

function facts.clearCache()
    industryCache = {}
end

function facts.forLine(lineId, tbl)
    local lineComp = lineComponent(lineId)
    if not lineComp then return nil end

    local cargos, passengers, cargo, vehicleCount = cargosOf(lineId)
    local radius = tbl and tbl.industry and tbl.industry.radius or 400

    local stops, towns, seenGroup, seenTown = {}, {}, {}, {}
    for __, stop in ipairs(lineComp.stops) do
        local group = stop.stationGroup
        -- A stop whose station group has already been deleted is skipped: reading it would raise,
        -- and a stop with no name is of no use to any pattern.
        if group and not seenGroup[group] and api.engine.entityExists(group) then
            seenGroup[group] = true
            local entry = { stationGroup = group, stop = entityName(group) }
            local groupComp = component(group, "STATION_GROUP")
            local station = groupComp and groupComp.stations and groupComp.stations[1]
            if station and api.engine.entityExists(station) then
                local townId = api.engine.system.stationSystem.getTown(station)
                if townId and api.engine.entityExists(townId) then
                    local townName = entityName(townId)
                    if townName ~= "" then
                        entry.town = townName
                        if not seenTown[townName] then
                            seenTown[townName] = true
                            towns[#towns + 1] = townName
                        end
                    end
                end
                if cargo then entry.industry = industryNear(group, station, radius) end
            end
            stops[#stops + 1] = entry
        end
    end

    return {
        id = lineId,
        name = facts.name(lineId),
        modes = modesOf(lineComp),
        vehicleCount = vehicleCount,
        cargos = cargos,
        carriesPassengers = passengers,
        carriesCargo = cargo,
        towns = towns,
        stops = stops,
    }
end

-- Human-readable report of the three unverified assumptions (spec §13). Logged by the engine
-- when the player presses "Run API check".
function facts.apiCheck(tbl)
    local report = {}
    report[#report + 1] = 'translated default word: _("Line") = "' .. tostring(_("Line")) .. '"'
    local lines = facts.playerLines()
    local checked, examined = 0, 0
    for __, lineId in ipairs(lines) do
        if checked >= MAX_CARGO_LINES_REPORTED or examined >= MAX_LINES_EXAMINED then break end
        examined = examined + 1
        facts.clearCache()
        local f = facts.forLine(lineId, tbl)
        if f and f.carriesCargo then
            checked = checked + 1
            for __, stop in ipairs(f.stops) do
                report[#report + 1] = ('line "%s" stop "%s": industry = %s'):format(f.name, stop.stop, tostring(stop.industry))
            end
        end
    end
    if checked == 0 then report[#report + 1] = "no cargo lines found; build one and run the check again" end
    if checked >= MAX_CARGO_LINES_REPORTED then
        report[#report + 1] = ("stopped after %d cargo lines (of %d lines, %d examined)")
            :format(checked, #lines, examined)
    elseif examined < #lines then
        report[#report + 1] = ("stopped after examining %d of %d lines"):format(examined, #lines)
    end
    return report
end

return facts
