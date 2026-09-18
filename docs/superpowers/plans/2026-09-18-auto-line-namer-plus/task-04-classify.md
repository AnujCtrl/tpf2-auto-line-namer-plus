# Task 4: classify

**Files:**
- Create: `res/scripts/anujctrl/alnp/classify.lua`
- Test: `test/test_classify.lua`

**Interfaces:**
- Consumes: facts table (C3); `tbl.scope.localMaxTowns`, `tbl.scope.regionalMinTowns` (build the
  table by hand in tests — do NOT require `settings.lua`, it is being written in parallel).
- Produces: contract C5.

Read spec §5.2. Pure Lua: no `api`, no `game`.

## Rules

`classify.kind(facts)`:

1. `cargoOnly` = `facts.carriesCargo and not facts.carriesPassengers`.
   When `facts.vehicleCount == 0` there is no cargo information, so instead
   `cargoOnly = facts.modes.truck == true and facts.modes.bus ~= true`.
2. First match wins:
   - `modes.tram` → `"tram"`
   - `modes.bus` or `modes.truck` → `cargoOnly and "truck" or "bus"`
   - `modes.train` → `cargoOnly and "trainCargo" or "trainPassenger"`
   - `modes.ship` → `cargoOnly and "shipCargo" or "shipPassenger"`
   - `modes.air` → `cargoOnly and "airCargo" or "airPassenger"`
   - otherwise `"unknown"`
3. A line carrying both passengers and cargo is a passenger kind.
4. `facts.modes` may be nil or empty → `"unknown"`.

`classify.scope(facts, tbl)` with `count = #(facts.towns or {})`:
- `count >= tbl.scope.regionalMinTowns` → `"regional"`
- `count <= tbl.scope.localMaxTowns` → `"local"` (a line with 0 towns is local)
- otherwise `"intercity"`
- If the thresholds overlap (e.g. localMax 3, regionalMin 2), regional wins — check it first.

## Steps

- [ ] **Step 1: Write `test/test_classify.lua`.** Helper and style:

```lua
local classify = require("anujctrl/alnp/classify")
local kinds = require("anujctrl/alnp/kinds")
local eq = require("fake_api").eq
local t = {}

local function line(modes, passengers, cargo, vehicles, towns)
    return { modes = modes, carriesPassengers = passengers, carriesCargo = cargo,
        vehicleCount = vehicles == nil and 1 or vehicles, towns = towns or {} }
end
local SCOPE = { scope = { localMaxTowns = 1, regionalMinTowns = 3 } }

function t.bus_with_passengers_is_a_bus()
    eq(classify.kind(line({ bus = true }, true, false)), "bus")
end

return t
```

  Required cases:

  | modes | passengers | cargo | vehicles | expected kind |
  |---|---|---|---|---|
  | bus | true | false | 1 | bus |
  | bus, truck | false | true | 1 | truck |
  | truck | false | true | 1 | truck |
  | bus, truck | true | true | 1 | bus |
  | truck | false | false | 0 | truck |
  | bus, truck | false | false | 0 | bus |
  | tram | true | false | 1 | tram |
  | tram, bus | true | false | 1 | tram |
  | train | true | false | 1 | trainPassenger |
  | train | false | true | 1 | trainCargo |
  | train | true | true | 1 | trainPassenger |
  | train | false | false | 0 | trainPassenger |
  | ship | false | true | 1 | shipCargo |
  | ship | true | false | 1 | shipPassenger |
  | air | false | true | 1 | airCargo |
  | air | true | false | 1 | airPassenger |
  | (empty table) | true | false | 1 | unknown |
  | nil | true | false | 1 | unknown |

  Plus: every result above is a member of `kinds.list`.

  Scope cases with `SCOPE`: 0 towns → local; 1 → local; 2 → intercity; 3 → regional; 5 → regional.
  With `{ scope = { localMaxTowns = 2, regionalMinTowns = 4 } }`: 2 → local; 3 → intercity; 4 → regional.
  With overlapping `{ localMaxTowns = 3, regionalMinTowns = 2 }`: 2 → regional. `facts.towns = nil` → local.

- [ ] **Step 2: Run it and watch it fail** — `lua5.4 test/run.lua test_classify`.
- [ ] **Step 3: Implement `classify.lua`** following the rules above.
- [ ] **Step 4: Run** `lua5.4 test/run.lua test_classify` → all pass. `luac -p` the module.
- [ ] **Step 5: Report** (do not commit): files written, test count, any contract concern.
