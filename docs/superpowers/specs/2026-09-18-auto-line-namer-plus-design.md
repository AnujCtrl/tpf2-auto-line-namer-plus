# Auto Line Namer Plus — design

Date: 2026-09-18
Status: awaiting review
Upstream: https://github.com/erkanercan/TPF2-AutoLineNamer (v0.2.0, MIT, commit `748b16c`)

## 1. Goal

A fork of Auto Line Namer for Transport Fever 2 that names every line from its stops, towns,
industries and cargo; never overwrites a name the player wrote; costs a fixed amount of work per
frame however large the save is; and exposes every tunable as a setting.

The fork fixes the upstream problems in §2, adds the features in §3, and rebuilds the internals so
that everything except one module is plain Lua tested on the host.

## 2. Upstream problems this fixes

| # | Problem | Upstream location |
|---|---|---|
| 1 | Renames every line not prefixed `Cst`, including hand-named ones | `auto_line_namer_helper.lua:28` |
| 2 | Auto-update defaults to on at 1 minute: every line gets a rename command each minute, even when nothing changed | `state.lua:30`, `auto_line_namer.lua:35` |
| 3 | `{lineNumber}` is the entity id, not a sequence number | `auto_line_namer_helper.lua:326` |
| 4 | A line with no resolvable town is renamed to an empty string | `auto_line_namer_helper.lua:302`, `auto_line_namer.lua:25` |
| 5 | Default-name detection is English-only (`^Line %d+$`) | `auto_line_namer_helper.lua:25` |
| 6 | The only edit trigger is one GUI widget id; engine reads run on the GUI thread | `auto_line_namer.lua:55` |
| 7 | Defaults written out three times; about 25 copy-paste getters and setters | `state.lua` |
| 8 | The settings preview re-implements the naming logic, so the two can drift | `auto_line_namer_gui.lua:12` |

## 3. Features added

1. Station and industry tokens (§7).
2. A naming pattern per line kind (§8).
3. Safe rename controls: automatic lock on hand-edited names, per-line lock, preview before a bulk
   rename (§6, §10).
4. Every tunable is a setting, driven by one schema (§9).

Out of scope: sharing code with Bus Line Tool Plus, ring detection, migrating upstream's saved
settings (a different mod id has no shared save state), auto-colouring lines, export and import of
settings as text.

## 4. Repo and identity

- Location: `~/Documents/personal/tpf2-mods/tpf2-auto-line-namer/`, cloned with upstream's full
  history. Remote `upstream` is fetch-only (push URL disabled). Work happens on branch
  `plus-rebuild`.
- Mod name "Auto Line Namer Plus". Installed folder `auto_line_namer_plus_1`.
- `mod.lua` authors: `AnujCtrl` as `CREATOR`, `erkanercan` as `BASED_ON`, with the description
  crediting him as the original author. The probe in §13 confirms the game accepts that role.
- `LICENSE` keeps "Copyright (c) 2025 Erkan Ercan" and adds "Copyright (c) 2026 AnujCtrl".
- `workshop_fileid.txt` (upstream's Workshop id `3360333659`) is deleted so the in-game publisher
  can never target upstream's item. `readme.bbcode`, the preview images and `.github/` are
  upstream's publishing assets: the images and bbcode are removed, to be replaced only if the
  fork is published.
- The game script is `res/config/game_script/auto_line_namer_plus.lua` and modules live under
  `res/scripts/anujctrl/alnp/`, so the fork can be enabled next to the Workshop original without
  module-name clashes.
- Publishing (GitHub fork under `AnujCtrl`, Steam Workshop) is not part of this work and needs an
  explicit go-ahead.

## 5. Architecture

Only `facts.lua` reads the game. Everything downstream works on plain tables.

| Module | Responsibility | Game API |
|---|---|---|
| `facts.lua` | `facts.forLine(lineId)` → plain table (§5.1). `facts.signature(lineId)` → cheap change signature. `facts.playerLines()` → ids | yes — the only one |
| `classify.lua` | facts → `kind` and `scope` (§5.2) | no |
| `naming.lua` | `render(pattern, facts, settings)` → string. `number(base, takenNames, settings)` | no |
| `tracker.lua` | per-line record and `decide(record, name, signature, settings)` → action (§6) | no |
| `settings.lua` | schema, defaults, `merge`, validated `set(path, value)` (§9) | no |
| `engine.lua` | engine-thread loop: a few lines per tick → facts → tracker → naming → `setName` | wiring |
| `gui/window.lua` | window shell, top-bar button, tabs | GUI only |
| `gui/schema_form.lua` | builds a form from settings schema rows | GUI only |
| `gui/patterns_tab.lua` | default and per-kind patterns with live preview | GUI only |
| `gui/lines_tab.lua` | line table, locks, preview and apply | GUI + `facts` reads |
| `log.lua` | prefixed, de-duplicated logging | `print` |
| game script | wires `update`, `handleEvent`, `guiInit`, `guiUpdate`, `guiHandleEvent`, `save`, `load` | wiring |

Threads. The engine thread owns the settings and the per-line records, and is the only place a
rename is sent. The GUI thread receives both through the game's `save()` → `load()` channel and
sends changes back as script events (`set`, `lock`, `apply`, `resetSection`). The GUI never
mutates settings locally.

### 5.1 Facts table

```lua
{
  id = 48213,
  name = "Line 7",
  modes = { bus = true },            -- from lineComp.vehicleInfo.transportModes
  vehicleCount = 3,
  cargos = { "Passengers" },         -- distinct, in first-seen order
  carriesPassengers = true,
  carriesCargo = false,
  stops = {                          -- distinct stops, order of first appearance
    { stationGroup = 101, stop = "Springfield Central", town = "Springfield", industry = nil },
    { stationGroup = 205, stop = "Shelbyville East",    town = "Shelbyville", industry = nil },
  },
}
```

"Last" everywhere means the last entry of `stops`, so a line listed A, B, C, B ends at C.

### 5.2 Kinds and scopes

Kinds: `bus`, `tram`, `truck`, `trainPassenger`, `trainCargo`, `shipPassenger`, `shipCargo`,
`airPassenger`, `airCargo`, `unknown`. A road line is `truck` when it carries cargo. Electric and
non-electric variants map to the same kind, as do small and large ships and aircraft.

Scopes: `local` (distinct towns ≤ `scope.localMaxTowns`), `regional` (distinct towns ≥
`scope.regionalMinTowns`), otherwise `intercity`.

## 6. When a line is renamed

Each engine `update` tick checks `scan.linesPerTick` lines, round-robin. For each line it computes
`facts.signature` (stop station-group ids, vehicle count, current name). If the signature equals
the stored one, nothing else happens. If it changed, a settle timer starts; once the signature has
been stable for `scan.settleSeconds`, the engine reads full facts and calls `tracker.decide`.

`tracker.decide` returns one of:

| Condition (first match wins) | Action |
|---|---|
| mod disabled, or the line's kind has auto-rename off | `skip` |
| record is locked by the player (Lines tab) | `skip` |
| name starts with non-empty `lock.prefix` | `skip` |
| name is one of `reload.names` (default `r`, `reload`) | `rename` |
| name matches a default-name pattern, and `eligible.defaultNames` | `rename` |
| name equals `record.lastAssigned`, and `eligible.modAssigned` | `rename` |
| name equals `record.lastAssigned`, `eligible.modAssigned` off | `skip` |
| anything else: the player wrote it | `autoLock` if `lock.autoLockEdited`, else `skip` |

`autoLock` sets `record.locked = "edited"`. The Lines tab shows it and can clear it.

Default-name patterns: `^Line %d+$`, the same with the game's translated word for "Line", and
every entry of `defaults.extraPrefixes` (a comma-separated setting, e.g. `Linie,Ligne`).

Hard rules in `engine.lua`, regardless of settings:

1. Never send `setName` when the new name equals the current name.
2. Never assign an empty or whitespace-only name.
3. Skip lines with fewer than `minStops` distinct stops (default 2).
4. A line id that no longer exists is removed from the records.

Saved per line: `lastAssigned`, `locked` and `number` (the `{n}` value it holds, §7.2).
Signatures and settle timers are runtime-only. The settle delay is measured in real seconds
(`os.time`), so it behaves the same whether the game is paused or running fast.

## 7. Patterns and tokens

| Token | Value | Upstream alias |
|---|---|---|
| `{type}` | label of the line's kind | `{transportType}` |
| `{scope}` | label of the line's scope | `{lineType}` |
| `{cargo}` | cargo names joined by `sep.cargo`; more than `cargo.max` names collapse to `cargo.mixedLabel`; `Passengers` omitted on passenger-only lines when `cargo.hidePassengers` | `{cargoTypes}` |
| `{towns}` | `{firstTown}` `sep.towns` `{lastTown}`, or the one town if both ends share it | `{townNames}` |
| `{firstTown}` `{lastTown}` | end towns | — |
| `{via}` | up to `via.max` intermediate towns that are neither end town, joined by `sep.via` | — |
| `{firstStop}` `{lastStop}` | station names at each end | — |
| `{firstIndustry}` `{lastIndustry}` | industry nearest each end stop within `industry.radius`; else per `industry.fallback` (`stop`, `town`, `empty`) | — |
| `{n}` | sequence number (§7.2) | `{lineNumber}` |

### 7.1 Syntax

- Modifiers after a colon, in any order: a number shortens to that many letters of each word;
  `u` upper-cases; `l` lower-cases. `{towns:3}` → `Spr – She`; `{firstTown:3u}` → `SPR`.
- `[ ... ]` is an optional group. If any token inside renders empty the whole group is dropped.
  Groups do not nest. `{type}[ {cargo}] {towns}[ #{n}]` never leaves a dangling separator.
- An unknown token renders as itself, so a typo is visible in the preview.
- After rendering, runs of spaces collapse to one and the result is trimmed.

### 7.2 Numbering

`{n}` disambiguates lines whose name is otherwise identical.

- `number.scope`: `sameName` (lines whose rendered name with `{n}` removed is equal), `kind`
  (all lines of the same kind), `global`.
- `number.first`: `blank` (first line gets no number, the next is 2) or `one`.
- `number.pad`: zero-pad width, 0 for none.

A line keeps its number across re-renames while its base name is unchanged.

## 8. Per-kind patterns

`patterns.default` plus an optional entry per kind. A kind without an entry inherits the default.
Each kind also has `autoRename` (default true), so, for example, trains can be left alone.

Shipped defaults:

- default: `{type} {towns}[ {n}]`
- `truck`, `trainCargo`, `shipCargo`, `airCargo`: `{cargo}: {firstIndustry} → {lastIndustry}[ {n}]`

Three built-in presets selectable in the Patterns tab: **Simple** (the shipped defaults),
**Upstream** (`{type} {cargo}-{towns:3}-{scope}-{n}` for every kind), **Detailed**
(`{type} {firstStop} – {lastStop}[ via {via}][ {n}]`). Choosing a preset overwrites the patterns
after a confirmation.

## 9. Settings

One schema table in `settings.lua` is the single source of truth. Each row:

```lua
{ path = "scan.linesPerTick", type = "int", min = 1, max = 50, default = 5,
  section = "performance", label = "set_scan_lines_per_tick", tooltip = "set_scan_lines_per_tick_tt" }
```

Types: `bool`, `int`, `number`, `string`, `enum` (with `values`). Defaults are derived from the
schema; nothing else holds a default.

- `settings.merge(userDefaults, saved)` deep-merges onto schema defaults and discards unknown or
  invalid values, so old saves load after settings are added or removed.
- `settings.set(path, value)` validates against the row and returns `ok, err`.
- `res/scripts/anujctrl/alnp/user_defaults.lua` returns a table of overrides applied to new saves.
  Settings are otherwise per save (game-script state). Editing this file is how the player sets
  their own defaults for every future save.
- `gui/schema_form.lua` builds the General and Advanced tabs from the rows: `bool` → check box,
  `int`/`number` → slider with value label, `string` → text field, `enum` → combo box. Adding a
  setting is one schema row and two strings.

Settings (defaults in brackets):

| Section | Path | Meaning |
|---|---|---|
| general | `enabled` [true] | master switch |
| general | `lock.prefix` [""] | names starting with this are never renamed |
| general | `lock.autoLockEdited` [true] | hand-edited names lock automatically |
| general | `reload.names` ["r,reload"] | names that request a one-off rename |
| eligibility | `eligible.defaultNames` [true] | rename lines with a game default name |
| eligibility | `eligible.modAssigned` [true] | re-rename lines the mod named when they change; off = name new lines once only |
| eligibility | `defaults.extraPrefixes` [""] | extra default-name words, comma-separated |
| eligibility | `minStops` [2] | fewer distinct stops than this: leave alone |
| labels | `label.kind.<kind>` [bus=Bus, tram=Tram, truck=Truck, trainPassenger=Train, trainCargo=Freight, shipPassenger=Ferry, shipCargo=Ship, airPassenger=Air, airCargo=Air Cargo, unknown=Line] | text for `{type}` |
| labels | `label.scope.<scope>` [Local, Intercity, Regional] | text for `{scope}` |
| scope | `scope.localMaxTowns` [1], `scope.regionalMinTowns` [3] | scope thresholds |
| separators | `sep.towns` [" – "], `sep.via` [", "], `sep.cargo` [", "] | joiners |
| cargo | `cargo.max` [2], `cargo.mixedLabel` ["Mixed"], `cargo.hidePassengers` [true] | `{cargo}` shaping |
| via | `via.max` [2] | intermediate towns shown |
| industry | `industry.radius` [400], `industry.fallback` [stop] | industry lookup |
| numbering | `number.scope` [sameName], `number.first` [blank], `number.pad` [0] | `{n}` |
| patterns | `patterns.default`, `patterns.<kind>`, `kinds.<kind>.autoRename` [true] | §8 |
| performance | `scan.linesPerTick` [5], `scan.settleSeconds` [5], `preview.linesPerFrame` [25] | work budget |
| logging | `log.level` [info] | `error`, `info`, `debug` |

Each section has a "Reset section" button. Reset of everything is on the General tab.

## 10. Window

Opened from a button in the top game-info bar. Tabs:

- **General** and **Advanced**: generated from the schema (§9). Advanced holds scope, separators,
  cargo, via, industry, numbering, performance and logging.
- **Patterns**: preset chooser; the default row; one row per kind with an auto-rename check box, a
  "custom pattern" check box, a text field and a live preview; a token cheat-sheet. The preview
  calls `naming.render` with sample facts for that kind, so it cannot drift from real output.
- **Lines**: table of the player's lines — kind, current name, proposed name, lock check box, and
  a "rename now" button per row. "Preview all" fills the proposed column by reading facts on the
  GUI thread in chunks of `preview.linesPerFrame` per `guiUpdate` frame. "Apply checked" sends the
  renames to the engine. Locked and hand-named rows start unchecked.

## 11. Errors and logging

- Every engine and GUI entry point runs under `xpcall`; an error is logged with a traceback and
  the game continues.
- `log.lua` prefixes `aln_plus:` and suppresses repeats of an identical message.
- Logs land in
  `~/.local/share/Steam/userdata/204184616/1066780/local/crash_dump/stdout.txt`.

## 12. Testing

Host: `lua5.4 test/run.lua` with `test/fake_api.lua`, the same shape as Bus Line Tool Plus.

- `naming`: every token, aliases, `:N`/`u`/`l` modifiers, optional groups, unknown tokens, space
  collapsing, numbering scopes, `first`, `pad`, number stability.
- `classify`: each kind, road cargo vs passenger, scope thresholds.
- `tracker`: one test per row of the §6 table, plus the hard rules.
- `settings`: defaults from schema, merge discarding bad values, `set` validation per type,
  user-defaults layering.
- `facts`: against the fake API, including a vanished line and a stop with no town.
- lint: the translation function `_` is never shadowed (ported from Bus Line Tool Plus).

In game: a README checklist — new line named; editing stops re-names it after the settle delay;
hand-edited name stays and shows as locked; per-kind pattern applies; preview and apply; a cargo
line shows industries; no hitch on the largest save with the Lines tab previewing.

## 13. Risks

1. **Industry lookup.** Expected: `game.interface.getEntities({pos, radius}, {type="SIM_BUILDING"})`.
   Not confirmed by the bundled API docs. The first implementation task is an in-game probe that
   logs the result for one cargo stop. If it fails, the industry tokens use `industry.fallback`
   and nothing else changes.
2. **Translated default name.** The probe also logs the game's translation of "Line".
   `defaults.extraPrefixes` covers any language by configuration either way.
3. **Author role.** `BASED_ON` is the accurate role for the original author. If the game rejects
   it when the probe build loads, use `CO_CREATOR`.
4. **Restart needed.** A new local mod appears in the mod list only after the game restarts.

## 14. Install

`install.sh` rsyncs the mod into
`~/.local/share/Steam/userdata/204184616/1066780/local/mods/auto_line_namer_plus_1`, excluding
`.git`, `docs`, `test`, `tf2-api`, `scripts`, `.github`, `.vscode`, `README.md` and itself.
`TPF2_LOCAL_MODS` overrides the destination root.
