-- Hardening tests for the real game script file (res/config/game_script/auto_line_namer_plus.lua).
-- The game calls these callbacks directly: anything that raises here crashes the game, and a save()
-- that returns nil makes the game store nothing, so the player silently loses settings and locks.
-- test_smoke.lua covers the happy path; this file only covers the failure paths.
local fakeGame = require("fake_game")
require("fake_gui")
local engine = require("anujctrl/alnp/engine")
local log = require("anujctrl/alnp/log")

local t = {}

local GAME_SCRIPT = "res/config/game_script/auto_line_namer_plus.lua"

local function scriptWithWorld()
    fakeGame.world({ towns = {}, stationGroups = {}, vehicles = {}, lines = {}, player = 1 })
    engine.load(nil)
    require("anujctrl/alnp/gui/window").reset()
    dofile(GAME_SCRIPT)
    return data()
end

-- Y2: the whole body of load() is guarded, including the "is this even a state table?" check,
-- which logs a value the game chose.
function t.load_does_not_raise_when_logging_an_odd_state_raises()
    log.reset()
    log.sink = function(message)
        if message:find("was given a", 1, true) then error("sink exploded") end
    end
    local scriptData = scriptWithWorld()
    scriptData.load(true) -- exactly what the real game passed before guiInit
end

function t.load_does_not_raise_when_the_engine_raises()
    log.reset()
    log.sink = function() end
    local scriptData = scriptWithWorld()
    local realLoad = engine.load
    engine.load = function() error("engine.load exploded") end
    local ok, err = pcall(scriptData.load, { version = 1 })
    engine.load = realLoad
    assert(ok, "load() must not raise: " .. tostring(err))
end

-- Y2: save() must never return nil, or the game saves nothing at all.
function t.save_returns_the_last_good_state_when_the_engine_raises()
    log.reset()
    log.sink = function() end
    local scriptData = scriptWithWorld()
    local good = scriptData.save()
    assert(type(good) == "table", "save() should return the engine state")
    local realSave = engine.save
    engine.save = function() error("engine.save exploded") end
    local fallback = scriptData.save()
    engine.save = realSave
    assert(fallback == good, "save() should fall back to the last table it returned")
end

function t.save_returns_a_table_even_when_it_never_succeeded()
    log.reset()
    log.sink = function() end
    local scriptData = scriptWithWorld()
    local realSave = engine.save
    engine.save = function() error("engine.save exploded") end
    local saved = scriptData.save()
    engine.save = realSave
    assert(type(saved) == "table", "save() must return a table, got " .. type(saved))
end

return t
