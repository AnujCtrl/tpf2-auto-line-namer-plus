-- Static guards over every file the mod ships: `_` shadowing, the layering rules, and syntax
-- outside the Lua 5.1/5.2 common subset -- the target, since the game embeds 5.2.2, not 5.1 (see
-- the task brief) -- are only ever revealed by the game at runtime, so they are checked here as
-- plain text.
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

-- Scans one line as code, given whether a level-0 `[[ ... ]]` long-bracket string is already open
-- from an earlier line (false for a line taken on its own -- see codeOnly() below). Returns the
-- line's code-only text and whether a long string is still open at the end of the line, so
-- codeLines() can carry that into the next one.
--
-- Outside a long string: a quoted string span ("..." or '...', honouring backslash escapes so
-- `"say \"hi\" // x"` stays one span) is dropped entirely, then a trailing `-- ...` line comment
-- is dropped, and a `[[` that opens a long string switches into it -- handling one that opens and
-- closes again on the very same line, and real code that follows the close, in the same pass.
-- Inside a long string, everything up to and including its closing `]]` is dropped, so a syntax
-- mention there -- a URL, a help example, the English word "goto" -- is invisible to every
-- pattern check below (this is what mod.lua's `description = _([[ ... ]])` needs: F1 alone only
-- stripped a QUOTED string on ONE line, and could not see this one open across several).
--
-- Level-0 brackets only: an `[=[ ... ]=]` long-bracket level is scanned as ordinary characters
-- (not given long-string treatment -- but that is safe, since `[=[`/`]=]` cannot be mistaken for
-- real code either), and a `--[[ ... ]]` block comment is not specially recognised. Neither
-- appears anywhere in this codebase today.
local function scanLine(line, insideLongString)
    local out = {}
    local i, n = 1, #line
    while i <= n do
        if insideLongString then
            if line:sub(i, i + 1) == "]]" then
                insideLongString = false
                i = i + 2
            else
                i = i + 1
            end
        elseif line:sub(i, i + 1) == "--" then
            break
        elseif line:sub(i, i + 1) == "[[" then
            insideLongString = true
            i = i + 2
        else
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
    end
    return table.concat(out), insideLongString
end

-- Reduces a single, isolated line to just its code (see scanLine()). A `[[` opened on this line
-- without a matching `]]` is invisible to whatever comes after it -- callers that need to see a
-- long string spanning several lines, i.e. everyone scanning a real file, use codeLines() below
-- instead, never this directly.
local function codeOnly(line)
    return (scanLine(line, false))
end

-- Reduces a whole file's lines to their code-only text in one pass (see scanLine()), carrying a
-- level-0 `[[ ... ]]` long string's open/closed state from one line to the next. Every syntax and
-- layering rule below reads a file through this, not codeOnly() line by line, so a long string
-- that opens on one line and closes on a later one -- exactly mod.lua's description -- cannot
-- leak a banned-looking word into any of them.
local function codeLines(lines)
    local out = {}
    local insideLongString = false
    for n, line in ipairs(lines) do
        out[n], insideLongString = scanLine(line, insideLongString)
    end
    return out
end

-- Reads `path` and returns its lines paired with their per-file code-only text (see codeLines()
-- above), so every syntax and layering rule shares one long-string-aware pass instead of scanning
-- each line in isolation. Returns nil, nil for a file another task has not written yet.
local function readCodeLines(path)
    local lines = readLines(path)
    if not lines then return nil, nil end
    return lines, codeLines(lines)
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

function t.codeLines_tracks_a_long_string_open_across_several_lines()
    local code = codeLines({
        "description = _([[",
        "visit https://example.org // and goto settings, api.engine.x()",
        "]]),",
    })
    assert(code[2] == "", "expected no code text inside the long string, got " .. ("%q"):format(code[2]))
    assert(code[3] == "),", "expected the code after the closing ]] on its own line, got " .. ("%q"):format(code[3]))

    local oneLiner = codeLines({ "[[ x ]] .. y // 2" })
    assert(oneLiner[1]:find("//", 1, true), "a real // after an open-and-close [[ ]] on one line must still be seen")
end

-- Regression, against the real file rather than an in-memory probe: mod.lua's own description is
-- exactly this shape (`description = _([[ ... multi-line text ... ]]),`). Finds the open/close
-- lines by their literal text and asserts every line strictly between them -- never the open or
-- close line itself, since both also carry real code -- produces no code text at all.
function t.codeLines_hides_mod_lua_description_from_every_rule()
    local lines = assert(readLines("mod.lua"), "mod.lua must exist")
    local code = codeLines(lines)
    local openLine, closeLine
    for n, line in ipairs(lines) do
        if line:find("_([[", 1, true) then openLine = n end
        if line:find("]])", 1, true) then closeLine = closeLine or n end
    end
    assert(openLine and closeLine and openLine < closeLine, "could not locate mod.lua's description string")
    for n = openLine + 1, closeLine - 1 do
        assert(code[n] == "", "expected no code text on mod.lua:" .. n .. ", got " .. ("%q"):format(code[n]))
    end
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
-- Known, accepted limitation: this is checked one line at a time (via codeLines(), so it is at
-- least immune to a string or a comment spanning a `[[ ... ]]` long string), so a function
-- declaration whose OWN parameter list spans several lines -- `local function foo(\n    _, x)` --
-- is not detected: the bare `_` never lands on the same line as the word `function`. Nothing in
-- res/ is written that way today (every real declaration keeps its parameter list on one line),
-- so this is a documented gap, not a fix made here.
local function shadowsUnderscore(code)
    if code:match("for%s+_%s*[,i]") then return true end
    if code:match("^%s*local%s+_%s*[,=]") then return true end
    local params = code:match("function%s*[%w_.:]*%s*%(([^)]*)%)")
    return params ~= nil and params:match("%f[%w_]_%f[^%w_]") ~= nil
end

function t.underscore_never_shadows_the_translator()
    local offenders = {}
    for __, path in ipairs(findLuaFiles()) do
        local lines, code = readCodeLines(path)
        if lines then
            for n, line in ipairs(lines) do
                if shadowsUnderscore(code[n]) then
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
-- codeLines()) only of files for which `allowed(path)` is true; every other occurrence is an
-- offender. A mention inside a string, a comment, or a `[[ ... ]]` long string spanning several
-- lines (e.g. a description) is not a call, so it is not checked at all.
local function checkRestrictedTo(needle, allowed, label)
    local offenders = {}
    for __, path in ipairs(findLuaFiles()) do
        if not allowed(path) then
            local lines, code = readCodeLines(path)
            if lines then
                for n, line in ipairs(lines) do
                    if code[n]:find(needle, 1, true) then
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

-- Spec §11: every widget event registered under gui/ must run under log.guard, or an error inside
-- one reaches the game instead of being logged. `code` is one line already reduced to code-only
-- text (see codeLines()); a handler registration only ever recognised there, so a mention of
-- ":onClick(" inside a string or a comment can never trip this.
-- Matched by shape, not by a list of names: the game's widgets expose dozens of events (onEnter,
-- onCancel, onDestroy, onStep, onVisibilityChange, onSelect, onScroll, onMove, onCurrentChanged,
-- ...), and any fixed list silently stops covering the ones added to a tab later.
local HANDLER_PATTERNS = {
    ":on%u[%w_]*%s*%(",
    -- Not a widget event, but the game runs the callback on a later frame, outside guiInit's guard.
    ":invokeLater%s*%(",
}

local function registersUnwrappedHandler(code)
    for __, pattern in ipairs(HANDLER_PATTERNS) do
        if code:find(pattern) then
            return not code:find("log.wrap(", 1, true)
        end
    end
    return false
end

function t.every_gui_handler_registration_is_wrapped_in_log_wrap()
    local offenders = {}
    for __, path in ipairs(findLuaFiles()) do
        if isUnderGui(path) then
            local lines, code = readCodeLines(path)
            if lines then
                for n, line in ipairs(lines) do
                    if registersUnwrappedHandler(code[n]) then
                        offenders[#offenders + 1] = path .. ":" .. n .. ": " .. line:gsub("^%s+", "")
                    end
                end
            end
        end
    end
    assert(#offenders == 0, "gui handler registered without log.wrap(...) on the same line:\n  "
        .. table.concat(offenders, "\n  "))
end

function t.handler_registration_checker_catches_unwrapped_and_passes_wrapped()
    local mustReport = {
        "checkbox:onToggle(function(v) send(v) end)",
        "button:onClick(handler)",
        "field:onChange(function(text) end)",
        -- Y8: the docs expose far more events than any fixed list keeps up with, so the rule
        -- matches the shape of a registration instead of a list of names.
        "widget:onEnter(handler)",
        "widget:onCancel(handler)",
        "widget:onDestroy(handler)",
        "widget:onStep(handler)",
        "widget:onVisibilityChange(handler)",
        "widget:onSelect(handler)",
        "widget:onScroll(handler)",
        "widget:onMove(handler)",
        "widget:onCurrentChanged(handler)",
        "api.gui.util.getGameUI():invokeLater(handler)",
    }
    for __, line in ipairs(mustReport) do
        assert(registersUnwrappedHandler(codeOnly(line)), "expected to catch: " .. line)
    end

    local mustNotReport = {
        'checkbox:onToggle(log.wrap("x", function(v) send(v) end))',
        'button:onClick(log.wrap("y", handler))',
        'widget:onVisibilityChange(log.wrap("z", handler))',
        'getGameUI():invokeLater(log.wrap("w", handler))',
        "layout:addItem(x)",
        -- Not registrations: a lowercase method, and a plain call to something merely named on...
        "table:onlyLooksLikeAnEvent(x)",
        "self:setVisible(true)",
        "onClick(handler)",
    }
    for __, line in ipairs(mustNotReport) do
        assert(not registersUnwrappedHandler(codeOnly(line)), "expected NOT to catch: " .. line)
    end
end

-- Collects every line whose CODE (see codeLines()) matches `pattern`, across every listed file, as
-- file:line offender strings. `pattern` is a Lua pattern (not a plain substring); a false
-- positive from a comment, a string, or a `[[ ... ]]` long string spanning several lines that
-- merely mentions the banned syntax is impossible by construction (codeLines already removed
-- it), so a real false positive here would mean tightening the pattern itself, not editing
-- whatever file it fired on.
local function collectPatternOffenders(pattern)
    local offenders = {}
    for __, path in ipairs(findLuaFiles()) do
        local lines, code = readCodeLines(path)
        if lines then
            for n, line in ipairs(lines) do
                if code[n]:match(pattern) then
                    offenders[#offenders + 1] = path .. ":" .. n .. ": " .. line:gsub("^%s+", "")
                end
            end
        end
    end
    return offenders
end

-- The rules from here down reject syntax newer than Lua 5.1 (the target is the common subset of
-- 5.1 and 5.2: the game embeds 5.2.2, and the tests also run under 5.1 and luajit -- see the task
-- brief), not merely "5.1-only" syntax; `goto` in particular is a Lua 5.2 addition that 5.1 lacks,
-- so it stays banned even though the game's own interpreter would accept it.
function t.no_goto_statement()
    local offenders = collectPatternOffenders("%f[%a]goto%s+%a")
    assert(#offenders == 0, "`goto` used in:\n  " .. table.concat(offenders, "\n  "))
end

function t.no_integer_division_operator()
    local offenders = collectPatternOffenders("//")
    assert(#offenders == 0, "`//` used in:\n  " .. table.concat(offenders, "\n  "))
end

-- Shipped code must not call unpack at all. Transport Fever 2's own res/scripts/init.lua replaces
-- table.unpack with `function(t) ... return oldunpack(t) end`, which DROPS the (i, j) arguments,
-- and the game has no global `unpack`. `table.unpack(results, 2)` therefore returned everything
-- from index 1 in the game (and only there), which made log.guard return xpcall's `true` instead of
-- the guarded function's result (2026-09-19: state never saved, window impossible to close). Pass
-- arguments positionally and return results as varargs instead.
local function callsUnpack(code)
    return code:find("%f[%w_]unpack%s*%(") ~= nil or code:find("unpack%s+or%s", 1) ~= nil
end

function t.shipped_code_never_calls_unpack()
    local offenders = {}
    for __, path in ipairs(findLuaFiles()) do
        local lines, code = readCodeLines(path)
        if lines then
            for n, line in ipairs(lines) do
                if callsUnpack(code[n]) then
                    offenders[#offenders + 1] = path .. ":" .. n .. ": " .. line:gsub("^%s+", "")
                end
            end
        end
    end
    assert(#offenders == 0, "unpack is not trustworthy in the game (init.lua drops its i, j):\n  "
        .. table.concat(offenders, "\n  "))
end

function t.unpack_checker_catches_every_spelling_and_passes_clean_code()
    assert(callsUnpack("return table.unpack(results, 2)"), "table.unpack(")
    assert(callsUnpack("return (unpack or table.unpack)(results, 2)"), "the old fallback spelling")
    assert(callsUnpack("local a, b = unpack (t)"), "global unpack with a space")
    assert(not callsUnpack("local unpacked = repack(t)"), "an identifier merely containing the word")
    assert(not callsUnpack("return finish(label, xpcall(f, debug.traceback))"), "clean code")
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

-- The other direction: Lua 5.2 REMOVED these 5.1 functions outright (`strings TransportFever2`
-- shows the game embeds 5.2.2, not 5.1 -- see the task brief), so calling any of them would work
-- under the 5.1/luajit test run but raise "attempt to call a nil value" in the actual game.
local REMOVED_IN_LUA_52 = { "setfenv(", "getfenv(", "loadstring(", "table.getn(", "table.maxn(" }

local function usesFunctionRemovedInLua52(code)
    for __, needle in ipairs(REMOVED_IN_LUA_52) do
        if code:find(needle, 1, true) then return true end
    end
    return false
end

function t.no_function_removed_in_lua_52()
    local offenders = {}
    for __, path in ipairs(findLuaFiles()) do
        local lines, code = readCodeLines(path)
        if lines then
            for n, line in ipairs(lines) do
                if usesFunctionRemovedInLua52(code[n]) then
                    offenders[#offenders + 1] = path .. ":" .. n .. ": " .. line:gsub("^%s+", "")
                end
            end
        end
    end
    assert(#offenders == 0, "a function Lua 5.2 removed used in:\n  " .. table.concat(offenders, "\n  "))
end

function t.function_removed_in_52_checker_catches_each_one_and_passes_clean_code()
    local mustReport = {
        "setfenv(1, env)",
        "local e = getfenv(f)",
        "local chunk = loadstring(code)",
        "local n = table.getn(t)",
        "local n = table.maxn(t)",
    }
    for __, line in ipairs(mustReport) do
        assert(usesFunctionRemovedInLua52(codeOnly(line)), "expected to catch: " .. line)
    end

    local mustNotReport = {
        "local n = #t",
        "local chunk = load(code)",
        'local text = "setfenv(1, env)"', -- inside a string: codeOnly already stripped it
    }
    for __, line in ipairs(mustNotReport) do
        assert(not usesFunctionRemovedInLua52(codeOnly(line)), "expected NOT to catch: " .. line)
    end
end

-- Lua 5.2 also removed the 5.1 `module(...)` declaration statement outright. Only a bare call at
-- the start of a statement is that declaration -- never a method call on some other table
-- (`ns.module(...)`) and never a use of an identifier that merely contains the word
-- (`mymodule(...)`, `modules[1]`) -- so the pattern anchors to the start of the (code-only) line.
local function isBareModuleCall(code)
    return code:match("^%s*module%s*%(") ~= nil
end

function t.no_bare_module_call()
    local offenders = collectPatternOffenders("^%s*module%s*%(")
    assert(#offenders == 0, "a bare `module(...)` declaration used in:\n  " .. table.concat(offenders, "\n  "))
end

function t.bare_module_call_checker_catches_the_51_declaration_and_passes_everything_else()
    local mustReport = {
        'module("mymod", package.seeall)',
        "    module(...)",
    }
    for __, line in ipairs(mustReport) do
        assert(isBareModuleCall(codeOnly(line)), "expected to catch: " .. line)
    end

    local mustNotReport = {
        "ns.module(x)",
        'local mymodule = require("mymodule")',
        "modules[1] = foo",
        "local module = 5",
    }
    for __, line in ipairs(mustNotReport) do
        assert(not isBareModuleCall(codeOnly(line)), "expected NOT to catch: " .. line)
    end
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
