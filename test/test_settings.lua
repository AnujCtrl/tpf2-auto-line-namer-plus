local settings = require("anujctrl/alnp/settings")
local kinds = require("anujctrl/alnp/kinds")
local eq = require("fake_api").eq
local t = {}

local KNOWN_TYPES = { bool = true, int = true, number = true, string = true, enum = true }
local KNOWN_TABS = { general = true, advanced = true, patterns = true }

function t.defaults_follow_the_dotted_paths()
    local d = settings.defaults()
    eq(d.scan.linesPerTick, 5)
    eq(d.label.kind.trainCargo, "Freight")
    eq(d.patterns.bus, "")
    eq(d.patterns.truck, "{cargo}: {firstIndustry} \226\134\146 {lastIndustry}[ {n}]")
    eq(d.kinds.tram.autoRename, true)
end

function t.defaults_are_fresh_each_call()
    local a = settings.defaults()
    a.scan.linesPerTick = 40
    eq(settings.defaults().scan.linesPerTick, 5)
end

function t.every_row_is_well_formed()
    local sectionKeys = {}
    for __, section in ipairs(settings.sections) do sectionKeys[section.key] = true end
    for __, row in ipairs(settings.schema) do
        assert(type(row.label) == "string" and row.label ~= "", "row " .. tostring(row.path) .. " needs a label")
        assert(type(row.help) == "string" and row.help ~= "", "row " .. tostring(row.path) .. " needs help")
        assert(KNOWN_TYPES[row.type], "row " .. tostring(row.path) .. " has unknown type " .. tostring(row.type))
        assert(sectionKeys[row.section], "row " .. tostring(row.path) .. " has unknown section " .. tostring(row.section))
        local ok = settings.validate(row, row.default)
        assert(ok, "row " .. tostring(row.path) .. " default fails its own validation")
    end
end

function t.no_two_rows_share_a_path_and_every_section_is_well_formed()
    local seen = {}
    for __, row in ipairs(settings.schema) do
        assert(not seen[row.path], "duplicate path " .. tostring(row.path))
        seen[row.path] = true
    end
    for __, section in ipairs(settings.sections) do
        assert(type(section.label) == "string" and section.label ~= "", "section " .. tostring(section.key) .. " needs a label")
        assert(type(section.help) == "string" and section.help ~= "", "section " .. tostring(section.key) .. " needs help")
        assert(KNOWN_TABS[section.tab], "section " .. tostring(section.key) .. " has unknown tab " .. tostring(section.tab))
    end
end

function t.no_help_line_is_longer_than_72_characters()
    local function checkLines(text, label)
        for line in (text .. "\n"):gmatch("(.-)\n") do
            assert(#line <= 72, label .. " has a help line over 72 characters: " .. line)
        end
    end
    for __, row in ipairs(settings.schema) do checkLines(row.help, "row " .. row.path) end
    for __, section in ipairs(settings.sections) do checkLines(section.help, "section " .. section.key) end
end

function t.every_row_help_has_a_description_line_and_an_example_line()
    for __, row in ipairs(settings.schema) do
        local lineCount = 0
        for __ in (row.help .. "\n"):gmatch("(.-)\n") do lineCount = lineCount + 1 end
        assert(lineCount >= 2, "row " .. row.path .. " help needs at least a description and an example line")
    end
end

function t.every_kind_has_a_label_pattern_and_autorename_row()
    for __, kind in ipairs(kinds.list) do
        assert(settings.row("label.kind." .. kind), "missing label.kind." .. kind)
        assert(settings.row("patterns." .. kind), "missing patterns." .. kind)
        assert(settings.row("kinds." .. kind .. ".autoRename"), "missing kinds." .. kind .. ".autoRename")
    end
end

function t.validate_checks_each_type()
    local boolRow = settings.row("enabled")
    eq(settings.validate(boolRow, true), true)
    eq(settings.validate(boolRow, 1), false)

    local intRow = settings.row("minStops")
    eq(settings.validate(intRow, 5), true)
    eq(settings.validate(intRow, 2.5), false)
    eq(settings.validate(intRow, 0), false)
    eq(settings.validate(intRow, "3"), false)

    local numberRow = { path = "test.number", type = "number", default = 1.5, min = 0, max = 10, section = "general", label = "x", help = "x" }
    eq(settings.validate(numberRow, 2.5), true)
    eq(settings.validate(numberRow, 20), false)

    local enumRow = settings.row("industry.fallback")
    eq(settings.validate(enumRow, "stop"), true)
    eq(settings.validate(enumRow, "nope"), false)

    local stringRow = settings.row("label.kind.bus")
    eq(settings.validate(stringRow, "Bus"), true)
    eq(settings.validate(stringRow, 5), false)
    eq(settings.validate(stringRow, string.rep("a", 201)), false)

    local nonEmptyRow = settings.row("patterns.default")
    eq(settings.validate(nonEmptyRow, ""), false)
end

function t.set_validates_writes_and_reports_unknown_paths()
    local ok, reason = settings.set({}, "no.such.path", true)
    eq(ok, false)
    assert(reason:find("no.such.path", 1, true), reason)

    local tbl = settings.defaults()
    local ok2, reason2 = settings.set(tbl, "minStops", 0)
    eq(ok2, false)
    assert(type(reason2) == "string" and reason2 ~= "")
    eq(tbl.minStops, 2)

    local ok3 = settings.set(tbl, "minStops", 5)
    eq(ok3, true)
    eq(settings.get(tbl, "minStops"), 5)

    local fresh = {}
    local ok4 = settings.set(fresh, "scan.linesPerTick", 10)
    eq(ok4, true)
    eq(fresh.scan.linesPerTick, 10)
end

function t.merge_layers_saved_over_userDefaults_over_default()
    eq(settings.merge(nil, nil), settings.defaults())

    local merged = settings.merge({ minStops = 5 }, { minStops = 7 })
    eq(merged.minStops, 7)

    local fallsBackToUserDefaults = settings.merge({ minStops = 5 }, { minStops = 999 })
    eq(fallsBackToUserDefaults.minStops, 5)

    local fallsBackToDefault = settings.merge(nil, { minStops = 999 })
    eq(fallsBackToDefault.minStops, 2)

    local dropsUnknownKeys = settings.merge(nil, { bogus = true })
    eq(dropsUnknownKeys.bogus, nil)
    eq(dropsUnknownKeys, settings.defaults())

    eq(settings.merge("x", 5), settings.defaults())
end

function t.patternFor_falls_back_to_default()
    local tbl = settings.defaults()
    tbl.patterns.truck = "Custom truck pattern"
    eq(settings.patternFor(tbl, "truck"), "Custom truck pattern")
    eq(settings.patternFor(tbl, "bus"), tbl.patterns.default)
    eq(settings.patternFor(tbl, "notAKind"), tbl.patterns.default)
end

function t.helpText_appends_generated_default_range_and_choices()
    local boolText = settings.helpText(settings.row("enabled"))
    assert(boolText:find("Default: on", 1, true), boolText)

    local intText = settings.helpText(settings.row("scan.linesPerTick"))
    assert(intText:find("Default: 5   Range: 1 to 50", 1, true), intText)

    local enumText = settings.helpText(settings.row("log.level"))
    assert(enumText:find("Choices: error, info, debug", 1, true), enumText)

    local emptyText = settings.helpText(settings.row("lock.prefix"))
    assert(emptyText:find("Default: (empty)", 1, true), emptyText)
end

function t.applyPreset_sets_default_and_blanks_kinds_or_rejects_unknown_key()
    local tbl = settings.defaults()
    tbl.patterns.truck = "custom"
    local ok = settings.applyPreset(tbl, "upstream")
    eq(ok, true)
    eq(tbl.patterns.default, "{type} {cargo}-{towns:3}-{scope}-{n}")
    for __, kind in ipairs(kinds.list) do
        eq(tbl.patterns[kind], "")
    end

    local unchanged = settings.defaults()
    local ok2 = settings.applyPreset(unchanged, "bogus")
    eq(ok2, false)
    eq(unchanged, settings.defaults())
end

function t.each_preset_produces_its_exact_patterns_for_every_kind()
    local expected = {
        simple = { default = "{type} {towns}[ {n}]",
            cargo = "{cargo}: {firstIndustry} \226\134\146 {lastIndustry}[ {n}]" },
        upstream = { default = "{type} {cargo}-{towns:3}-{scope}-{n}", cargo = nil },
        detailed = { default = "{type} {firstStop} \226\128\147 {lastStop}[ via {via}][ {n}]",
            cargo = "{cargo}: {firstIndustry} \226\134\146 {lastIndustry}[ via {via}][ {n}]" },
    }
    for presetKey, expectation in pairs(expected) do
        local tbl = settings.defaults()
        eq(settings.applyPreset(tbl, presetKey), true, presetKey)
        eq(tbl.patterns.default, expectation.default, presetKey .. " default")
        for __, kind in ipairs(kinds.list) do
            local wanted = kinds.cargo[kind] and (expectation.cargo or "") or ""
            eq(tbl.patterns[kind], wanted, presetKey .. " " .. kind)
        end
    end
end

function t.rowsIn_returns_schema_order_and_row_of_unknown_path_is_nil()
    local rows = settings.rowsIn("numbering")
    eq(#rows, 3)
    eq(rows[1].path, "number.scope")
    eq(rows[2].path, "number.first")
    eq(rows[3].path, "number.pad")
    eq(settings.row("nope"), nil)
end

-- The game writes its script-state file as Lua source with bare identifier keys, so any saved key
-- that is a Lua keyword (or not identifier-shaped) makes that file invalid and the game silently
-- drops this mod's whole state. Every key we can save must survive being written bare.
local LUA_KEYWORDS = {
    ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true,
    ["end"] = true, ["false"] = true, ["for"] = true, ["function"] = true, ["goto"] = true,
    ["if"] = true, ["in"] = true, ["local"] = true, ["nil"] = true, ["not"] = true,
    ["or"] = true, ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
    ["until"] = true, ["while"] = true,
}

local function checkKey(key, where)
    assert(type(key) == "string", where .. ": key is not a string")
    assert(not LUA_KEYWORDS[key], where .. ": " .. key .. " is a Lua keyword")
    assert(key:match("^[%a_][%w_]*$"), where .. ": " .. key .. " is not identifier-shaped")
end

function t.no_saved_key_is_a_lua_keyword()
    for __, row in ipairs(settings.schema) do
        for segment in row.path:gmatch("[^%.]+") do
            checkKey(segment, "settings path " .. row.path)
        end
    end
    for __, scope in ipairs(kinds.scopes) do checkKey(scope, "scope id") end
    for __, kind in ipairs(kinds.list) do checkKey(kind, "kind id") end
    for __, field in ipairs({ "lastAssigned", "locked", "number", "numberKey" }) do
        checkKey(field, "record field")
    end
    for __, field in ipairs({ "settings", "records", "version" }) do
        checkKey(field, "engine state field")
    end
end

return t
