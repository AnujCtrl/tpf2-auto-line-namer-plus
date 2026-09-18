-- The kinds of line the mod tells apart, and the scopes a line can have. Plain data.
local kinds = {}

kinds.list = {
    "bus", "tram", "truck",
    "trainPassenger", "trainCargo",
    "shipPassenger", "shipCargo",
    "airPassenger", "airCargo",
    "unknown",
}

-- Kinds whose shipped default pattern is the cargo one.
kinds.cargo = { truck = true, trainCargo = true, shipCargo = true, airCargo = true }

kinds.scopes = { "local", "intercity", "regional" }

-- English display names, shown in the Patterns and Lines tabs (wrap in _() at the call site).
kinds.label = {
    bus = "Bus",
    tram = "Tram",
    truck = "Truck",
    trainPassenger = "Passenger train",
    trainCargo = "Cargo train",
    shipPassenger = "Passenger ship",
    shipCargo = "Cargo ship",
    airPassenger = "Passenger aircraft",
    airCargo = "Cargo aircraft",
    unknown = "Other",
}

return kinds
