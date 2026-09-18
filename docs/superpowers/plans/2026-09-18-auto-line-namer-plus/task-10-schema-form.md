# Task 10: schema form (the General and Advanced tabs)

**Files:**
- Create: `res/scripts/anujctrl/alnp/gui/schema_form.lua`
- Test: `test/test_schema_form.lua`

**Interfaces:**
- Consumes: `settings` (C4), `help` + topic keys `reset.section`, `reset.all`,
  `advanced.apiCheck` (C11), `sync` (Task 8), `log` (C2), `test/fake_gui.lua` (API in
  `.superpowers/sdd/2026-09-18-auto-line-namer-plus/task-7-report.md`).
- Produces (C12): `schemaForm.build(tabKey, state, send) -> component`, `schemaForm.refresh(state)`,
  `schemaForm.reset()`.

Read spec §9, §10, §10.1. The point of this module: a settings row never needs hand-written GUI
code. One loop over `settings.sections` / `settings.rowsIn` builds both tabs.

You cannot run the game. Use only widget classes and methods the strict fake accepts; it rejects
anything that is not in the API docs (`tf2-api/docs/modules/api.gui.md`) or proven in the game.

## Layout

`build(tabKey, state, send)` returns a `ScrollArea` whose content is a vertical `BoxLayout`.
For each section with `section.tab == tabKey`, in order:

1. a heading row: `TextView(_(section.label))`, `help.buttonFor(_(section.label), section.help)`,
   and a "Reset section" `Button` followed by `help.button("reset.section")`.
   Click → `send("resetSection", { section = section.key })`.
2. one row per `settings.rowsIn(section.key)`: `TextView(_(row.label))`, the editor, and
   `help.buttonFor(row.label, settings.helpText(row))`.

At the bottom of the `general` tab: a "Reset everything" button + `help.button("reset.all")` →
`send("resetAll", {})`. At the bottom of the `advanced` tab: a "Run API check" button +
`help.button("advanced.apiCheck")` → `send("apiCheck", {})`.

## Editors

| row.type | widget | reads | sends |
|---|---|---|---|
| bool | `CheckBox` | `setSelected(value, false)` | `onToggle(v)` → `send("set", {path, value = v})` |
| string | `TextInputField` | `setText(value, false)` | `onChange(text)` → `send("set", {path, value = text})` |
| enum | `ComboBox`, one `addItem(_(v))` per `row.values` | `setSelected(index0, false)` | `onIndexChanged(i)` → value `row.values[i + 1]` |
| int, number | `Slider` (horizontal) + a `TextView` showing the value | `setValue(value, false)` | `onValueChanged(v)` → `math.floor(v + 0.5)` for int |

The slider is the one widget nothing in the two proven sources uses. Build it inside `pcall`;
if construction or any setup call raises, log once with `log.info` and fall back to a
`TextInputField` that sends `tonumber(text)` when it is a number (Bus Line Tool Plus does the
same for its colour chooser). Put the two variants in two small local functions.

Every editor calls `sync:sent(path, value)` right before `send`, using one module-level
`sync.new()` instance.

## Refresh

`build` remembers each editor by path. `refresh(state)` walks them and, for each path where
`sync:shouldApply(path, settings.get(state.settings, path))` is true and the widget shows a
different value, writes the state value with the "do not emit" flag (`false`) so a refresh never
echoes back to the engine. `reset()` forgets remembered editors and makes a new sync instance
(`guiInit` calls it; tests call it after `fake.reset()`).

## Tests (`test/test_schema_form.lua`)

Use `settings.defaults()` as `state.settings` and a `send` that records calls.
1. `build("general", …)` contains a label for every row of every general-tab section and none
   from advanced-tab sections, and vice versa; the `patterns` section appears in neither;
2. every row has exactly one info button whose tooltip contains the row's help text and the
   generated `Default:` line; every section heading has one whose tooltip is the section help;
3. toggling a bool sends `set` with the path and a boolean; typing in a string field sends the
   text; choosing enum index 2 of `log.level` sends `"debug"`; moving an int slider to 7.6 sends `8`;
4. editors show the state's values at build time (e.g. `scan.linesPerTick` shows 5);
5. "Reset section" sends `resetSection` with that section's key; "Reset everything" exists only
   on general; "Run API check" exists only on advanced; each has its info button;
6. `refresh` with a changed state updates the widget and sends **nothing**;
7. `refresh` does not overwrite a field the player just typed in (type `ab`, refresh with the
   old value → the field still shows `ab`); after the engine echoes `ab` and then a preset
   changes the value, `refresh` shows the new value;
8. slider fallback: make `api.gui.comp.Slider.new` raise → the row is a text field, typing `12`
   sends the number 12, typing `abc` sends nothing, and exactly one info log line was written.

## Steps

- [ ] **Step 1:** write the test file. **Step 2:** run `lua5.4 test/run.lua test_schema_form` → fails to load.
- [ ] **Step 3:** write `gui/schema_form.lua`. **Step 4:** run → all pass; `luac -p` the module.
- [ ] **Step 5:** report (do not commit): files written, test count, any contract concern.
