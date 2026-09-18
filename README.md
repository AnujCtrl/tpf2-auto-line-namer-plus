# Auto Line Namer Plus

Transport Fever 2 mod that names every line for you, from its stops, towns, industries and
cargo. It never overwrites a name you wrote yourself, looks at only a bounded number of lines
per game tick however large the save is, and exposes every tunable as a setting with an
in-window "i" button explaining it. A fork of erkanercan's Auto Line Namer, rebuilt from the
ground up so that everything except the code that reads the game is plain Lua, tested on the
host.

## How names are chosen, and when a line is left alone

Every game tick the engine checks `scan.linesPerTick` lines, in round-robin order. For each
line it computes a cheap signature (stop station-group ids, vehicle count, current name). If
the signature has not changed since last time, nothing else happens. If it changed, a settle
timer starts; only once the signature has been stable for `scan.settleSeconds` real seconds does
the mod read the line's full facts and decide what to do. The delay is measured in real seconds
(the system clock, `os.time()`), not game ticks. Whether `update()` — and so this whole
check — keeps running while the game is paused is not verified; see the first-launch checklist.

Once a line settles, the mod checks these conditions in order, and stops at the first match:

1. The mod is disabled, or auto-rename is turned off for that line's kind — left alone.
2. You ticked the lock box for the line on the Lines tab — left alone.
3. The name starts with the configured "never-rename prefix" — left alone.
4. The name is one of the reload-trigger words (`r`, `reload` by default) — renamed.
5. The name looks like a game default name (see below) and that is enabled — renamed.
6. The name is exactly what the mod named it last time, and re-renaming mod-assigned names is
   enabled — renamed.
7. The name is exactly what the mod named it last time, but that setting is off — left alone.
8. Anything else — you typed it yourself. If auto-lock is on, the line is locked (shown as
   "edited" on the Lines tab) and left alone from then on; if auto-lock is off, it is just left
   alone.

A "game default name" is `Line 12` (or its translated equivalent, e.g. `Linie 12` in German —
see the first-launch checklist below), plus any comma-separated word you add under "Extra
default-name words".

This whole list is what the engine's automatic scan checks. "Rename now" on the Lines tab
skips it entirely and renames that one line regardless of any lock — it is a manual override,
not a ninth rule.

Three rules apply no matter what the settings say:

- The mod never sends a rename when the new name is identical to the current one.
- The mod never assigns an empty or whitespace-only name.
- A line with fewer distinct stops than "Minimum stops" (default 2) is left alone.

A line id that no longer exists is dropped from the mod's records. Per-line locks and the name
the mod last assigned are saved in the save game (the mod's own state, via the game's
`save()`/`load()`, not a property stored on the line itself); scan signatures and settle timers
are not saved and start fresh each time the game loads.

## Patterns and tokens

A pattern is a template made of tokens, e.g. `{type} {towns}[ {n}]`, rendered against a line's
own facts. Every line kind uses the default pattern (Patterns tab) unless that same tab gives
it a custom pattern of its own. Each kind also has its own auto-rename switch (default on), so
you can turn off, say, trains and rename them by hand while everything else keeps auto-renaming.

### Tokens

| Token | Example | Meaning | Upstream alias |
|---|---|---|---|
| `{type}` | `Bus` | The line's kind, from the label settings. | `{transportType}` |
| `{scope}` | `Intercity` | The line's scope: Local, Intercity or Regional. | `{lineType}` |
| `{cargo}` | `Coal, Iron ore` | Cargo carried, joined by the cargo separator; collapses to the mixed-cargo label past the maximum; hidden on passenger-only lines by default. | `{cargoTypes}` |
| `{towns}` | `Springfield – Shelbyville` | First and last town, or the one town if there is only one. | `{townNames}` |
| `{firstTown}` | `Springfield` | The first town on the line. | — |
| `{lastTown}` | `Shelbyville` | The last town on the line. | — |
| `{via}` | `Ogdenville, North Haverbrook` | Up to "Max via towns shown" intermediate towns, neither end town. | — |
| `{firstStop}` | `Springfield Central` | Station name at the first stop. | — |
| `{lastStop}` | `Shelbyville East` | Station name at the last stop. | — |
| `{firstIndustry}` | `Coal mine` | Industry nearest the first stop within the search radius, else the fallback (stop name, town name, or empty). | — |
| `{lastIndustry}` | `Steel mill` | Industry nearest the last stop, same fallback rule. | — |
| `{n}` | `2` | Sequence number that tells apart otherwise-identical names (see Numbering below). | `{lineNumber}` |

"Last" always means the last stop in the line's stop order, so a line visiting A, B, C, B ends
at C.

### Modifiers

Add modifiers after a colon, in any order:

- A number keeps that many characters of each word in the token's value and joins them back
  together with no spaces, e.g. `{towns:3}` → `Spr – She`. A multi-word value truncates per
  word: `New York` at `:3` becomes `NewYor`.
- `u` upper-cases the value; `l` lower-cases it. `{firstTown:3u}` → `SPR`.

### Optional groups

`[ ... ]` marks an optional group. If any token inside it renders empty, the whole group —
including its surrounding punctuation — is dropped, so a pattern like `{type}[ {cargo}]
{towns}[ #{n}]` never leaves a dangling separator or a stray `#`. Groups cannot nest.

An unknown token (a typo) is left exactly as typed, so it is visible in the preview instead of
silently disappearing. After rendering, runs of spaces collapse to one and the result is trimmed.

### Numbering (`{n}`)

`{n}` disambiguates lines whose rendered name, with `{n}` removed, would otherwise be identical.
Three settings control it, all on the Advanced tab under Numbering:

- **Numbering scope**: `sameName` numbers lines sharing a rendered name together (default),
  `kind` numbers by line kind, `global` numbers across every line.
- **First number**: `blank` leaves the first line in a group unnumbered and the next gets `2`
  (default); `one` always shows a number, starting at `1`.
- **Zero-pad width**: pads `{n}` with leading zeros, e.g. width 2 turns `3` into `03`. `0`
  means no padding (default).

A line keeps the same number across re-renames as long as its base name (the name with `{n}`
removed) does not change.

### Shipped default patterns per kind

- Default (every kind without its own pattern): `{type} {towns}[ {n}]`
- Cargo kinds (truck, cargo train, cargo ship, cargo aircraft):
  `{cargo}: {firstIndustry} → {lastIndustry}[ {n}]`

### Presets

The Patterns tab has a preset chooser. Pick a preset from the dropdown, then click "Apply
preset" twice — the first click arms it, the second confirms — since applying a preset
overwrites the default pattern and every kind's own pattern.

| Preset | Default pattern | Cargo-kind pattern (truck, cargo train/ship/aircraft) |
|---|---|---|
| **Simple** | `{type} {towns}[ {n}]` | `{cargo}: {firstIndustry} → {lastIndustry}[ {n}]` |
| **Upstream** | `{type} {cargo}-{towns:3}-{scope}-{n}` for every kind, cargo kinds included | (same as default) |
| **Detailed** | `{type} {firstStop} – {lastStop}[ via {via}][ {n}]` | `{cargo}: {firstIndustry} → {lastIndustry}[ via {via}][ {n}]` |

Simple is what the mod ships with. Upstream reproduces the original Auto Line Namer's layout.
Detailed spells out the route by its first and last stop, with any towns in between; for cargo
kinds it instead names them by cargo and industry (with via towns added), matching how Simple
already treats cargo kinds differently from passenger kinds.

## Install

```bash
./install.sh
```

This copies the mod into the game's local mods folder as `auto_line_namer_plus_1`
(`TPF2_LOCAL_MODS` overrides the destination root, for testing).

Then:

1. **Restart Transport Fever 2.** A new local mod only appears in the mod list after a restart.
2. Enable "Auto Line Namer Plus" in the mod list.
3. If you are subscribed to the Workshop "Auto Line Namer", disable it. Two mods must not
   rename the same lines.
4. In a game, click the **"[ALN+]"** button in the top game-info bar to open the settings
   window.

## First-launch checklist

On the Advanced tab, click "Run API check". Then read
`~/.local/share/Steam/userdata/<your Steam id>/1066780/local/crash_dump/stdout.txt` for the
lines it writes, all starting `aln_plus: api check:`.

- **(a)** If a cargo stop's industry shows `nil`, the industry lookup found nothing for it. This
  is expected on some maps or stop placements; the industry tokens fall back to the stop name
  (or town name, or empty, per "When no industry is found") and everything else keeps working.
- **(b)** Whatever the report's translated word for "Line" is, it is already recognised
  automatically. Only act if new lines in your language are **not** named "`<that word>
  <number>`": look at a fresh line's default name and add its first word to "Extra default-name
  words" on the General tab.
- **(c)** If the mod list shows no author for the mod, change `BASED_ON` to `CO_CREATOR` for
  `erkanercan` in `mod.lua` and reinstall.
- **(d)** If the numeric options on the Advanced tab show text fields instead of sliders, the
  slider constructor guess in `gui/schema_form.lua` was wrong for your game version. The text
  fields still work exactly the same; `stdout.txt` will have one `aln_plus:` line saying the
  slider widget was unavailable and it fell back to a text field.
- **(e)** Is `update()` called while the game is paused? Pause the game, wait past the settle
  delay, then check whether a changed line still gets renamed. This is unverified; it decides
  whether the settle delay actually behaves the same paused as running.

## In-game checklist

1. A newly built line with a default name gets a name from the mod.
2. Editing a line's stops re-names it, after the settle delay.
3. A line you rename by hand keeps that name and shows as locked on the Lines tab.
4. Giving a kind its own pattern on the Patterns tab changes only lines of that kind.
5. "Preview all" fills in proposed names without changing anything; "Apply checked" renames the
   ticked rows.
6. A cargo line's rendered name shows the industries at its ends (or the configured fallback).
7. Previewing on the largest save you have causes no hitch — the Lines tab reads facts in small
   chunks over several frames.
8. Every "i" button shows its tooltip on hover and fills the help panel at the bottom of the
   window on click, with no text cut off.
9. Preview a line, rename it by hand in-game before applying, then tick its row and click
   "Apply checked": the row is skipped and shows "(name changed: preview again)" — your
   hand-written name survives.
10. The window resizes and scrolls correctly on all four tabs (General, Advanced, Patterns,
    Lines).
11. A kind that should inherit the default pattern stays unticked under "Custom pattern" after
    closing and reopening the window once.
12. The arrow (`→`) and en dash (`–`) used in the shipped patterns render correctly in the
    game's font, not as missing-glyph boxes.
13. Check what `{cargo}` renders for a truck set to carry every cargo type.
14. Check a brand-new line with no vehicles yet.

## Tests

```bash
lua5.4 test/run.lua
```

Runs the whole suite against a fake game API (`test/fake_api.lua`); nothing here touches a real
Transport Fever 2 install. The installed game binary embeds Lua 5.2.2 (`strings
TransportFever2` shows `$LuaVersion: Lua 5.2.2`), so the code is restricted to the subset of
syntax valid in both Lua 5.1 and 5.2, and the suite also passes under `lua5.4`, `lua5.1` and
`luajit` (5.2 itself is not installed on this machine) — the lint test (`test/test_lint.lua`)
checks every file for syntax newer than Lua 5.1 (rejects `goto`, `//`, `table.unpack` without a
fallback, `utf8.`, `string.pack`, `<const>`/`<close>`).

## Design

- Design: `docs/superpowers/specs/2026-09-18-auto-line-namer-plus-design.md`
- Implementation plan: `docs/superpowers/plans/2026-09-18-auto-line-namer-plus/`

## Credit and licence

A fork of [Auto Line Namer](https://github.com/erkanercan/TPF2-AutoLineNamer) by erkanercan,
rebuilt. MIT licence — see `LICENSE`:

```
Copyright (c) 2025 Erkan Ercan
Copyright (c) 2026 AnujCtrl
```

## Known limitations

- The `u`/`l` case modifiers are ASCII only; they do not upper- or lower-case accented or
  non-Latin characters.
- Help text is written with explicit line breaks at about 70 characters and does not re-wrap to
  the window's actual width.
- Settings and per-line locks are stored per save, not globally. To change what a **new** save
  starts with, edit `res/scripts/anujctrl/alnp/user_defaults.lua` in the repo and reinstall —
  `install.sh` overwrites the installed copy, so editing the installed file directly is lost on
  the next install.
- The mod cannot be run outside Transport Fever 2, so anything that touches the real game API
  (the top-bar button, the window, in-game renames) is verified with the checklists above
  rather than by an automated test.
- A line's name is only re-evaluated when its stops, vehicle count or current name change (see
  `facts.signature`). A refit to a different cargo at the same vehicle count, or renaming a
  station or town, does not update the line's name until something else changes it — naming the
  line `r` forces a re-evaluation.
