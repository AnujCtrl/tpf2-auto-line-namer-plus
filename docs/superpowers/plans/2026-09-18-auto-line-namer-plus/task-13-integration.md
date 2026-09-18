# Task 13: window, game script, coverage tests, README

**Files:**
- Create: `res/scripts/anujctrl/alnp/gui/window.lua`
- Create: `res/config/game_script/auto_line_namer_plus.lua`
- Create: `res/scripts/anujctrl/alnp/user_defaults.lua`
- Rewrite: `strings.lua`, `README.md`
- Test: `test/test_window.lua`, `test/test_smoke.lua`, `test/test_lint.lua`, `test/test_help_coverage.lua`

**Interfaces:**
- Consumes: everything (C1–C12). Fake APIs: `task-6-report.md` and `task-7-report.md` in
  `.superpowers/sdd/2026-09-18-auto-line-namer-plus/`.
- Produces: the loadable mod.

Read the whole spec. This task wires finished modules together; it adds no naming logic.

## Part A — `gui/window.lua`

```lua
window.init(send)      -- guiInit: help.reset(), reset the three tab modules, build the window (hidden), add the top-bar button
window.setState(state) -- called from load() on every delivery; stores state and its version
window.update()        -- guiUpdate: if the window is visible and state.version changed since the last refresh,
                       -- refresh the three tabs; always call linesTab.update()
```

- Top-bar button: upstream's proven idiom —
  `api.gui.util.getById("gameInfo"):getLayout():addItem(button)` inside `invokeLater`, with a
  `VerticalLine` component on each side; label `"[ALN+]"`; tooltip = topic `topbar.button`
  text; click toggles the window's visibility. Guard against a nil `gameInfo` or nil layout
  with a logged error, as upstream did.
- Window: `api.gui.comp.Window.new(_("Auto Line Namer Plus"), content)`, `addHideOnCloseHandler()`,
  start hidden. `content` is a vertical layout: a header row with
  `help.labelled(_("How this works"), "window.overview")`; a `TabWidget` with four tabs whose
  labels are `help.labelled(_("General"), "tab.general")`, `…("Advanced"), "tab.advanced")`,
  `…("Patterns"), "tab.patterns")`, `…("Lines"), "tab.lines")` (if the strict fake shows that
  `addTab` needs a plain `TextView` label, use a `TextView` and put the tab's `help.button` as
  the first item inside the tab's content instead); then `help.panel()` docked at the bottom.
- The tab contents come from `schemaForm.build("general", …)`, `schemaForm.build("advanced", …)`,
  `patternsTab.build(…)`, `linesTab.build(…)`.
- If `setState` has not delivered a state yet when `init` runs, build with
  `{ settings = settings.defaults(), records = {}, version = -1 }`; the first real state refreshes it.
- `update()` must be cheap when the window is hidden: no refresh, only `linesTab.update()`
  (which returns immediately when no scan runs).

## Part B — the game script (write this)

```lua
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
```

`api.cmd` appears here and in `engine.lua` only; the lint test allows exactly these two files.

## Part C — `user_defaults.lua`

Returns `{}` with a comment block explaining: values here override the built-in defaults for
**new** saves; paths mirror the settings (give three commented-out examples:
`patterns = { default = "{type} {towns:3}[ {n}]" }`, `scan = { linesPerTick = 10 }`,
`defaults = { extraPrefixes = "Linie" }`); invalid values are ignored; `install.sh` overwrites the
installed copy, so edit the copy in the repo.

## Part D — `strings.lua`

Translations only, keyed by the English text. Keep upstream's languages (`de`, `ru`, `tr`) with
entries for the mod name `"Auto Line Namer Plus"` (same in every language) and nothing else;
English has no table. Read upstream's description translations with
`git show 748b16c:strings.lua` — they describe the old mod, so do not reuse them.

## Part E — tests

`test/test_window.lua`: `init` adds exactly one button to `gameInfo`; clicking it shows the
window and clicking again hides it; the window has four tabs; the overview and each tab have
their info buttons; `update()` with the window hidden refreshes nothing (wrap the tab modules'
`refresh` to count); with the window visible, a state with a new `version` refreshes each tab
once and the same version again refreshes nothing; a nil `gameInfo` logs an error and does not raise.

`test/test_smoke.lua`: load the game script with `dofile`, call `data()`, and run a whole
session against `fake_game` + `fake_gui` with an `api.cmd` fake whose `sendCommand` renames the
line for `setName` commands and, for `sendScriptEvent` commands, calls the script's own
`handleEvent("file", id, name, param)`: `load(nil)`; `guiInit()`; tick until a default-named
line is renamed; feed `save()` into `load()` and call `guiUpdate()`; click the top-bar button;
toggle a setting in the General tab and assert the engine's saved settings changed; press
"Preview all", pump `guiUpdate()`, press "Apply checked" and assert the line was renamed.
Also: an error thrown inside `engine.tick` (make `facts.playerLines` raise) is logged once and
`update()` does not raise.

`test/test_lint.lua` over every `.lua` file under `res/` plus `mod.lua` and `strings.lua`:
1. `_` is never a loop variable, local or parameter (port the three patterns from
   `/home/anujp/Documents/personal/tpf2-mods/tpf2-bus-line-tool/test/test_lint.lua`);
2. every file parses: `luac -p`, and also `luac5.1 -p` when that binary exists;
3. layering: `api.engine`, `api.res`, `game.interface` appear only in `facts.lua`; `api.cmd`
   only in `engine.lua` and the game script; `api.gui` only under `gui/`; `print(` only in `log.lua`
   (ignore comment lines);
4. Lua 5.1 only: no `goto `, no `//` outside strings and comments, no `table.unpack(` without
   `unpack or`, no `utf8.`, no `string.pack`, no `<const>`/`<close>`;
5. no line longer than 150 characters; no tab indentation.

`test/test_help_coverage.lua` (spec §12):
1. every schema row and section has non-empty `label` and `help`;
2. every topic has non-empty `title` and `text`;
3. static scan of `res/scripts/anujctrl/alnp/gui/*.lua`: every string literal passed to
   `help.button(`, `help.labelled(…, ` or `topics.get(` is a key in `help_topics`; every topic
   key is used at least once;
4. function-level rule: in each `gui/*.lua` file except `help.lua` and `sync.lua`, every function
   body that creates a `Button.new`, a `Table.new`, a `TabWidget.new`/`addTab`, or a `CheckBox.new`
   also calls one of `help.button`, `help.buttonFor`, `help.labelled`. Split function bodies by
   lines matching `^%s*local function ` / `^%s*function ` / `= function%(`; report offenders as
   `file:line`. If a legitimate builder fails this, fix the builder (move the info button into
   it), not the test;
5. dynamic: build the real window against `fake_gui` with default settings, and assert the number
   of `"i"` buttons in the tree is at least `#settings.schema` rows on the two form tabs
   + number of sections + the fixed topics. Print nothing.

## Part F — `README.md`

Rewrite for the fork: what it does; credit and licence (fork of erkanercan's Auto Line Namer,
MIT, both copyright lines); install (`./install.sh`, restart the game, enable "Auto Line Namer
Plus", disable the Workshop original to avoid double renames); tests (`lua5.4 test/run.lua`);
design (link the spec); **first-launch checklist**: run "Run API check" on the Advanced tab and
read `~/.local/share/Steam/userdata/204184616/1066780/local/crash_dump/stdout.txt` for
`aln_plus: api check:` lines — (a) if industries show `nil` for cargo stops, industry tokens fall
back to stop names; (b) if the translated word is not "Line", add it to "Extra default-name
words"; (c) if the mod list shows no author for the fork, change `BASED_ON` to `CO_CREATOR` in
`mod.lua`; then the in-game checklist from spec §12; known limitations (ASCII-only upper/lower
case; help text does not re-wrap; settings are per save — point to `user_defaults.lua`).

## Steps

- [ ] **Step 1:** write the four test files. **Step 2:** run them → fail to load / fail.
- [ ] **Step 3:** write `gui/window.lua`, the game script, `user_defaults.lua`, `strings.lua`.
- [ ] **Step 4:** run the **whole** suite: `lua5.4 test/run.lua` → everything passes, output pristine.
  If lint or coverage flags another task's file, fix that file minimally and list the fix in your report.
- [ ] **Step 5:** write `README.md`. Run `TPF2_LOCAL_MODS=$(mktemp -d) ./install.sh` and list the
  installed files in your report (no `test/`, `docs/`, `tf2-api/`).
- [ ] **Step 6:** report (do not commit).
