local tracker = require("anujctrl/alnp/tracker")
local eq = require("fake_api").eq
local t = {}

local WORDS = { "Line" }

local function tbl(over)
    local s = {
        enabled = true,
        lock = { prefix = "", autoLockEdited = true },
        reload = { names = "r,reload" },
        eligible = { defaultNames = true, modAssigned = true },
        defaults = { extraPrefixes = "" },
    }
    for section, values in pairs(over or {}) do
        if type(values) == "table" then
            for k, v in pairs(values) do s[section][k] = v end
        else
            s[section] = values
        end
    end
    return s
end

function t.new_record_is_empty()
    eq(tracker.newRecord(), {})
end

function t.new_record_is_a_fresh_table_each_call()
    local a = tracker.newRecord()
    local b = tracker.newRecord()
    a.locked = "player"
    eq(b, {})
end

function t.default_names()
    eq(tracker.isDefaultName("Line 7", WORDS), true)
    eq(tracker.isDefaultName("Line 1234", WORDS), true)
    eq(tracker.isDefaultName("", WORDS), true)
    eq(tracker.isDefaultName("   ", WORDS), true)
    eq(tracker.isDefaultName(nil, WORDS), true)
    eq(tracker.isDefaultName("Line 7a", WORDS), false)
    eq(tracker.isDefaultName("Line", WORDS), false)
    eq(tracker.isDefaultName("line 7", WORDS), false)
    eq(tracker.isDefaultName("Tramline 7", WORDS), false)
    eq(tracker.isDefaultName("Linie 3", { "Line", "Linie" }), true)
end

function t.default_words_with_pattern_characters_are_literal()
    eq(tracker.isDefaultName("L.ne 7", { "L.ne" }), true)
    eq(tracker.isDefaultName("Line 7", { "L.ne" }), false)
end

function t.default_words_are_built_from_translation_and_extras()
    eq(tracker.defaultWords(tbl(), nil), { "Line" })
    eq(tracker.defaultWords(tbl(), "Linie"), { "Line", "Linie" })
    eq(tracker.defaultWords(tbl(), "Line"), { "Line" })
    eq(tracker.defaultWords(tbl({ defaults = { extraPrefixes = " Ligne ,, Linie,Ligne" } }), "Linie"),
        { "Line", "Linie", "Ligne" })
end

function t.rule1_disabled_mod_or_kind_skips_everything()
    eq(tracker.decide(nil, "Line 7", true, tbl({ enabled = false }), WORDS), "skip")
    eq(tracker.decide(nil, "Line 7", false, tbl(), WORDS), "skip")
end

function t.rule2_player_lock_beats_a_default_name_and_reload()
    eq(tracker.decide({ locked = "player" }, "Line 7", true, tbl(), WORDS), "skip")
    eq(tracker.decide({ locked = "player" }, "r", true, tbl(), WORDS), "skip")
end

function t.rule3_prefix_lock_is_a_plain_prefix()
    local s = tbl({ lock = { prefix = "[x]" } })
    eq(tracker.decide(nil, "[x] My line", true, s, WORDS), "skip")
    eq(tracker.decide(nil, "xMy line", true, s, WORDS), "autoLock")
    eq(tracker.decide(nil, "Line 7", true, tbl({ lock = { prefix = "" } }), WORDS), "rename")
end

function t.rule4_reload_names_are_trimmed_and_case_insensitive()
    eq(tracker.decide(nil, "r", true, tbl(), WORDS), "rename")
    eq(tracker.decide(nil, " Reload ", true, tbl(), WORDS), "rename")
    eq(tracker.decide({ locked = "edited" }, "R", true, tbl(), WORDS), "rename")
    eq(tracker.decide(nil, "rr", true, tbl(), WORDS), "autoLock")
    eq(tracker.decide(nil, "r", true, tbl({ reload = { names = "" } }), WORDS), "autoLock")
end

function t.rule5_default_name_follows_the_eligibility_switch_and_never_autolocks()
    eq(tracker.decide(nil, "Line 7", true, tbl(), WORDS), "rename")
    eq(tracker.decide(nil, "Line 7", true, tbl({ eligible = { defaultNames = false } }), WORDS), "skip")
    eq(tracker.decide({ locked = "edited" }, "Line 7", true, tbl(), WORDS), "rename")
end

function t.rule6_mod_assigned_name_follows_its_switch()
    local record = { lastAssigned = "Bus A – B" }
    eq(tracker.decide(record, "Bus A – B", true, tbl(), WORDS), "rename")
    eq(tracker.decide(record, "Bus A – B", true, tbl({ eligible = { modAssigned = false } }), WORDS), "skip")
end

function t.rule7_hand_written_name_autolocks_or_skips()
    local record = { lastAssigned = "Bus A – B" }
    eq(tracker.decide(record, "My favourite line", true, tbl(), WORDS), "autoLock")
    eq(tracker.decide(nil, "My favourite line", true, tbl(), WORDS), "autoLock")
    eq(tracker.decide(nil, "My favourite line", true, tbl({ lock = { autoLockEdited = false } }), WORDS), "skip")
end

function t.decide_never_mutates_the_record()
    local record = { lastAssigned = "Bus A – B" }
    tracker.decide(record, "Something else", true, tbl(), WORDS)
    eq(record, { lastAssigned = "Bus A – B" })
end

function t.lock_state()
    eq(tracker.lockState({ locked = "player" }, "x", tbl()), "player")
    eq(tracker.lockState({ locked = "edited" }, "x", tbl()), "edited")
    eq(tracker.lockState({ locked = "edited" }, "[x] y", tbl({ lock = { prefix = "[x]" } })), "prefix")
    eq(tracker.lockState({ locked = "player" }, "[x] y", tbl({ lock = { prefix = "[x]" } })), "player")
    eq(tracker.lockState(nil, "x", tbl()), nil)
    eq(tracker.lockState({}, "x", tbl()), nil)
end

function t.lock_state_treats_a_nil_record_as_new_for_the_prefix_rule()
    eq(tracker.lockState(nil, "[x] y", tbl({ lock = { prefix = "[x]" } })), "prefix")
end

return t
