-- Auto Line Namer Plus: wiring only. The engine thread runs update/handleEvent/save; the GUI
-- thread runs guiInit/guiUpdate. load() runs in both: once on the engine thread when the game
-- loads, and repeatedly on the GUI thread with whatever the engine's save() last returned.
local log = require "anujctrl/alnp/log"
local engine = require "anujctrl/alnp/engine"
local window = require "anujctrl/alnp/gui/window"

local SOURCE = "alnp"
local engineLoaded = false

local function send(name, param)
    api.cmd.sendCommand(api.cmd.make.sendScriptEvent("auto_line_namer_plus.lua", SOURCE, name, param or {}))
end

function data()
    return {
        load = function(saved)
            -- Both calls are safe on either thread: the engine keeps only its first load, and the
            -- window only stores the table until a window exists (which is only on the GUI thread).
            if not engineLoaded then
                engineLoaded = true
                log.guard("load", engine.load, saved)
            end
            log.guard("setState", window.setState, saved)
        end,
        save = function()
            return log.guard("save", engine.save)
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
