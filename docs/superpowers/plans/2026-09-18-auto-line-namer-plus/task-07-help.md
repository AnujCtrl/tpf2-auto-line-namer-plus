# Task 7: help system and the strict GUI fake

**Files:**
- Create: `res/scripts/anujctrl/alnp/help_topics.lua`
- Create: `res/scripts/anujctrl/alnp/gui/help.lua`
- Create: `test/fake_gui.lua`
- Test: `test/test_help.lua`

**Interfaces:**
- Consumes: `log` (C2).
- Produces: contract C11, and `test/fake_gui.lua` which tasks 10–13 use to test their GUI code.

Read spec §10 and §10.1. You cannot run the game, so the fake GUI is the safety net for every
GUI task: it must reject any widget class or method that does not exist.

## Part A — `test/fake_gui.lua` (strict)

Parse `tf2-api/docs/modules/api.gui.md` at load time:

- class headings look like `## <span id="Class_comp_Slider2"></span>Class comp.Slider2`
- the base class line looks like `Base class: [comp.Component](api.gui.html#comp.Component)`
- methods look like `<span id="comp.Slider2:getValue"></span>`  (also `layout.BoxLayout:addItem`,
  `util.Size:new`)

Build `class -> { methods = set, base = className }`. A method is allowed on a class if the class
or any ancestor documents it.

The docs are incomplete. Add an explicit `PROVEN` table for methods that are missing from the
docs but are used in code that runs in the game. Add an entry **only** after confirming it is
absent from the docs, and cite where it is proven, from these two sources:

- upstream's GUI: `git show 748b16c:res/scripts/abajuradam/auto_line_namer_gui.lua`
- Bus Line Tool Plus: `/home/anujp/Documents/personal/tpf2-mods/tpf2-bus-line-tool/res/scripts/bus_line_tool_window.lua`

Every `api.gui.*` call in those two files must work against the fake (test 3 below).

Behaviour:

- `require("fake_gui")` registers a reset hook with `require("fake_api").addReset(...)` that
  installs a fresh `api.gui` with `comp`, `layout`, `util`.
- `api.gui.comp.<Class>.new(...)` / `api.gui.layout.<Class>.new(...)` / `api.gui.util.Size.new(w,h)`
  return a widget object: `{ class = "comp.Button", args = {...}, calls = {}, children = {}, handlers = {} }`
  with a metatable whose `__index` returns a method function for allowed names and **raises**
  `"comp.Button has no method 'setLabel'"` otherwise. An unknown class raises too.
- Every method call is appended to `widget.calls` as `{ name, args }`.
- Methods starting with `on` (`onClick`, `onToggle`, `onChange`, `onIndexChanged`,
  `onValueChanged`, `onClose`, …) store the callback in `widget.handlers[name]`.
- Structure is recorded in `widget.children`: `addItem(child)`, `addTab(label, child)` (both),
  `setLayout(layout)`, `setContent(child)`, `addRow({ ... })`, `setHeader({ ... })`, and the
  constructor's widget arguments (e.g. `Button.new(textView, true)`, `Window.new(title, content)`,
  `ScrollArea.new(content, name)`). `deleteAll()` clears the rows it added.
- Simple state so tests can assert: `setText`/`getText`, `setVisible`/`isVisible`,
  `setSelected`/`isSelected` (and `getCurrentIndex` for ComboBox), `setValue`/`getValue`,
  `setTooltip` (stored as `widget.tooltip`), `setEnabled`/`isEnabled`. When the second argument
  of `setText`/`setSelected`/`setValue` is `true` the matching handler fires (that is what the
  game's "emit signal" flag does).
- `api.gui.util.getById(id)` returns a widget of class `comp.Component` with a BoxLayout already
  set, remembered per id, so `getById("gameInfo"):getLayout():addItem(x)` works and the test can
  find `x`. `invokeLater(fn)` calls `fn` immediately.
- Helpers for tests: `fakeGui.find(root, predicate)` → first widget in the tree (depth-first)
  satisfying it; `fakeGui.findAll(root, predicate)`; `fakeGui.text(widget)` → `getText` value or
  the constructor's first string argument; `fakeGui.click(widget)` fires `handlers.onClick`;
  `fakeGui.allText(root)` → every text in the tree joined by `\n`.

## Part B — `help_topics.lua`

`topics.list` is an array of `{ key, title, text }`; `topics.get(key)` returns the entry or nil.
Plain English strings (the GUI wraps them in `_()`); no `api`, no `_()` here. Text lines are at
most 72 characters, separated by `\n`. Write each text from the spec — it must let someone who
has never seen the mod use that surface without guessing. These keys are fixed; other tasks use
them verbatim:

| key | the text must cover (spec section) |
|---|---|
| `topbar.button` | one paragraph: what the mod does; click to open settings |
| `window.overview` | how lines get named and when (§6: a few lines per tick, settle delay); what locks a line; settings are stored per save; `user_defaults.lua` sets defaults for new saves (§9) |
| `tab.general` | what is on the tab and the usual workflow |
| `tab.advanced` | what is on the tab; safe to leave alone |
| `tab.patterns` | what a pattern is; default vs per-kind; preview is live |
| `tab.lines` | what the table shows; preview then apply workflow |
| `patterns.preset` | what each of the three presets produces (§8); choosing one overwrites all patterns |
| `patterns.default` | used by every kind that has no custom pattern |
| `patterns.kind` | which lines a kind row applies to; inheritance |
| `patterns.autoRename` | off = lines of this kind are never renamed automatically; "Apply checked" still works |
| `patterns.custom` | ticked = this kind uses its own pattern; unticked = inherits the default |
| `patterns.tokens` | syntax only: `{token}`, modifiers `:3` `u` `l` with an example, optional groups `[ ... ]` with an example, upstream aliases, unknown tokens appear as typed (§7.1). The token list itself is appended at runtime from `naming.tokens` |
| `lines.col.apply` | tick = include this line in "Apply checked"; locked and hand-named lines start unticked |
| `lines.col.kind` | the kind the mod detected, which decides the pattern |
| `lines.col.current` | the line's name now |
| `lines.col.proposed` | filled by "Preview all"; blank when the line would be skipped (fewer than the minimum stops) |
| `lines.col.lock` | the three lock states — player (ticked here), edited (you typed a name), prefix — and how to clear each (§6) |
| `lines.col.renameNow` | renames this one line immediately, even if locked or hand-named |
| `lines.previewAll` | reads every line and fills "proposed"; changes nothing; runs in small chunks |
| `lines.applyChecked` | renames exactly the ticked rows to their proposed names; can only be undone by renaming again; the mod then owns those names |
| `reset.section` | restores this section's options to defaults; per-line locks and records are kept |
| `reset.all` | restores every option and pattern; per-line locks and records are kept |
| `advanced.apiCheck` | writes a report to stdout.txt (give the path from spec §11) about the industry lookup and the translated word for "Line"; what to do with the result (add the word to "extra default-name words"; industry tokens fall back if the lookup finds nothing) |

## Part C — `gui/help.lua`

```lua
local help = require "anujctrl/alnp/gui/help"
help.panel()                  -- creates the panel once and returns it; later calls return the same component
help.button(topicKey)         -- small Button labelled "i"
help.buttonFor(title, text)   -- same, for generated help
help.labelled(text, topicKey) -- horizontal Component: TextView(text) followed by help.button(topicKey)
help.show(title, text)        -- fills the panel and makes it visible
help.reset()                  -- forget the panel (guiInit calls this; tests call it after fake.reset())
```

- Button: `api.gui.comp.Button.new(api.gui.comp.TextView.new("i"), true)`; `setTooltip(_(text))`;
  `onClick` → `help.show(title, text)`.
- Panel: a `Component` with a vertical `BoxLayout` holding a title `TextView`, a body `TextView`
  and a "Close" `Button`; hidden (`setVisible(false, false)`) until `help.show`. Close hides it.
- `title` and `text` go through `_()` when displayed.
- Unknown topic key: `log.error("no help topic '<key>'")`, and the button shows
  "No help has been written for this yet." — it must not raise, because that would take the whole
  window down in the game. (A coverage test in Task 13 catches unknown keys on the host.)
- `help.show` before `help.panel()` was ever called must not raise (create the panel lazily).

## Steps

- [ ] **Step 1: Write `test/fake_gui.lua`** (Part A).
- [ ] **Step 2: Write `test/test_help.lua`.** Required cases:
  1. fake: an undocumented method raises with the class and method in the message; an unknown
     class raises; an inherited method (`setTooltip` on a `Button`, documented on `Component`) works;
  2. fake: handlers fire through `fakeGui.click` and through `setSelected(x, true)`; `find` and
     `allText` see widgets nested via `addItem`, `addTab`, `setLayout`, `addRow` and constructors;
  3. fake: every distinct `api.gui.<ns>.<Class>.new` and every `:method(` used in the two proven
     source files is accepted. Extract them with Lua patterns (read upstream through
     `io.popen("git show 748b16c:res/scripts/abajuradam/auto_line_namer_gui.lua")`; read the bus
     tool file directly, and skip that half with a printed note if the file is absent). Because
     the receiver's class is unknown to a regex, assert only that **some** class allows the method;
  4. topics: every key in the table above exists; every entry has non-empty `title` and `text`;
     keys are unique; no text line is longer than 72 characters; `get("nope")` is nil;
  5. help: `button("tab.lines")` has the topic text as its tooltip; clicking it makes the panel
     visible with the topic's title and text; clicking another button replaces the text; "Close"
     hides the panel; `panel()` returns the same object twice;
  6. help: `button("no.such.topic")` does not raise, logs one error (capture `log.sink`), and its
     tooltip is the fallback sentence; `show` before `panel()` does not raise;
  7. help: `labelled("Lock", "lines.col.lock")` contains a TextView with "Lock" and an "i" button.
- [ ] **Step 3: Run** `lua5.4 test/run.lua test_help` → fails with "could not load".
- [ ] **Step 4: Write `help_topics.lua` and `gui/help.lua`.**
- [ ] **Step 5: Run** `lua5.4 test/run.lua test_help` → all pass. `luac -p` every Lua file you wrote.
- [ ] **Step 6: Report** (do not commit): files written, test count, the `PROVEN` entries you
  added and their sources, any contract concern.
