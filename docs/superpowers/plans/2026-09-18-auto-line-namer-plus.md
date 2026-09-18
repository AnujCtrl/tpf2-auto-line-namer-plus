# Auto Line Namer Plus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Auto Line Namer fork into "Auto Line Namer Plus": safe, change-driven line
renaming with station/industry tokens, per-kind patterns, schema-driven settings, and an info
button on every UI surface.

**Architecture:** One module (`facts.lua`) reads the game; everything else is plain Lua on plain
tables, tested on the host with `lua5.4`. The engine thread owns settings and per-line records and
is the only place a rename is sent; the GUI thread only sends script events. Settings, their form
and their help text all derive from one schema table.

**Tech Stack:** Lua (game runs LuaJIT-era 5.1 semantics; host tests run `lua5.4`), Transport
Fever 2 scripting API, bash + rsync for install. No third-party libraries.

**Spec:** `docs/superpowers/specs/2026-09-18-auto-line-namer-plus-design.md` — read it with your
task file. Where the two disagree, the spec wins; report the disagreement.

**Task files:** `docs/superpowers/plans/2026-09-18-auto-line-namer-plus/task-NN-*.md`. Each
implementer reads this overview, the spec, and their own task file only.

## Global Constraints

- Work on branch `plus-rebuild`. Never push. Remote `upstream` has its push URL disabled; leave it.
- Modules live in `res/scripts/anujctrl/alnp/` and are required as `require "anujctrl/alnp/<name>"`
  (GUI modules: `require "anujctrl/alnp/gui/<name>"`).
- The game script is `res/config/game_script/auto_line_namer_plus.lua`. Script-event source id is
  the string `"alnp"`.
- Only `facts.lua` may call `api.engine`, `api.res` or `game.interface`. Only `engine.lua` may call
  `api.cmd`. Only files under `gui/` may call `api.gui`. A lint test enforces all three.
- Code must run on Lua 5.1 semantics: no `goto`, no integer division `//`, no bitwise operators,
  no `table.unpack` (use `unpack or table.unpack`), no `utf8` library, no `string.pack`.
- `_` is the game's translation function. Never use `_` as a variable, loop variable or parameter;
  spell throwaways `__`. A lint test enforces this.
- All UI text is `_("English text")`. English needs no `strings.lua` entry. No task except Task 13
  edits `strings.lua`.
- Help text has explicit `\n` line breaks at about 70 characters.
- Log through `anujctrl/alnp/log`; never call `print` directly elsewhere.
- Indent Lua with 4 spaces (upstream's style). Max line length 150.
- **Parallel-safety:** touch only the files your task lists under **Files**. Run only your own
  tests (`lua5.4 test/run.lua <your_test_name>`); other tasks' files may be half-written. Do not
  run `git add`/`git commit` — the controller commits after review.
- If a test in your task file contradicts the spec, stop and report; do not "fix" the test.

## File map

| File | Task |
|---|---|
| `mod.lua`, `LICENSE`, `.luacheckrc`, `.gitignore`, `install.sh` | 1 |
| `test/run.lua`, `test/fake_api.lua` (base), `test/test_log.lua`, `test/test_kinds.lua` | 1 |
| `res/scripts/anujctrl/alnp/kinds.lua`, `log.lua` | 1 |
| removed: `res/scripts/abajuradam/`, `res/config/game_script/auto_line_namer.lua`, `workshop_fileid.txt`, `readme.bbcode`, `image_00.*`, `modio_preview.jpg`, `workshop_preview.jpg`, `scripts/`, `.github/` | 1 |
| `settings.lua`, `test/test_settings.lua` | 2 |
| `naming.lua`, `test/test_naming.lua` | 3 |
| `classify.lua`, `test/test_classify.lua` | 4 |
| `tracker.lua`, `test/test_tracker.lua` | 5 |
| `facts.lua`, `test/fake_game.lua`, `test/test_facts.lua` | 6 |
| `gui/help.lua`, `help_topics.lua`, `test/fake_gui.lua`, `test/test_help.lua` | 7 |
| `propose.lua`, `test/test_propose.lua` | 8 |
| `engine.lua`, `test/test_engine.lua` | 9 |
| `gui/schema_form.lua`, `test/test_schema_form.lua` | 10 |
| `gui/patterns_tab.lua`, `test/test_patterns_tab.lua` | 11 |
| `gui/lines_tab.lua`, `test/test_lines_tab.lua` | 12 |
| `gui/window.lua`, game script, `user_defaults.lua`, `strings.lua`, `test/test_lint.lua`, `test/test_help_coverage.lua`, `test/test_smoke.lua`, `README.md` | 13 |

(Paths without a directory are under `res/scripts/anujctrl/alnp/`.)

## Execution waves

```
Wave 0:  Task 1                      (alone)
Wave 1:  Tasks 2 3 4 5 6 7           (parallel — no code dependencies on each other)
Wave 2:  Task 8                      (alone, small; needs 2 3 4)
Wave 3:  Tasks 9 10 11 12            (parallel; need wave 1 and Task 8)
Wave 4:  Task 13                     (alone; integrates everything)
```

Within a wave every task owns disjoint files. Each task is reviewed (spec compliance, then code
quality) before the controller commits it.

## Contracts

These names and shapes are fixed. A task may add private helpers but must not change a contract;
if a contract is wrong, stop and report.

### C1. `kinds` (Task 1)

```lua
local kinds = require "anujctrl/alnp/kinds"
kinds.list   -- {"bus","tram","truck","trainPassenger","trainCargo","shipPassenger","shipCargo","airPassenger","airCargo","unknown"}
kinds.cargo  -- { truck=true, trainCargo=true, shipCargo=true, airCargo=true }
kinds.scopes -- {"local","intercity","regional"}
kinds.label  -- English display name per kind, e.g. kinds.label.trainCargo == "Cargo train"
```

### C2. `log` (Task 1)

```lua
local log = require "anujctrl/alnp/log"
log.setLevel("error"|"info"|"debug")     -- default "info"
log.error(msg) log.info(msg) log.debug(msg)  -- prints "aln_plus: <msg>"; identical consecutive message suppressed
log.guard(label, fn, ...)                -- xpcall(fn, traceback, ...); on error logs "<label>: <traceback>" and returns nil
log.sink = print                         -- tests replace this
```

### C3. Facts table (produced by Task 6, consumed by 3 4 8 9 11 12)

Exactly the shape in spec §5.1. `modes` is a set over `bus`, `truck`, `tram`, `train`, `ship`,
`air` (electric and small/large variants already folded). `towns` is distinct town names in order
of first appearance. `stops[i].town` and `stops[i].industry` may be `nil`.

### C4. `settings` (Task 2)

```lua
local settings = require "anujctrl/alnp/settings"
settings.schema      -- array of rows: { path, type, default, section, label, help, min?, max?, values? }
settings.sections    -- array: { key, tab = "general"|"advanced"|"patterns", label, help }
settings.presets     -- array: { key, label, help, patterns = { default = "...", [kind] = "..." } }
settings.defaults()              -- fresh nested table built from schema defaults
settings.merge(userDefaults, saved)  -- nested table: defaults <- valid userDefaults <- valid saved
settings.get(tbl, path)          -- value at dotted path, or nil
settings.set(tbl, path, value)   -- returns true, or false, "reason"; validates against the row; mutates tbl
settings.row(path)               -- schema row or nil
settings.rowsIn(sectionKey)      -- array of rows, schema order
settings.helpText(row)           -- row.help .. "\n\n" .. generated "Default: ..." (+ " Range: a to b" / " Choices: x, y")
settings.patternFor(tbl, kind)   -- tbl.patterns[kind] if non-empty string, else tbl.patterns.default
settings.applyPreset(tbl, key)   -- sets patterns.default and every patterns.<kind> ("" when the preset omits it); true/false
settings.resetSection(tbl, sectionKey)  -- restores schema defaults for that section's rows
```

Nested shape follows the dotted path: `"scan.linesPerTick"` ↔ `tbl.scan.linesPerTick`,
`"label.kind.bus"` ↔ `tbl.label.kind.bus`. `patterns.<kind>` is a string; `""` means "inherit the
default pattern". Enum values are strings.

### C5. `classify` (Task 4)

```lua
local classify = require "anujctrl/alnp/classify"
classify.kind(facts)            -- one of kinds.list
classify.scope(facts, tbl)      -- one of kinds.scopes, using tbl.scope.localMaxTowns / regionalMinTowns
```

### C6. `naming` (Task 3)

```lua
local naming = require "anujctrl/alnp/naming"
naming.render(pattern, facts, ctx)  -- ctx = { settings = tbl, kind = "bus", scope = "local", n = 2 or nil } -> string
naming.usesNumber(pattern)          -- true if the pattern contains {n} or {lineNumber} (with or without modifiers)
naming.pickNumber(current, taken)   -- current if non-nil and not taken[current]; else lowest integer >= 1 not in taken
naming.sampleFacts(kind)            -- plausible facts table for previews
naming.tokens                       -- array: { token = "{type}", example = "Bus", help = "..." } in cheat-sheet order
```

`{n}` renders `""` when `ctx.n` is nil, or when `ctx.n == 1` and `tbl.number.first == "blank"`;
otherwise `ctx.n` zero-padded to `tbl.number.pad`.

### C7. `tracker` (Task 5)

```lua
local tracker = require "anujctrl/alnp/tracker"
tracker.newRecord()   -- { lastAssigned = nil, locked = nil, number = nil, numberKey = nil }
tracker.isDefaultName(name, words)          -- words: array like {"Line","Linie"}; matches "^<word> %d+$"
tracker.defaultWords(tbl, translatedLine)   -- {"Line", translatedLine?, each of tbl.defaults.extraPrefixes}, de-duplicated, trimmed
tracker.decide(record, name, kindAutoRename, tbl, words)  -- "skip" | "rename" | "autoLock"  (spec §6 table, first match wins)
tracker.lockState(record, name, tbl)        -- nil | "player" | "edited" | "prefix"
```

`record.locked` is `nil`, `"player"` or `"edited"`. `record` may be nil in `decide`/`lockState`.

### C8. `facts` (Task 6)

```lua
local facts = require "anujctrl/alnp/facts"
facts.playerLines()            -- array of line entity ids
facts.name(lineId)             -- current name, "" if none
facts.signature(lineId)        -- string, or nil if the line no longer exists
facts.forLine(lineId, tbl)     -- facts table (C3), or nil if the line no longer exists
facts.clearCache()             -- forget cached industry lookups
facts.apiCheck(tbl)            -- array of strings: _("Line") first, then the industry lookup result per cargo stop
```

### C9. `propose` (Task 8)

```lua
local propose = require "anujctrl/alnp/propose"
propose.name(facts, record, tbl, takenByKey)
-- takenByKey: { [numberKey] = { [n] = true, ... } } for OTHER lines
-- returns nil                      when the line has < tbl.minStops stops or the result is blank
-- returns name, n, numberKey       otherwise (n, numberKey are nil when the pattern has no {n})
propose.takenByKey(records, exceptLineId)   -- builds takenByKey from a records map
```

### C10. `engine` (Task 9)

```lua
local engine = require "anujctrl/alnp/engine"
engine.load(saved)            -- saved = { settings = tbl, records = { [lineId] = record } } or nil
engine.save()                 -- same shape
engine.tick(now)              -- now = os.time(); does scan.linesPerTick lines of work
engine.handleEvent(name, param)
```

Events (source id `"alnp"`): `set {path, value}` · `lock {line, locked}` (locked: true → "player",
false → nil) · `apply {renames = {{line, name}, ...}}` · `renameNow {line}` · `preset {key}` ·
`resetSection {section}` · `resetAll {}` · `apiCheck {}`.

### C11. `gui/help` and `help_topics` (Task 7)

```lua
local help = require "anujctrl/alnp/gui/help"
help.button(topicKey)     -- api.gui.comp.Button labelled "i"; tooltip = topic text; click shows topic in the panel
help.buttonFor(title, text)  -- same, for generated help (settings rows)
help.panel()              -- the shared panel component (create once; window.lua docks it at the bottom)
help.labelled(text, topicKey)  -- horizontal component: TextView(text) + help.button(topicKey)

local topics = require "anujctrl/alnp/help_topics"
topics.list               -- array of { key, title, text }
topics.get(key)           -- entry or nil
```

Topic keys are fixed (Task 7 lists them); tasks 10–13 use them verbatim.

### C12. GUI tab builders (Tasks 10–12)

```lua
schemaForm.build(tabKey, state, send)   -- tabKey "general"|"advanced" -> api.gui component
patternsTab.build(state, send)          -- -> component
linesTab.build(state, send)             -- -> component;  linesTab.update() called from guiUpdate
-- every builder module also has  <module>.refresh(state)  called when load() delivers new state
-- state = { settings = tbl, records = {...} }   (GUI thread's copy, replaced on every load)
-- send(name, param) sends the C10 event
```

### C13. Test harness (Task 1)

`lua5.4 test/run.lua` runs every `test/test_*.lua`; `lua5.4 test/run.lua test_naming` runs one.
A test file returns a table of functions; each runs after `fake.reset()`. Plain `assert`, plus
`local eq = require("fake_api").eq` — `eq(actual, expected, label)` deep-compares and prints both
on failure.

## Tasks

1. [Scaffold, identity, harness, kinds, log](2026-09-18-auto-line-namer-plus/task-01-scaffold.md)
2. [settings](2026-09-18-auto-line-namer-plus/task-02-settings.md)
3. [naming](2026-09-18-auto-line-namer-plus/task-03-naming.md)
4. [classify](2026-09-18-auto-line-namer-plus/task-04-classify.md)
5. [tracker](2026-09-18-auto-line-namer-plus/task-05-tracker.md)
6. [facts](2026-09-18-auto-line-namer-plus/task-06-facts.md)
7. [help and the strict GUI fake](2026-09-18-auto-line-namer-plus/task-07-help.md)
8. [propose](2026-09-18-auto-line-namer-plus/task-08-propose.md)
9. [engine](2026-09-18-auto-line-namer-plus/task-09-engine.md)
10. [schema form](2026-09-18-auto-line-namer-plus/task-10-schema-form.md)
11. [patterns tab](2026-09-18-auto-line-namer-plus/task-11-patterns-tab.md)
12. [lines tab](2026-09-18-auto-line-namer-plus/task-12-lines-tab.md)
13. [window, game script, coverage tests, README](2026-09-18-auto-line-namer-plus/task-13-integration.md)
