-- Prefixed logging to the game's stdout.txt. A message is printed the first time and then at most
-- once every REPEAT_EVERY repeats (with an "(xN)" suffix), so an error inside a callback that runs
-- several times a second cannot flood the log. The count is per message, not per last message:
-- two errors raised in alternation would otherwise both look "new" every single time.
local log = {}

local PREFIX = "aln_plus: "
local LEVELS = { error = 1, info = 2, debug = 3 }
local REPEAT_EVERY = 100
local MAX_TRACKED = 200 -- bound the table; a long session must not grow it without limit

local level = LEVELS.info
local counts = {}
local tracked = 0

-- Tests replace this.
log.sink = print

function log.setLevel(name)
    if LEVELS[name] then level = LEVELS[name] end
end

-- Back to the initial state. Modules are cached by require, so tests call this first.
function log.reset()
    level = LEVELS.info
    counts = {}
    tracked = 0
    log.sink = print
end

local function emit(required, message)
    if level < required then return end
    message = tostring(message)
    local seen = counts[message]
    if not seen then
        if tracked >= MAX_TRACKED then
            counts = {}
            tracked = 0
        end
        counts[message] = 1
        tracked = tracked + 1
        log.sink(PREFIX .. message)
        return
    end
    seen = seen + 1
    counts[message] = seen
    if seen % REPEAT_EVERY == 0 then
        log.sink(PREFIX .. message .. " (x" .. seen .. ")")
    end
end

function log.error(message) emit(LEVELS.error, message) end
function log.info(message) emit(LEVELS.info, message) end
function log.debug(message) emit(LEVELS.debug, message) end

-- Run fn(...) so that a script error is logged with a traceback instead of reaching the game.
-- Returns fn's results, or nil after an error.
-- Hands xpcall's results on: everything after the status on success, nil after reporting on error.
-- Results travel as varargs on purpose, never through unpack (see log.guard).
local function finish(label, ok, ...)
    if ok then return ... end
    local err = ...
    -- Reporting the error must not raise: tostring() can call a hostile __tostring, the label may
    -- not be a string, and log.sink is the game's own print. Anything raised here would escape the
    -- guard, which is the one thing the guard exists to prevent.
    pcall(function()
        local described, text = pcall(tostring, err)
        if not described then text = "<error object that cannot be converted to text>" end
        log.error(tostring(label) .. ": " .. text)
    end)
    return nil
end

-- NO unpack ANYWHERE IN HERE. Transport Fever 2's own res/scripts/init.lua replaces table.unpack
-- with a one-argument version that drops (i, j), and the game has no global unpack; the earlier
-- `table.unpack(results, 2)` therefore returned xpcall's `true` instead of fn's result, in the game
-- only. Arguments are passed positionally (six is more than any caller uses) and results come back
-- as varargs, so nothing here depends on what unpack does.
function log.guard(label, fn, a, b, c, d, e, f)
    return finish(label, xpcall(function() return fn(a, b, c, d, e, f) end, debug.traceback))
end

-- A function that runs fn under log.guard, for widget callbacks.
function log.wrap(label, fn)
    return function(...) return log.guard(label, fn, ...) end
end

return log
