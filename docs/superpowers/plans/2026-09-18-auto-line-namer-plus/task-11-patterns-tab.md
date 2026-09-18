# Task 11: patterns tab

**Files:**
- Create: `res/scripts/anujctrl/alnp/gui/patterns_tab.lua`
- Test: `test/test_patterns_tab.lua`

**Interfaces:**
- Consumes: `settings` (C4: `presets`, `patternFor`, `get`), `naming` (C6: `render`,
  `sampleFacts`, `tokens`), `classify` (C5), `kinds` (C1), `help` + topics `patterns.preset`,
  `patterns.default`, `patterns.kind`, `patterns.autoRename`, `patterns.custom`,
  `patterns.tokens` (C11), `sync` (Task 8), `test/fake_gui.lua` (API in
  `.superpowers/sdd/2026-09-18-auto-line-namer-plus/task-7-report.md`).
- Produces (C12): `patternsTab.build(state, send) -> component`, `patternsTab.refresh(state)`,
  `patternsTab.reset()`.

Read spec §7, §8, §10, §10.1. You cannot run the game: use only what the strict fake accepts.

## Layout (top to bottom, inside a `ScrollArea`)

1. **Preset row:** `help.labelled(_("Preset"), "patterns.preset")`, a `ComboBox` listing
   `settings.presets` labels, and an "Apply preset" `Button`. Applying overwrites every pattern,
   so it takes two clicks: the first click changes the button text to
   "Click again to overwrite all patterns"; a second click sends `send("preset", { key = … })`
   and restores the text; choosing a different preset in between also restores it.
2. **Default row:** `help.labelled(_("Default pattern"), "patterns.default")`, a `TextInputField`
   for `patterns.default`, and a preview `TextView`.
3. **One row per `kinds.list` entry:** `TextView(_(kinds.label[kind]))` + `help.button("patterns.kind")`;
   a `CheckBox(_("Rename automatically"))` for `kinds.<kind>.autoRename` + `help.button("patterns.autoRename")`;
   a `CheckBox(_("Custom pattern"))` + `help.button("patterns.custom")`; a `TextInputField`;
   a preview `TextView`.
   - "Custom pattern" is ticked when `patterns.<kind> ~= ""`. Ticking it sends
     `set patterns.<kind>` = the current default pattern; unticking sends `""`.
   - The text field is enabled only while custom is ticked (`setEnabled`); when unticked it shows
     the inherited default pattern.
4. **Token reference:** `help.labelled(_("Tokens"), …)` is not enough here because the list is
   generated: use `help.buttonFor(topic.title, topic.text .. "\n\n" .. tokenLines)` with
   `topic = topics.get("patterns.tokens")` and one `"{token}  example  — help"` line per
   `naming.tokens` entry. Below it, show the same token lines as a visible `TextView` cheat-sheet.

## Preview

The preview of a row is `naming.render(pattern, naming.sampleFacts(kind), ctx)` with
`ctx = { settings = state.settings, kind = kind, scope = classify.scope(facts, state.settings), n = 2 }`
(`n = 2` so the number is visible). The default row previews as kind `bus`. It must call
`naming.render` — never re-implement token substitution (that was upstream's bug #8). The
preview updates immediately from the text the player is typing, not from the engine's echo.
A blank result shows `_("(blank: the line would be left alone)")`.

Every editor calls `sync:sent(path, value)` before `send("set", { path = …, value = … })`.
`refresh(state)` follows the same rule as the schema form: apply only where
`sync:shouldApply` says so and the widget differs, with the emit flag `false`, then recompute
every preview (labels and separators may have changed). `reset()` forgets widgets and makes a
new sync instance.

## Tests (`test/test_patterns_tab.lua`)

1. there is a row for the default and for every kind; every row has its info buttons; the
   preset row and token reference have theirs (assert on tooltip text from `help_topics`);
2. the default preview equals `naming.render` of the default pattern for the bus sample with
   `n = 2`; the `trainCargo` preview uses the cargo pattern and shows an industry name;
3. typing a new default pattern sends `set patterns.default` and updates the default preview
   and every inheriting kind's preview immediately, without a refresh;
4. typing `{bogus}` shows `{bogus}` in the preview (unknown tokens are visible);
5. ticking "Custom pattern" on `bus` sends the default pattern text for `patterns.bus` and
   enables the field; unticking sends `""`, disables it and shows the default pattern again;
6. toggling "Rename automatically" sends `set kinds.tram.autoRename` with a boolean;
7. preset: one click sends nothing and changes the button text; the second click sends
   `preset` with the chosen key; changing the combo box between clicks resets the confirmation;
8. a pattern that renders blank shows the "(blank …)" text;
9. `refresh` with a state where `label.kind.bus = "Coach"` changes the bus preview and sends nothing;
10. the token reference tooltip contains every `naming.tokens` token and the syntax topic text.

## Steps

- [ ] **Step 1:** write the test file. **Step 2:** run `lua5.4 test/run.lua test_patterns_tab` → fails to load.
- [ ] **Step 3:** write `gui/patterns_tab.lua`. **Step 4:** run → all pass; `luac -p` the module.
- [ ] **Step 5:** report (do not commit): files written, test count, any contract concern.
