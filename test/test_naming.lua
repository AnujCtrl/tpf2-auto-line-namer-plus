local naming = require("anujctrl/alnp/naming")
local eq = require("fake_api").eq
local t = {}

local function tbl(over)
    local s = {
        label = {
            kind = { bus = "Bus", trainCargo = "Freight", truck = "Truck" },
            scope = { ["local"] = "Local", intercity = "Intercity", regional = "Regional" },
        },
        sep = { towns = " – ", via = ", ", cargo = ", " },
        cargo = { max = 2, mixedLabel = "Mixed", hidePassengers = true },
        via = { max = 2 },
        industry = { fallback = "stop" },
        number = { first = "blank", pad = 0 },
    }
    for section, values in pairs(over or {}) do
        for k, v in pairs(values) do s[section][k] = v end
    end
    return s
end

local function bus()
    return {
        id = 1, name = "Line 1", modes = { bus = true }, vehicleCount = 2,
        cargos = { "Passengers" }, carriesPassengers = true, carriesCargo = false,
        towns = { "Springfield", "Ogdenville", "North Haverbrook", "Shelbyville" },
        stops = {
            { stationGroup = 11, stop = "Springfield Central", town = "Springfield" },
            { stationGroup = 12, stop = "Ogdenville Mall", town = "Ogdenville" },
            { stationGroup = 13, stop = "Haverbrook Monorail", town = "North Haverbrook" },
            { stationGroup = 14, stop = "Shelbyville East", town = "Shelbyville" },
        },
    }
end

local function freight()
    return {
        id = 2, name = "Line 2", modes = { train = true }, vehicleCount = 1,
        cargos = { "Coal", "Iron ore" }, carriesPassengers = false, carriesCargo = true,
        towns = { "Springfield" },
        stops = {
            { stationGroup = 21, stop = "Springfield Yard", town = "Springfield", industry = "Coal mine" },
            { stationGroup = 22, stop = "Remote Halt", town = nil, industry = nil },
        },
    }
end

local function ctx(kind, over, n) return { settings = tbl(over), kind = kind, scope = "intercity", n = n } end

function t.default_pattern_names_a_bus_line()
    eq(naming.render("{type} {towns}[ {n}]", bus(), ctx("bus")), "Bus Springfield – Shelbyville")
end

function t.number_appears_from_two_when_first_is_blank()
    eq(naming.render("{type} {towns}[ {n}]", bus(), ctx("bus", nil, 1)), "Bus Springfield – Shelbyville")
    eq(naming.render("{type} {towns}[ {n}]", bus(), ctx("bus", nil, 2)), "Bus Springfield – Shelbyville 2")
end

function t.number_one_shows_when_first_is_one_and_pads()
    eq(naming.render("{type} #{n}", bus(), ctx("bus", { number = { first = "one", pad = 3 } }, 1)), "Bus #001")
end

function t.upstream_aliases_render_the_same()
    local a = naming.render("{transportType} {cargoTypes}-{townNames}-{lineType}-{lineNumber}", freight(), ctx("trainCargo", nil, 4))
    local b = naming.render("{type} {cargo}-{towns}-{scope}-{n}", freight(), ctx("trainCargo", nil, 4))
    eq(a, b)
    eq(b, "Freight Coal, Iron ore-Springfield-Intercity-4")
end

function t.abbreviation_applies_per_element_and_keeps_the_separator()
    eq(naming.render("{towns:3}", bus(), ctx("bus")), "Spr – She")
end

function t.abbreviation_joins_the_words_of_one_name()
    eq(naming.render("{lastStop:3}", bus(), ctx("bus")), "SheEas")
end

function t.case_modifiers()
    eq(naming.render("{firstTown:3u}/{type:l}", bus(), ctx("bus")), "SPR/bus")
    eq(naming.render("{firstTown:u3}", bus(), ctx("bus")), "SPR")
end

function t.abbreviation_counts_utf8_characters()
    local f = bus()
    f.towns = { "Zürich", "Łódź" }
    eq(naming.render("{towns:2}", f, ctx("bus")), "Zü – Łó")
end

function t.via_lists_intermediate_towns_up_to_the_maximum()
    eq(naming.render("{via}", bus(), ctx("bus")), "Ogdenville, North Haverbrook")
    eq(naming.render("{via}", bus(), ctx("bus", { via = { max = 1 } })), "Ogdenville")
    eq(naming.render("{via}", bus(), ctx("bus", { via = { max = 0 } })), "")
end

function t.optional_group_is_dropped_when_a_token_inside_is_empty()
    eq(naming.render("{type}[ via {via}] {lastTown}", freight(), ctx("trainCargo")), "Freight Springfield")
    eq(naming.render("{type}[ via {via}] {lastTown}", bus(), ctx("bus")), "Bus via Ogdenville, North Haverbrook Shelbyville")
end

function t.passenger_cargo_is_hidden_on_passenger_lines_by_default()
    eq(naming.render("{type}[ {cargo}]", bus(), ctx("bus")), "Bus")
    eq(naming.render("{type}[ {cargo}]", bus(), ctx("bus", { cargo = { hidePassengers = false } })), "Bus Passengers")
end

function t.too_many_cargos_collapse_to_the_mixed_label()
    local f = freight()
    f.cargos = { "Coal", "Iron ore", "Steel" }
    eq(naming.render("{cargo}", f, ctx("trainCargo")), "Mixed")
    eq(naming.render("{cargo}", f, ctx("trainCargo", { cargo = { max = 3 } })), "Coal, Iron ore, Steel")
end

function t.industry_tokens_fall_back_as_configured()
    local p = "{firstIndustry} → {lastIndustry}"
    eq(naming.render(p, freight(), ctx("trainCargo")), "Coal mine → Remote Halt")
    eq(naming.render(p, freight(), ctx("trainCargo", { industry = { fallback = "town" } })), "Coal mine →")
    eq(naming.render("[{firstIndustry} → {lastIndustry}]", freight(), ctx("trainCargo", { industry = { fallback = "empty" } })), "")
end

function t.one_town_line_shows_the_town_once()
    eq(naming.render("{towns}", freight(), ctx("trainCargo")), "Springfield")
end

function t.no_towns_and_no_stops_render_empty_not_nil()
    local f = freight()
    f.towns, f.stops = {}, {}
    eq(naming.render("{towns}{firstTown}{lastTown}{via}{firstStop}{lastStop}{firstIndustry}", f, ctx("trainCargo")), "")
end

function t.unknown_token_is_shown_as_typed_and_counts_as_present()
    eq(naming.render("{type}[ {bogus}]", bus(), ctx("bus")), "Bus {bogus}")
end

function t.unclosed_bracket_is_literal()
    eq(naming.render("{type} [x", bus(), ctx("bus")), "Bus [x")
end

function t.spaces_collapse_and_trim()
    eq(naming.render("  {type}   {cargo}   {firstTown} ", bus(), ctx("bus")), "Bus Springfield")
end

function t.percent_signs_in_names_are_safe()
    local f = bus()
    f.towns = { "100%ville", "%1" }
    eq(naming.render("{towns}", f, ctx("bus")), "100%ville – %1")
end

function t.missing_label_renders_empty()
    eq(naming.render("[{type} ]{firstTown}", bus(), ctx("airCargo")), "Springfield")
end

function t.usesNumber_sees_n_with_and_without_modifiers_and_the_alias()
    eq(naming.usesNumber("{type} {n}"), true)
    eq(naming.usesNumber("{type} {lineNumber}"), true)
    eq(naming.usesNumber("{type} {n:u}"), true)
    eq(naming.usesNumber("{type} {towns}"), false)
    eq(naming.usesNumber("{type} {name}"), false)
end

function t.pickNumber_keeps_a_free_current_number_else_takes_the_lowest_free()
    eq(naming.pickNumber(3, { [1] = true, [2] = true }), 3)
    eq(naming.pickNumber(2, { [1] = true, [2] = true }), 3)
    eq(naming.pickNumber(nil, {}), 1)
    eq(naming.pickNumber(nil, { [1] = true, [3] = true }), 2)
end

function t.sample_facts_exist_for_every_kind_and_render_without_error()
    local kinds = require("anujctrl/alnp/kinds")
    for __, kind in ipairs(kinds.list) do
        local f = naming.sampleFacts(kind)
        assert(#f.stops >= 2 and #f.towns >= 1, kind)
        local out = naming.render("{type} {cargo} {towns} {firstIndustry}", f, ctx(kind))
        assert(type(out) == "string", kind)
    end
    eq(naming.sampleFacts("truck").carriesCargo, true)
    eq(naming.sampleFacts("bus").carriesCargo, false)
end

function t.sample_facts_classify_as_their_own_kind()
    local classify = require("anujctrl/alnp/classify")
    local kinds = require("anujctrl/alnp/kinds")
    for __, kind in ipairs(kinds.list) do
        eq(classify.kind(naming.sampleFacts(kind)), kind, kind)
    end
end

function t.token_reference_lists_every_token_once_with_help_and_example()
    local seen = {}
    for __, entry in ipairs(naming.tokens) do
        assert(entry.token:match("^{%a+}$"), tostring(entry.token))
        assert(entry.help ~= "" and entry.example ~= "", entry.token)
        assert(not seen[entry.token], "duplicate " .. entry.token)
        seen[entry.token] = true
    end
    for __, token in ipairs({ "{type}", "{scope}", "{cargo}", "{towns}", "{firstTown}", "{lastTown}", "{via}",
        "{firstStop}", "{lastStop}", "{firstIndustry}", "{lastIndustry}", "{n}" }) do
        assert(seen[token], token .. " missing from naming.tokens")
    end
end

return t
