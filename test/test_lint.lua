-- Static guards over every file the mod ships: `_` shadowing, the layering rules and Lua-5.1-only
-- syntax are only ever revealed by the game at runtime, so they are checked here as plain text.
-- Scans every .lua file under res/ plus mod.lua and strings.lua; other tasks are writing some of
-- these files right now, so a listed path that does not exist yet is skipped, not an error.
local t = {}

local function findLuaFiles()
    local files = {}
    local listing = assert(io.popen("find res -name '*.lua'"))
    for path in listing:lines() do files[#files + 1] = path end
    listing:close()
    files[#files + 1] = "mod.lua"
    files[#files + 1] = "strings.lua"
    table.sort(files)
    return files
end

-- nil (not an error) for a file another task has not written yet, or a transient read race.
local function readLines(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = line end
    return lines
end

function t.can_read_at_least_the_files_already_written()
    local any = false
    for __, path in ipairs(findLuaFiles()) do
        if readLines(path) then any = true end
    end
    assert(any, "no .lua files found under res/, mod.lua or strings.lua")
end

-- Reduces a line to just its code: every quoted string span ("..." or '...', honouring backslash
-- escapes so `"say \"hi\" // x"` stays one span) is dropped entirely, then a trailing `-- ...`
-- line comment is dropped too. A syntax mention inside a string or a comment -- a URL, a help
-- example, the English word "goto" -- is therefore invisible to every pattern check below. A
-- per-line heuristic is enough for this codebase: no file opens a `[[ ... ]]` long string, so no
-- check here needs to track state across lines.
local function codeOnly(line)
    local out = {}
    local i, n = 1, #line
    while i <= n do
        if line:sub(i, i + 1) == "--" then
            break
        end
        local c = line:sub(i, i)
        if c == '"' or c == "'" then
            local quote = c
            i = i + 1
            while i <= n do
                local d = line:sub(i, i)
                if d == "\\" then
                    i = i + 2
                elseif d == quote then
                    i = i + 1
                    break
                else
                    i = i + 1
                end
            end
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

function t.codeOnly_strips_strings_and_comments_but_keeps_real_code()
    local eq = function(actual, expected, label)
        assert(actual == expected, label .. ": expected " .. ("%q"):format(expected) .. ", got " .. ("%q"):format(actual))
    end
    eq(codeOnly('local probeStr = "a // b"'):find("//", 1, true) and "has //" or "no //", "no //", "string containing //")
    eq(codeOnly("local x = 1 -- 7 // 2"):find("//", 1, true) and "has //" or "no //", "no //", "// only in a trailing comment")
    eq(codeOnly('help = "goto settings"'):find("goto", 1, true) and "has goto" or "no goto", "no goto", "goto only inside a string")
    eq(codeOnly('local s = "say \\"hi\\" // x"'):find("//", 1, true) and "has //" or "no //", "no //", "// inside an escaped-quote string")
    eq(codeOnly("local x = 7 // 2"):find("//", 1, true) and "has //" or "no //", "has //", "a real // outside any string/comment")
    eq(codeOnly("goto done"):find("goto", 1, true) and "has goto" or "no goto", "has goto", "a real goto statement")
end

-- In Transport Fever 2, `_` is the translation function. A loop variable, a local or a parameter
-- named `_` shadows it and any later `_("text")` in that scope calls a number. The loop-variable
-- and local patterns are ported verbatim from tpf2-bus-line-tool/test/test_lint.lua; the %f
-- frontiers keep `__` (the approved spelling) clean.
--
-- The parameter pattern is extended past that reference (controller ruling): the reference only
-- matches the word `function` directly against `(`, so it catches an anonymous `function(_, x)`
-- but not this codebase's dominant style, a NAMED declaration -- `local function foo(_, x)`,
-- `function M.foo(_, x)`, `function M:foo(_)`. `[%w_.:]*` between `function` and `(` accepts that
-- name (identifier characters, dots for a table path, one colon for a method), or nothing at all
-- for the anonymous case, before checking the captured parameter list for a bare `_`.
local function shadowsUnderscore(code)
    if code:match("for%s+_%s*[,i]") then return true end
    if code:match("^%s*local%s+_%s*[,=]") then return true end
    local params = code:match("function%s*[%w_.:]*%s*%(([^)]*)%)")
    return params ~= nil and params:match("%f[%w_]_%f[^%w_]") ~= nil
end

function t.underscore_never_shadows_the_translator()
    local offenders = {}
    for __, path in ipairs(findLuaFiles()) do
        local lines = readLines(path)
        if lines then
            for n, line in ipairs(lines) do
                if shadowsUnderscore(codeOnly(line)) then
                    offenders[#offenders + 1] = path .. ":" .. n .. ": " .. line:gsub("^%s+", "")
                end
            end
        end
    end
    assert(#offenders == 0, "`_` shadowed in:\n  " .. table.concat(offenders, "\n  "))
end

function t.underscore_shadow_checker_catches_named_and_anonymous_function_parameters()
    local mustReport = {
        "local function foo(_, x)",
        "function M.foo(x, _)",
        "function M:bar(_)",
        "function(_, x)",
        "x = function(a, _)",
    }
    for __, line in ipairs(mustReport) do
        assert(shadowsUnderscore(codeOnly(line)), "expected to catch: " .. line)
    end

    local mustNotReport = {
        "local function foo(__, x)",
        "function M.foo(x_, _y)",
        'local text = _("Hello")',
        'call(function() return _("x") end)',
    }
    for __, line in ipairs(mustNotReport) do
        assert(not shadowsUnderscore(codeOnly(line)), "expected NOT to catch: " .. line)
    end
end

-- os.execute's success signal is not portable: 5.2+ returns `true` on success, but 5.1 and
-- LuaJIT (its default, non-52compat build) return the raw OS status code as a plain number --
-- always truthy, 0 or not -- so `not os.execute(cmd)` never fires under those two. Normalise both
-- conventions to a real boolean.
local function shellOk(cmd)
    local a = os.execute(cmd)
    if type(a) == "boolean" then return a end
    return a == 0
end

-- Catches the "0then" class of typo before the game does.
function t.every_file_parses()
    local offenders = {}
    local haveLuac51 = shellOk("command -v luac5.1 >/dev/null 2>&1")
    for __, path in ipairs(findLuaFiles()) do
        if readLines(path) then
            if not shellOk("luac -p " .. path .. " >/dev/null 2>&1") then
                offenders[#offenders + 1] = path .. " (luac -p)"
            end
            if haveLuac51 and not shellOk("luac5.1 -p " .. path .. " >/dev/null 2>&1") then
                offenders[#offenders + 1] = path .. " (luac5.1 -p)"
            end
        end
    end
    assert(#offenders == 0, "does not parse:\n  " .. table.concat(offenders, "\n  "))
end

local ENGINE_PATH = "res/scripts/anujctrl/alnp/engine.lua"
local GAME_SCRIPT_PATH = "res/config/game_script/auto_line_namer_plus.lua"
local FACTS_PATH = "res/scripts/anujctrl/alnp/facts.lua"
local LOG_PATH = "res/scripts/anujctrl/alnp/log.lua"

local function isUnderGui(path)
    return path:find("/gui/", 1, true) ~= nil
end

-- Checks that `needle` (a plain-text substring, not a pattern) appears in the CODE (see
-- codeOnly()) only of files for which `allowed(path)` is true; every other occurrence is an
-- offender. A mention inside a string or a comment is not a call, so it is not checked at all.
local function checkRestrictedTo(needle, allowed, label)
    local offenders = {}
    for __, path in ipairs(findLuaFiles()) do
        if not allowed(path) then
            local lines = readLines(path)
            if lines then
                for n, line in ipairs(lines) do
                    if codeOnly(line):find(needle, 1, true) then
                        offenders[#offenders + 1] = path .. ":" .. n .. ": " .. line:gsub("^%s+", "")
                    end
                end
            end
        end
    end
    assert(#offenders == 0, label .. " used outside its allowed files:\n  " .. table.concat(offenders, "\n  "))
end

function t.api_engine_res_and_game_interface_are_restricted_to_facts()
    local function allowed(path) return path == FACTS_PATH end
    checkRestrictedTo("api.engine", allowed, "api.engine")
    checkRestrictedTo("api.res", allowed, "api.res")
    checkRestrictedTo("game.interface", allowed, "game.interface")
end

function t.api_cmd_is_restricted_to_engine_and_the_game_script()
    checkRestrictedTo("api.cmd", function(path)
        return path == ENGINE_PATH or path == GAME_SCRIPT_PATH
    end, "api.cmd")
end

function t.api_gui_is_restricted_to_the_gui_directory()
    checkRestrictedTo("api.gui", isUnderGui, "api.gui")
end

function t.print_is_restricted_to_log()
    checkRestrictedTo("print(", function(path) return path == LOG_PATH end, "print(")
end

-- Collects every line whose CODE (see codeOnly()) matches `pattern`, across every listed file, as
-- file:line offender strings. `pattern` is a Lua pattern (not a plain substring); a false
-- positive from a comment or a help string that merely mentions the banned syntax is impossible
-- by construction (codeOnly already removed it), so a real false positive here would mean
-- tightening the pattern itself, not editing whatever file it fired on.
local function collectPatternOffenders(pattern)
    local offenders = {}
    for __, path in ipairs(findLuaFiles()) do
        local lines = readLines(path)
        if lines then
            for n, line in ipairs(lines) do
                if codeOnly(line):match(pattern) then
                    offenders[#offenders + 1] = path .. ":" .. n .. ": " .. line:gsub("^%s+", "")
                end
            end
        end
    end
    return offenders
end

function t.no_goto_statement()
    local offenders = collectPatternOffenders("%f[%a]goto%s+%a")
    assert(#offenders == 0, "`goto` used in:\n  " .. table.concat(offenders, "\n  "))
end

function t.no_integer_division_operator()
    local offenders = collectPatternOffenders("//")
    assert(#offenders == 0, "`//` used in:\n  " .. table.concat(offenders, "\n  "))
end

-- `table.unpack` is 5.2+; res/ code must spell it `(unpack or table.unpack)(...)` so it also
-- works on 5.1, where `unpack` is a global and `table.unpack` does not exist.
function t.table_unpack_always_has_a_51_fallback()
    local offenders = {}
    for __, path in ipairs(findLuaFiles()) do
        local lines = readLines(path)
        if lines then
            for n, line in ipairs(lines) do
                local code = codeOnly(line)
                if code:find("table%.unpack%(") and not code:find("unpack or", 1, true) then
                    offenders[#offenders + 1] = path .. ":" .. n .. ": " .. line:gsub("^%s+", "")
                end
            end
        end
    end
    assert(#offenders == 0, "`table.unpack(` without an `unpack or` fallback in:\n  " .. table.concat(offenders, "\n  "))
end

function t.no_utf8_library()
    local offenders = collectPatternOffenders("utf8%.")
    assert(#offenders == 0, "`utf8.` used in:\n  " .. table.concat(offenders, "\n  "))
end

function t.no_string_pack()
    local offenders = collectPatternOffenders("string%.pack")
    assert(#offenders == 0, "`string.pack` used in:\n  " .. table.concat(offenders, "\n  "))
end

function t.no_local_attributes()
    local offenders = collectPatternOffenders("<const>")
    for __, offender in ipairs(collectPatternOffenders("<close>")) do offenders[#offenders + 1] = offender end
    assert(#offenders == 0, "`<const>`/`<close>` used in:\n  " .. table.concat(offenders, "\n  "))
end

function t.no_line_over_150_characters()
    local offenders = {}
    for __, path in ipairs(findLuaFiles()) do
        local lines = readLines(path)
        if lines then
            for n, line in ipairs(lines) do
                if #line > 150 then
                    offenders[#offenders + 1] = path .. ":" .. n .. " (" .. #line .. " characters)"
                end
            end
        end
    end
    assert(#offenders == 0, "line over 150 characters in:\n  " .. table.concat(offenders, "\n  "))
end

function t.no_tab_characters()
    local offenders = {}
    for __, path in ipairs(findLuaFiles()) do
        local lines = readLines(path)
        if lines then
            for n, line in ipairs(lines) do
                if line:find("\t", 1, true) then
                    offenders[#offenders + 1] = path .. ":" .. n
                end
            end
        end
    end
    assert(#offenders == 0, "tab character in:\n  " .. table.concat(offenders, "\n  "))
end

return t
