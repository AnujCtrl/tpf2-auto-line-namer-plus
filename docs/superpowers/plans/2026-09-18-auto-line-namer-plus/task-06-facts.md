# Task 6: facts (the only module that reads the game)

**Files:**
- Create: `res/scripts/anujctrl/alnp/facts.lua`
- Create: `test/fake_game.lua`
- Test: `test/test_facts.lua`

**Interfaces:**
- Consumes: `log` (C2); `tbl.industry.radius` from a settings table (build by hand in tests).
- Produces: contract C8 and the facts table C3 (spec §5.1).

You cannot run the game. The API calls below are the ones upstream used successfully, plus
`game.interface.getEntities` for the industry lookup, which is **unverified** — that is why it is
wrapped in `pcall` and why `facts.apiCheck` exists. Do not invent other API calls. The bundled
docs are in `tf2-api/docs/modules/api.engine.md` if you need to confirm a name. Upstream's
original reader is at `git show 748b16c:res/scripts/abajuradam/auto_line_namer_helper.lua`.

## Implementation (write this; adjust only if a test proves it wrong)

```lua
-- Reads a line out of the game into a plain table. The only module that touches api.engine,
-- api.res or game.interface; everything downstream works on the table.
local log = require "anujctrl/alnp/log"

local facts = {}

-- Cargo is read from at most this many vehicles per line; a line's vehicles almost always share it.
local MAX_VEHICLES_SAMPLED = 8

-- TransportMode enum name -> the mode group the rest of the mod uses.
local MODE_GROUPS = {
    BUS = "bus", TRUCK = "truck",
    TRAM = "tram", ELECTRIC_TRAM = "tram",
    TRAIN = "train", ELECTRIC_TRAIN = "train",
    SHIP = "ship", SMALL_SHIP = "ship",
    AIRCRAFT = "air", SMALL_AIRCRAFT = "air",
}

local industryCache = {} -- [stationGroupId] = industry name, or false when none was found

local function component(entity, typeName)
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
        if group and not seenGroup[group] then
            seenGroup[group] = true
            local entry = { stationGroup = group, stop = entityName(group) }
            local groupComp = component(group, "STATION_GROUP")
            local station = groupComp and groupComp.stations and groupComp.stations[1]
            if station then
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
    local checked = 0
    for __, lineId in ipairs(facts.playerLines()) do
        if checked >= 10 then break end
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
    return report
end

return facts
```

## `test/fake_game.lua`

A world builder that installs just the API surface `facts.lua` uses. It must register itself with
the base fake so every test starts clean:

```lua
local fake = require("fake_api")
local fakeGame = {}

-- world{ towns = {[900]="Springfield"},
--        stationGroups = {[11]={name="Springfield Central", station=111, town=900, position={0,0,0}}},
--        industries = {[700]={name="Coal mine", position={120,0,0}}},
--        vehicles = {[501]={capacities={PASSENGERS=40}}},          -- cargo id name -> capacity
--        lines = {[1]={name="Line 1", stops={11,12,11}, modes={"BUS"}, vehicles={501}}},
--        player = 1 }
-- Cargo types are fixed: PASSENGERS=0 "Passengers", COAL=1 "Coal", IRON_ORE=2 "Iron ore", STEEL=3 "Steel".
function fakeGame.world(spec) ... return world end
```

`world` installs: `api.type.ComponentType` (NAME, LINE, STATION_GROUP, TRANSPORT_VEHICLE as
distinct values), `api.type.enum.TransportMode` (BUS=0, TRUCK=1, TRAM=2, ELECTRIC_TRAM=3, TRAIN=4,
ELECTRIC_TRAIN=5, AIRCRAFT=6, SHIP=7, SMALL_AIRCRAFT=8, SMALL_SHIP=9), `api.engine.entityExists`,
`api.engine.getComponent`, `api.engine.util.getPlayer`, `api.engine.system.lineSystem.getLinesForPlayer`
(ids sorted ascending), `api.engine.system.transportVehicleSystem.getLineVehicles`,
`api.engine.system.stationSystem.getTown` (returns -1 when the group has no town),
`api.res.cargoTypeRep.find/get`, `game.interface.getEntity` (returns `{position=...}` for a
station id or group id) and `game.interface.getEntities` (honours `pos`, `radius` and
`type = "SIM_BUILDING"`; returns `{[id] = {name=, position=}}`).

Component shapes: LINE → `{ stops = { {stationGroup=11}, ... }, vehicleInfo = { transportModes = {0,1,0,...} } }`
(a 16-slot array, 1 at `enum+1` for each listed mode); STATION_GROUP → `{ stations = {111} }`;
TRANSPORT_VEHICLE → `{ config = { capacities = {40,0,0,0} } }` (index = cargo id + 1);
NAME → `{ name = "..." }` for lines, groups and towns.

World helpers the tests need: `world.removeLine(id)`, `world.renameLine(id, name)`,
`world.counts.getEntities` (number of calls), `world.breakGetEntities()` (makes it raise).
Later tasks (engine, lines tab) reuse this fake, so keep it general and add
`world.setStops(id, stops)` and `world.setVehicles(id, vehicleIds)` too.

## Steps

- [ ] **Step 1: Write `test/fake_game.lua`** as described.
- [ ] **Step 2: Write `test/test_facts.lua`.** Required cases:
  1. `playerLines` returns the ids; `name` returns `""` for an entity without a NAME component;
  2. `forLine` on a two-town bus line returns exactly the C3 shape (compare the whole table with `eq`);
  3. stops repeat A, B, C, B → `stops` has A, B, C and `towns` is distinct in first-seen order;
  4. a stop whose group has no town → `town == nil`, and it contributes nothing to `towns`;
  5. `ELECTRIC_TRAIN` → `modes.train`; `SMALL_SHIP` → `modes.ship`; `SMALL_AIRCRAFT` → `modes.air`; `ELECTRIC_TRAM` → `modes.tram`;
  6. cargo line: `cargos == {"Coal","Iron ore"}`, `carriesCargo == true`, `carriesPassengers == false`;
     mixed vehicle → both true; a line with no vehicles → `cargos == {}`, both false, `vehicleCount == 0`;
  7. industry: nearest of two industries within radius wins; none within radius → `industry == nil`;
     passenger-only line never calls `getEntities` (`world.counts.getEntities == 0`);
  8. industry lookups are cached per stop (second `forLine` makes no new `getEntities` calls) and
     `clearCache()` makes it look again;
  9. `world.breakGetEntities()` → `forLine` still returns facts, `industry == nil`, no error raised;
  10. `signature` changes when a stop is added, when a vehicle is added, and when the line is
      renamed; it is identical across two calls when nothing changed;
  11. a removed line → `signature` and `forLine` both return nil;
  12. only the first 8 vehicles are sampled (give vehicle 9 a unique cargo; it must not appear);
  13. `apiCheck` returns a string array whose first entry contains `_("Line")`, has one entry per
      cargo stop, and reports "no cargo lines found" when there are none.
- [ ] **Step 3: Run** `lua5.4 test/run.lua test_facts` → fails with "could not load".
- [ ] **Step 4: Write `facts.lua`** from the listing above.
- [ ] **Step 5: Run** `lua5.4 test/run.lua test_facts` → all pass. `luac -p` both Lua files.
- [ ] **Step 6: Report** (do not commit): files written, test count, anything in the listing you
  had to change and why.
