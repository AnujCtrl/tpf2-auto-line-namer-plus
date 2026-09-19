local sync = require("anujctrl/alnp/gui/sync")
local eq = require("fake_api").eq

local t = {}

-- A clock you advance by hand: clock.now is passed to sync.new, clock.advance(dt) moves it.
local function newClock(t0)
    local now = t0 or 0
    return {
        now = function() return now end,
        advance = function(dt) now = now + dt end,
    }
end

function t.nothing_pending_may_always_apply()
    local s = sync.new(newClock().now)
    eq(s:shouldApply("general.enabled", true), true)
end

function t.pending_and_state_matches_clears_and_reports_no_change_needed()
    local clock = newClock()
    local s = sync.new(clock.now)
    s:sent("p", "a")
    eq(s:shouldApply("p", "a"), false)
    -- the pending entry was cleared, so a later, different value applies immediately
    eq(s:shouldApply("p", "z"), true)
end

function t.pending_and_state_differs_before_timeout_does_not_apply()
    local clock = newClock()
    local s = sync.new(clock.now)
    s:sent("p", "a")
    clock.advance(1) -- less than sync.TIMEOUT (2)
    eq(s:shouldApply("p", "b"), false)
end

function t.pending_and_state_differs_after_timeout_applies_and_clears()
    local clock = newClock()
    local s = sync.new(clock.now)
    s:sent("p", "a")
    clock.advance(2) -- timeout has passed
    eq(s:shouldApply("p", "b"), true)
    -- cleared: a further call with nothing pending applies unconditionally
    eq(s:shouldApply("p", "anything"), true)
end

function t.fast_typing_is_not_clobbered_until_the_engine_catches_up()
    local clock = newClock()
    local s = sync.new(clock.now)
    s:sent("p", "a")
    s:sent("p", "ab")
    eq(s:shouldApply("p", "a"), false)
    eq(s:shouldApply("p", "ab"), false)
    eq(s:shouldApply("p", "x"), true)
end

function t.two_paths_are_independent()
    local clock = newClock()
    local s = sync.new(clock.now)
    s:sent("path1", "a")
    eq(s:shouldApply("path2", "anything"), true)
    eq(s:shouldApply("path1", "a"), false)
end

function t.two_sync_instances_are_independent()
    local clock = newClock()
    local s1 = sync.new(clock.now)
    local s2 = sync.new(clock.now)
    s1:sent("p", "a")
    eq(s2:shouldApply("p", "anything"), true)
    eq(s1:shouldApply("p", "a"), false)
end

function t.clock_defaults_to_os_time()
    local s = sync.new()
    eq(s:shouldApply("p", "anything"), true)
end

-- (X10) A clock that steps backwards -- os.time() moving back over a system clock correction --
-- made `now - then` negative, which is smaller than any timeout, so the pending entry would never
-- have expired and that widget would have stopped accepting refreshes for the rest of the
-- session. Time going backwards counts as "time has passed".
function t.a_backward_clock_step_does_not_pin_a_pending_edit_forever()
    local clock = newClock(1000)
    local s = sync.new(clock.now)
    s:sent("p", "a")
    clock.advance(-60)
    eq(s:shouldApply("p", "b"), true)
    eq(s:shouldApply("p", "anything"), true, "the stale pending entry was cleared too")
end

return t
