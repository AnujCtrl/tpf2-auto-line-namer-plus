# Task 5: tracker

**Files:**
- Create: `res/scripts/anujctrl/alnp/tracker.lua`
- Test: `test/test_tracker.lua`

**Interfaces:**
- Consumes: a settings table shaped like C4 — only `enabled`, `lock.prefix`,
  `lock.autoLockEdited`, `reload.names`, `eligible.defaultNames`, `eligible.modAssigned`,
  `defaults.extraPrefixes`. Build it by hand in tests — do NOT require `settings.lua`.
- Produces: contract C7.

Read spec §6. Pure Lua: no `api`, no `game`, no `_()`.

This module is the safety core of the mod: it decides whether a line's name may be touched.
When in doubt it must answer `"skip"`.

## Rules

`tracker.isDefaultName(name, words)`: true when `name` is nil, empty or only whitespace, or
matches `<word> <digits>` exactly for any word in `words`. Words are literal text — escape
pattern characters (`%p` → `%%%0`). `Line 7` yes; `Line 7a`, `Line`, `line 7`, `Tramline 7` no.

`tracker.defaultWords(tbl, translatedLine)`: `"Line"`, then `translatedLine` when it is a
non-empty string, then each comma-separated entry of `tbl.defaults.extraPrefixes`; entries are
trimmed, empty entries dropped, duplicates removed, order kept.

`tracker.decide(record, name, kindAutoRename, tbl, words)` — first match wins:

| # | Condition | Result |
|---|---|---|
| 1 | `tbl.enabled` is false, or `kindAutoRename` is false | `"skip"` |
| 2 | `record.locked == "player"` | `"skip"` |
| 3 | `tbl.lock.prefix ~= ""` and `name` starts with it (plain comparison, not a pattern) | `"skip"` |
| 4 | `name`, trimmed and lower-cased, equals an entry of `tbl.reload.names` (comma-separated, trimmed, lower-cased) | `"rename"` |
| 5 | `isDefaultName(name, words)` | `"rename"` if `tbl.eligible.defaultNames`, else `"skip"` |
| 6 | `record.lastAssigned ~= nil` and `name == record.lastAssigned` | `"rename"` if `tbl.eligible.modAssigned`, else `"skip"` |
| 7 | anything else (the player wrote this name) | `"autoLock"` if `tbl.lock.autoLockEdited`, else `"skip"` |

`record` may be nil (treat as `newRecord()`). `record.locked == "edited"` does **not**
short-circuit: the name is re-examined every time, so renaming the line to `r` or back to
`Line 7` hands it back to the mod. The engine, not this module, mutates records.

`tracker.lockState(record, name, tbl)`: `"player"` if `record.locked == "player"`; else
`"prefix"` if rule 3 matches; else `"edited"` if `record.locked == "edited"`; else nil.

## Steps

- [ ] **Step 1: Write `test/test_tracker.lua`** — exactly this, then add cases if you find gaps:

```lua
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

return t
```

- [ ] **Step 2: Run it and watch it fail** — `lua5.4 test/run.lua test_tracker`.
- [ ] **Step 3: Implement `tracker.lua`** following the rules table. Keep `decide` a single
  readable chain of `if … return` in rule order, with the rule number in a comment on each.
- [ ] **Step 4: Run** `lua5.4 test/run.lua test_tracker` → all pass. `luac -p` the module.
- [ ] **Step 5: Report** (do not commit): files written, test count, any contract concern.
