local log = require("anujctrl/alnp/log")
local eq = require("fake_api").eq
local t = {}

local function capture()
    log.reset()
    local lines = {}
    log.sink = function(s) lines[#lines + 1] = s end
    return lines
end

function t.messages_are_prefixed()
    local lines = capture()
    log.info("hello")
    eq(lines, { "aln_plus: hello" })
end

-- Was "identical_consecutive_message_is_printed_once": suppression used to compare with the last
-- message only, so two messages raised alternately (one per frame, which is what a broken callback
-- does) printed forever. Suppression is now per message, whether or not the repeats are adjacent.
function t.a_repeated_message_is_printed_once_even_when_other_messages_interleave()
    local lines = capture()
    log.error("boom")
    log.error("boom")
    log.error("other")
    log.error("boom")
    eq(lines, { "aln_plus: boom", "aln_plus: other" })
end

function t.alternating_messages_do_not_print_forever()
    local lines = capture()
    for __ = 1, 50 do
        log.error("a")
        log.error("b")
    end
    eq(lines, { "aln_plus: a", "aln_plus: b" })
end

function t.a_flooding_message_reappears_every_hundredth_repeat_with_a_count()
    local lines = capture()
    for __ = 1, 201 do log.error("flood") end
    eq(lines, { "aln_plus: flood", "aln_plus: flood (x100)", "aln_plus: flood (x200)" })
end

function t.reset_clears_the_repeat_counts()
    local lines = capture()
    log.error("boom")
    local again = capture()
    log.error("boom")
    eq(lines, { "aln_plus: boom" })
    eq(again, { "aln_plus: boom" })
end

function t.debug_is_hidden_at_the_default_level_and_shown_after_setLevel()
    local lines = capture()
    log.debug("quiet")
    log.setLevel("debug")
    log.debug("loud")
    eq(lines, { "aln_plus: loud" })
end

function t.error_level_hides_info()
    local lines = capture()
    log.setLevel("error")
    log.info("no")
    log.error("yes")
    eq(lines, { "aln_plus: yes" })
end

function t.unknown_level_name_is_ignored()
    local lines = capture()
    log.setLevel("chatty")
    log.info("still info")
    eq(lines, { "aln_plus: still info" })
end

function t.guard_returns_results_and_passes_arguments()
    capture()
    local a, b = log.guard("sum", function(x, y) return x + y, "ok" end, 2, 3)
    eq({ a, b }, { 5, "ok" })
end

function t.guard_logs_a_traceback_and_returns_nil_on_error()
    local lines = capture()
    local result = log.guard("tick", function() error("kaput") end)
    eq(result, nil)
    assert(#lines == 1, "one log line expected")
    assert(lines[1]:find("aln_plus: tick: ", 1, true), lines[1])
    assert(lines[1]:find("kaput", 1, true), lines[1])
    assert(lines[1]:find("stack traceback", 1, true), lines[1])
end

-- The guard's own error path must be unable to raise: an error thrown while reporting an error
-- escapes the guard, which is exactly what the guard exists to prevent.
function t.guard_survives_an_error_object_whose_tostring_raises()
    local lines = capture()
    local hostile = setmetatable({}, { __tostring = function() error("cannot describe me") end })
    local result = log.guard("tick", function() error(hostile) end)
    eq(result, nil)
    assert(#lines == 1, "one log line expected, got " .. #lines)
    assert(lines[1]:find("aln_plus: tick: ", 1, true), lines[1])
end

function t.guard_survives_a_sink_that_raises()
    log.reset()
    log.sink = function() error("sink is down") end
    local result = log.guard("tick", function() error("kaput") end)
    eq(result, nil)
end

function t.wrap_passes_arguments_and_results_through()
    capture()
    local wrapped = log.wrap("sum", function(x, y) return x + y, "ok" end)
    local a, b = wrapped(2, 3)
    eq({ a, b }, { 5, "ok" })
end

function t.wrap_logs_the_label_and_does_not_raise_on_error()
    local lines = capture()
    local wrapped = log.wrap("tick", function() error("kaput") end)
    local result = wrapped()
    eq(result, nil)
    assert(#lines == 1, "one log line expected")
    assert(lines[1]:find("aln_plus: tick: ", 1, true), lines[1])
    assert(lines[1]:find("kaput", 1, true), lines[1])
end

return t
