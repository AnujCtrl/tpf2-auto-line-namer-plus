-- Pure classification: a facts table (see spec sec5.1) becomes a line kind and scope.
-- No game API calls; only plain tables in, a string out.
local classify = {}

-- classify.kind(facts) -> one of kinds.list.
function classify.kind(facts)
    local modes = facts.modes
    if not modes then return "unknown" end

    local cargoOnly
    if facts.vehicleCount == 0 then
        -- No vehicles means no cargo/passenger info; fall back to which road mode is present.
        cargoOnly = modes.truck == true and modes.bus ~= true
    else
        cargoOnly = facts.carriesCargo and not facts.carriesPassengers
    end

    if modes.tram then return "tram" end
    if modes.bus or modes.truck then return cargoOnly and "truck" or "bus" end
    if modes.train then return cargoOnly and "trainCargo" or "trainPassenger" end
    if modes.ship then return cargoOnly and "shipCargo" or "shipPassenger" end
    if modes.air then return cargoOnly and "airCargo" or "airPassenger" end
    return "unknown"
end

-- facts.scope, tbl.scope.{localMaxTowns,regionalMinTowns} -> one of kinds.scopes.
-- Overlapping thresholds: regional is checked first, so it wins.
function classify.scope(facts, tbl)
    local count = #(facts.towns or {})
    if count >= tbl.scope.regionalMinTowns then return "regional" end
    if count <= tbl.scope.localMaxTowns then return "local" end
    return "intercity"
end

return classify
