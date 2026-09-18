-- Shared helpers for the test_engine_*.lua files. Not a test file: the runner only discovers
-- test_*.lua.
local fake = require("fake_api")
local fakeGame = require("fake_game")
local log = require("anujctrl/alnp/log")
local settings = require("anujctrl/alnp/settings")

local H = {}

-- Three towns, four stops, one bus and one coal truck. Pass the lines you want; stops 11 and 12
-- are in Springfield and Shelbyville, 13 is in Ogdenville, 14 is a second Springfield stop.
function H.world(lines)
    local world = fakeGame.world({
        towns = { [900] = "Springfield", [901] = "Shelbyville", [902] = "Ogdenville" },
        stationGroups = {
            [11] = { name = "Springfield Central", station = 111, town = 900, position = { 0, 0, 0 } },
            [12] = { name = "Shelbyville East", station = 112, town = 901, position = { 500, 0, 0 } },
            [13] = { name = "Ogdenville Mall", station = 113, town = 902, position = { 900, 0, 0 } },
            [14] = { name = "Springfield North", station = 114, town = 900, position = { 0, 300, 0 } },
        },
        industries = { [700] = { name = "Coal mine", position = { 40, 0, 0 } } },
        vehicles = {
            [501] = { capacities = { PASSENGERS = 40 } },
            [502] = { capacities = { PASSENGERS = 40 } },
            [601] = { capacities = { COAL = 20 } },
        },
        lines = lines,
        player = 1,
    })
    return world
end

-- A default-named bus line between Springfield and Shelbyville.
function H.busLine(name, stops)
    return { name = name, stops = stops or { 11, 12 }, modes = { "BUS" }, vehicles = { 501 } }
end

-- api.cmd for the engine: records what was sent and applies renames to the world, as the game would.
function H.installCmd(world)
    local sent = {}
    api.cmd = {
        make = { setName = function(id, name) return { id = id, name = name } end },
        sendCommand = function(cmd)
            sent[#sent + 1] = cmd
            world.renameLine(cmd.id, cmd.name)
        end,
    }
    return sent
end

-- A saved table whose settings are the defaults with the given dotted paths overridden, e.g.
-- H.saved({ ["scan.settleSeconds"] = 0 }, records).
function H.saved(overrides, records)
    local tbl = settings.defaults()
    for path, value in pairs(overrides or {}) do
        assert(settings.set(tbl, path, value), "bad override " .. path)
    end
    return { settings = tbl, records = records or {} }
end

-- Fresh engine state and captured log lines. Call after building the world.
function H.freshEngine(saved)
    log.reset()
    local lines = {}
    log.sink = function(line) lines[#lines + 1] = line end
    local engine = require("anujctrl/alnp/engine")
    engine.load(saved)
    return engine, lines
end

-- One tick per second from `from` to `to` inclusive.
function H.tickRange(engine, from, to)
    for now = from, to do engine.tick(now) end
end

H.fake = fake
return H
