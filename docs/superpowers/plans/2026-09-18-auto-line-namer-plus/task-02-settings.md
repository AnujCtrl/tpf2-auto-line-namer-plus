# Task 2: settings

**Files:**
- Create: `res/scripts/anujctrl/alnp/settings.lua`
- Test: `test/test_settings.lua`

**Interfaces:**
- Consumes: `kinds` (contract C1).
- Produces: contract C4 exactly, plus `settings.validate(row, value) -> true | false, "reason"`.

Read spec §8 and §9 first. This module is pure Lua: no `api`, no `game`, no `_()` calls (labels
and help are plain English strings; the GUI wraps them in `_()`).

## Schema rows

Sections, in this order (`key` / `tab` / label):

| key | tab | label |
|---|---|---|
| `general` | general | General |
| `eligibility` | general | Which lines get renamed |
| `labels` | general | Labels |
| `scope` | advanced | Local, intercity, regional |
| `separators` | advanced | Separators |
| `cargo` | advanced | Cargo names |
| `via` | advanced | Via towns |
| `industry` | advanced | Industry lookup |
| `numbering` | advanced | Numbering |
| `performance` | advanced | Performance |
| `logging` | advanced | Logging |
| `patterns` | patterns | Patterns |

Every section needs a `help` string (2–4 lines) explaining what the section controls as a whole.

Rows (path · type · default · extra). Build the per-kind and per-scope rows with a loop over
`kinds.list` / `kinds.scopes`; everything else is written out.

| section | path | type | default | extra |
|---|---|---|---|---|
| general | `enabled` | bool | true | |
| general | `lock.prefix` | string | `""` | |
| general | `lock.autoLockEdited` | bool | true | |
| general | `reload.names` | string | `"r,reload"` | |
| eligibility | `eligible.defaultNames` | bool | true | |
| eligibility | `eligible.modAssigned` | bool | true | |
| eligibility | `defaults.extraPrefixes` | string | `""` | |
| eligibility | `minStops` | int | 2 | min 1, max 10 |
| labels | `label.kind.<kind>` | string | bus=Bus, tram=Tram, truck=Truck, trainPassenger=Train, trainCargo=Freight, shipPassenger=Ferry, shipCargo=Ship, airPassenger=Air, airCargo=Air Cargo, unknown=Line | |
| labels | `label.scope.<scope>` | string | local=Local, intercity=Intercity, regional=Regional | |
| scope | `scope.localMaxTowns` | int | 1 | min 1, max 5 |
| scope | `scope.regionalMinTowns` | int | 3 | min 2, max 10 |
| separators | `sep.towns` | string | `" – "` (space, en dash, space) | |
| separators | `sep.via` | string | `", "` | |
| separators | `sep.cargo` | string | `", "` | |
| cargo | `cargo.max` | int | 2 | min 1, max 6 |
| cargo | `cargo.mixedLabel` | string | `"Mixed"` | |
| cargo | `cargo.hidePassengers` | bool | true | |
| via | `via.max` | int | 2 | min 0, max 4 |
| industry | `industry.radius` | int | 400 | min 50, max 2000 |
| industry | `industry.fallback` | enum | `"stop"` | values stop, town, empty |
| numbering | `number.scope` | enum | `"sameName"` | values sameName, kind, global |
| numbering | `number.first` | enum | `"blank"` | values blank, one |
| numbering | `number.pad` | int | 0 | min 0, max 4 |
| performance | `scan.linesPerTick` | int | 5 | min 1, max 50 |
| performance | `scan.settleSeconds` | int | 5 | min 0, max 60 |
| performance | `preview.linesPerFrame` | int | 25 | min 1, max 200 |
| logging | `log.level` | enum | `"info"` | values error, info, debug |
| patterns | `patterns.default` | string | `"{type} {towns}[ {n}]"` | `nonEmpty = true` |
| patterns | `patterns.<kind>` | string | cargo kinds (`kinds.cargo`): `"{cargo}: {firstIndustry} → {lastIndustry}[ {n}]"`; all others `""` | |
| patterns | `kinds.<kind>.autoRename` | bool | true | |

Each row needs a `label` (short, sentence case) and a `help` (what it does, plus one example of
the effect; do NOT write the default or range into `help` — `helpText` generates that). Lines in
`help` are at most 72 characters, separated by `\n`. Spec §6, §7 and §9 say what each option means.

Presets (`settings.presets`, spec §8), each with `key`, `label`, `help`, `patterns`:

- `simple`: `default = "{type} {towns}[ {n}]"`, each cargo kind = the cargo pattern above.
- `upstream`: `default = "{type} {cargo}-{towns:3}-{scope}-{n}"`, nothing else.
- `detailed`: `default = "{type} {firstStop} – {lastStop}[ via {via}][ {n}]"`, each cargo kind =
  `"{cargo}: {firstIndustry} → {lastIndustry}[ via {via}][ {n}]"`.

## Behaviour

- `validate(row, value)`: bool → must be boolean. int → number, whole, within min/max. number →
  number within min/max (no row uses it yet; keep it for the contract). string → string of at
  most 200 bytes, and non-empty when `row.nonEmpty`. enum → one of `row.values`.
- `defaults()` returns a fresh table each call (mutating one result must not affect the next).
- `merge(userDefaults, saved)`: for every schema row take `saved`'s value if valid, else
  `userDefaults`'s value if valid, else the default. Both arguments may be nil or non-tables.
  Keys that are not schema paths never appear in the result.
- `set(tbl, path, value)`: unknown path → `false, "unknown setting: <path>"`; invalid →
  `false, <validate reason>`; else writes (creating intermediate tables) and returns `true`.
- `helpText(row)`: `row.help .. "\n\nDefault: " .. D` then, for int/number, `"   Range: <min> to <max>"`,
  for enum `"   Choices: a, b, c"`. `D` is `on`/`off` for bool, `(empty)` for `""`, the value in
  double quotes for other strings, plain for numbers and enums.
- `applyPreset(tbl, key)`: sets `patterns.default` and every `patterns.<kind>` (to `""` when the
  preset omits the kind). Unknown key → returns false and changes nothing.
- `resetSection(tbl, key)`: restores defaults for that section's rows only.

## Steps

- [ ] **Step 1: Write `test/test_settings.lua`** covering every case below. Style:

```lua
local settings = require("anujctrl/alnp/settings")
local kinds = require("anujctrl/alnp/kinds")
local eq = require("fake_api").eq
local t = {}

function t.defaults_follow_the_dotted_paths()
    local d = settings.defaults()
    eq(d.scan.linesPerTick, 5)
    eq(d.label.kind.trainCargo, "Freight")
    eq(d.patterns.bus, "")
    eq(d.patterns.truck, "{cargo}: {firstIndustry} → {lastIndustry}[ {n}]")
    eq(d.kinds.tram.autoRename, true)
end

function t.defaults_are_fresh_each_call()
    local a = settings.defaults()
    a.scan.linesPerTick = 40
    eq(settings.defaults().scan.linesPerTick, 5)
end

return t
```

  Required cases (one test function each, names of your choosing):
  1. the two above;
  2. every row has non-empty `label` and `help`, a known `type`, a `section` that exists in
     `settings.sections`, and a default that passes `validate`;
  3. no two rows share a `path`; every section has non-empty `label`, `help` and a valid `tab`;
  4. no `help` line (row or section) is longer than 72 characters;
  5. there is a `label.kind.*`, `patterns.*` and `kinds.*.autoRename` row for every entry of `kinds.list`;
  6. `validate`: bool rejects `1`; int rejects `2.5`, `0` when min is 1, and `"3"`; enum rejects an
     unlisted value; string rejects a number and a 201-byte string; `nonEmpty` rejects `""`;
  7. `set`: unknown path → `false` plus a reason naming the path; invalid value leaves `tbl`
     unchanged; valid value is readable with `get`; works on an empty `{}` (creates intermediates);
  8. `merge(nil, nil)` equals `defaults()`; saved wins over userDefaults wins over default;
     an invalid saved value falls back to the userDefaults value; unknown keys are dropped;
     non-table arguments (`merge("x", 5)`) are treated as empty;
  9. `patternFor`: kind pattern when non-empty, default pattern when `""`, default for an unknown kind;
  10. `helpText`: bool shows `Default: on`; int shows `Default: 5   Range: 1 to 50`; enum shows
      `Choices: error, info, debug`; empty-string default shows `Default: (empty)`;
  11. `applyPreset("upstream")` sets the default and blanks every kind pattern; unknown key returns
      false and changes nothing;
  12. `resetSection(tbl, "performance")` restores `scan.*` and `preview.*` but leaves a changed
      `cargo.max` alone;
  13. `rowsIn("numbering")` returns the three numbering rows in schema order; `row("nope")` is nil.

- [ ] **Step 2: Run it and watch it fail** — `lua5.4 test/run.lua test_settings` → "could not load".
- [ ] **Step 3: Implement `settings.lua`** to the contract and behaviour above.
- [ ] **Step 4: Run** `lua5.4 test/run.lua test_settings` → all pass. Run `luac -p` on the module.
- [ ] **Step 5: Report** (do not commit): files written, test count, any contract concern.
