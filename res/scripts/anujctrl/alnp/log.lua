-- Prefixed logging to the game's stdout.txt. An identical consecutive message is printed once,
-- so an error inside a callback that runs several times a second cannot flood the log.
local log = {}

local PREFIX = "aln_plus: "
local LEVELS = { error = 1, info = 2, debug = 3 }

local level = LEVELS.info
local lastMessage = nil

-- Tests replace this.
log.sink = print

function log.setLevel(name)
    if LEVELS[name] then level = LEVELS[name] end
end

-- Back to the initial state. Modules are cached by require, so tests call this first.
function log.reset()
    level = LEVELS.info
    lastMessage = nil
    log.sink = print
end

local function emit(required, message)
    if level < required then return end
    message = tostring(message)
    if message == lastMessage then return end
    lastMessage = message
    log.sink(PREFIX .. message)
end

function log.error(message) emit(LEVELS.error, message) end
function log.info(message) emit(LEVELS.info, message) end
function log.debug(message) emit(LEVELS.debug, message) end

-- Run fn(...) so that a script error is logged with a traceback instead of reaching the game.
-- Returns fn's results, or nil after an error.
function log.guard(label, fn, ...)
    local args = { n = select("#", ...), ... }
    local results = { xpcall(function() return fn((unpack or table.unpack)(args, 1, args.n)) end, debug.traceback) }
    if results[1] then
        return (unpack or table.unpack)(results, 2)
    end
    log.error(label .. ": " .. tostring(results[2]))
    return nil
end

-- A function that runs fn under log.guard, for widget callbacks.
function log.wrap(label, fn)
    return function(...) return log.guard(label, fn, ...) end
end

return log
