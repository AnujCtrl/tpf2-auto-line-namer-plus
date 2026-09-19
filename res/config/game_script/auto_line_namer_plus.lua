-- Auto Line Namer Plus: wiring only. The engine thread runs update/handleEvent/save; the GUI
-- thread runs guiInit/guiUpdate. load() runs in both: once on the engine thread when the game
-- loads, and repeatedly on the GUI thread with whatever the engine's save() last returned.
local log = require "anujctrl/alnp/log"
local engine = require "anujctrl/alnp/engine"
local window = require "anujctrl/alnp/gui/window"

local SOURCE = "alnp"
local engineLoaded = false
local reportedOddLoad = false
-- The last table save() handed the game. Returning nil from save() makes the game store nothing,
-- so every setting and lock would be lost without the player ever seeing an error.
local lastSaved = {}

-- The game binds this callback as load(state, reset), and the first argument is not always a state
-- table: a real session passed `true` before guiInit. Urban Games' own scripts treat nil, an empty
-- table and reset as "nothing to adopt" (res/scripts/guidesystem.lua), and so does this.
local function usableState(saved, reset)
    if reset then return nil end
    if type(saved) ~= "table" then
        if saved ~= nil and not reportedOddLoad then
            reportedOddLoad = true
            log.info("load() was given a " .. type(saved) .. " (" .. tostring(saved) .. "), not a state; ignored")
        end
        return nil
    end
    if next(saved) == nil then return nil end
    return saved
end

local function send(name, param)
    api.cmd.sendCommand(api.cmd.make.sendScriptEvent("auto_line_namer_plus.lua", SOURCE, name, param or {}))
end

-- The whole body of load(), including the inspection of the value the game passed: tostring() on
-- a foreign value and log.sink can both raise, and outside a guard that would crash the game.
local function loadBody(saved, reset)
    local state = usableState(saved, reset)
    if not state then return end
    -- Both calls are safe on either thread: the engine adopts only the first real state
    -- (until then it runs on defaults), and the window only stores the table until a
    -- window exists (which is only on the GUI thread).
    if not engineLoaded then
        engineLoaded = true
        log.guard("engine load", engine.load, state)
    end
    log.guard("setState", window.setState, state)
end

function data()
    return {
        load = function(saved, reset)
            log.guard("load", loadBody, saved, reset)
        end,
        save = function()
            local saved = log.guard("save", engine.save)
            if type(saved) == "table" then lastSaved = saved end
            return lastSaved
        end,
        update = function()
            log.guard("update", engine.tick, os.time())
        end,
        handleEvent = function(__, id, name, param)
            if id ~= SOURCE then return end
            log.guard("event " .. tostring(name), engine.handleEvent, name, param)
        end,
        guiInit = function()
            log.guard("guiInit", window.init, send)
        end,
        guiUpdate = function()
            log.guard("guiUpdate", window.update)
        end,
    }
end
