-- Decides when a GUI refresh may overwrite a widget the player might still be typing into.
-- The GUI thread receives the engine's state many times a second; without this, a refresh that
-- arrived before the engine caught up to the player's latest keystroke would clobber it: the
-- field shows "ab", the engine has only acknowledged "a", and the refresh would write "a" back.
local sync = {}

sync.TIMEOUT = 2

-- clock: function returning the current time in seconds; defaults to os.time.
function sync.new(clock)
    clock = clock or os.time
    local pending = {} -- [path] = { value = <sent value>, at = <clock() when sent> }
    local self = {}

    -- The widget at `path` just sent `value` to the engine.
    function self:sent(path, value)
        pending[path] = { value = value, at = clock() }
    end

    -- May a refresh overwrite the widget at `path` with `stateValue`?
    function self:shouldApply(path, stateValue)
        local entry = pending[path]
        if not entry then return true end
        if stateValue == entry.value then
            pending[path] = nil
            return false
        end
        -- A negative elapsed time means the clock stepped backwards (a system clock correction
        -- under os.time). That is not "no time has passed": read literally it is smaller than any
        -- timeout, so this entry would never expire and the widget would refuse every refresh for
        -- the rest of the session. Treat it as "time has passed" (hardening X10).
        local elapsed = clock() - entry.at
        if elapsed >= 0 and elapsed < sync.TIMEOUT then
            return false
        end
        pending[path] = nil
        return true
    end

    return self
end

return sync
