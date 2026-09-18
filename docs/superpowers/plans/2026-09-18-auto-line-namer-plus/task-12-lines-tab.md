# Task 12: lines tab

**Files:**
- Create: `res/scripts/anujctrl/alnp/gui/lines_tab.lua`
- Test: `test/test_lines_tab.lua`

**Interfaces:**
- Consumes: `facts` (C8), `classify` (C5), `propose` (C9), `tracker.lockState`, `tracker.decide`
  and `tracker.defaultWords(state.settings, _("Line"))` (C7), `kinds`
  (C1), `help` + topics `lines.col.apply`, `lines.col.kind`, `lines.col.current`,
  `lines.col.proposed`, `lines.col.lock`, `lines.col.renameNow`, `lines.previewAll`,
  `lines.applyChecked` (C11), `test/fake_gui.lua` and `test/fake_game.lua` (APIs in
  `.superpowers/sdd/2026-09-18-auto-line-namer-plus/task-7-report.md` and `task-6-report.md`).
- Produces (C12): `linesTab.build(state, send) -> component`, `linesTab.refresh(state)`,
  `linesTab.update()`, `linesTab.reset()`.

Read spec §6, §10, §10.1. You cannot run the game: use only what the strict fake accepts.
This is a GUI file, so it may not call `api.engine` itself — it reads the game only through
`facts`, and it never renames anything: it sends events and the engine does the work.

## Layout

- Button row: "Preview all" + `help.button("lines.previewAll")`; "Apply checked" +
  `help.button("lines.applyChecked")`; a status `TextView`.
- A `Table` with six columns inside a `ScrollArea`. Header cells are
  `help.labelled(text, topic)` components:
  `Apply` (`lines.col.apply`), `Kind` (`lines.col.kind`), `Current name` (`lines.col.current`),
  `Proposed name` (`lines.col.proposed`), `Lock` (`lines.col.lock`), `Rename now` (`lines.col.renameNow`).
- One row per player line: apply `CheckBox`; `TextView` kind (`_(kinds.label[kind])`);
  `TextView` current name; `TextView` proposed name; lock `CheckBox` whose label shows the lock
  state (`""`, `_("locked")`, `_("locked: you edited the name")`, `_("locked: prefix")`);
  "Rename now" `Button`.

## Behaviour

- `build` creates the widgets and an **empty** table. It must not read any line: building the
  window has to be instant on a huge save.
- "Preview all" starts a scan: it takes `facts.playerLines()`, clears the table, and sets the
  status to `_("Reading lines… 0 / N")`.
- `update()` (called every GUI frame) does at most `state.settings.preview.linesPerFrame` lines
  of a running scan and returns immediately when no scan is running. For each line:
  `f = facts.forLine(id, state.settings)`; skip it if nil; `kind = classify.kind(f)`;
  `name, n, key = propose.name(f, state.records[id], state.settings, taken)` where `taken`
  starts as `propose.takenByKey(state.records, nil)` **minus the line's own number** and is
  updated with each proposal as the scan proceeds, so two previewed lines never get the same
  number; `lock = tracker.lockState(state.records[id], f.name, state.settings)`.
  - The apply box starts ticked only when `name` is non-nil, differs from `f.name`, `lock` is
    nil, and the name is mod-owned or default (i.e. `tracker.decide(...)` would return
    `"rename"`; pass `true` for `kindAutoRename` so the preview does not depend on that switch
    — the help text says "Apply checked" still works for kinds with auto-rename off).
    Locked and hand-named rows start unticked.
  - A nil proposal shows `_("(left alone)")` and the apply box is disabled.
  - When the scan ends the status shows `_("N lines, M would change")`.
- "Apply checked" sends one event:
  `send("apply", { renames = { { line = id, name = name, n = n, key = key }, … } })` for rows that
  are ticked and have a proposal, then unticks them. With nothing ticked it sends nothing and the
  status says so.
- The lock box sends `send("lock", { line = id, locked = true|false })`. Unticking a row whose
  state is `edited` or `prefix` cannot clear it from here (those clear by renaming the line to
  `r`, or by removing the prefix): re-tick the box without emitting, and put that explanation in
  the status line.
- "Rename now" sends `send("renameNow", { line = id })`.
- `refresh(state)` stores the new state; if a preview has been shown, it updates each row's
  current name and lock label from the new state **without** reading facts again (names come
  from `facts.name(id)`, which is one cheap component read per row; do this at most once per
  second, not on every call). It never restarts a scan by itself.
- `reset()` forgets everything.

## Tests (`test/test_lines_tab.lua`)

Build a world with `fake_game` (several bus lines, one cargo line, one hand-named line, one
one-stop line), `state = { settings = settings.defaults(), records = {…} }`, and a recording `send`.

1. `build` reads nothing: wrap `facts.forLine`/`facts.playerLines` to count → 0 calls; the table
   is empty; every header cell and both buttons have their info button;
2. with `preview.linesPerFrame = 2` and 5 lines: after "Preview all" and one `update()`, 2 rows;
   after three, 5 rows and the final status; further `update()` calls read nothing;
3. a default-named line row is ticked and shows its proposed name; the hand-named line is
   unticked and its lock label is empty (no record yet) — or `edited` when the record says so;
   a player-locked line is unticked; the one-stop line shows "(left alone)" with a disabled box;
4. two default-named lines between the same towns get different proposed numbers in one preview;
5. "Apply checked" sends exactly the ticked rows, each with `line`, `name`, `n`, `key`; a second
   click sends nothing;
6. ticking a lock box sends `lock` true; unticking a player lock sends `lock` false; unticking
   an `edited` row sends nothing, re-ticks, and explains in the status;
7. "Rename now" sends `renameNow` with that row's line id;
8. a line that vanishes mid-scan is skipped without an error;
9. `refresh` after a preview updates a changed current name and never calls `facts.forLine`.

## Steps

- [ ] **Step 1:** write the test file. **Step 2:** run `lua5.4 test/run.lua test_lines_tab` → fails to load.
- [ ] **Step 3:** write `gui/lines_tab.lua`. **Step 4:** run → all pass; `luac -p` the module.
- [ ] **Step 5:** report (do not commit): files written, test count, any contract concern.
