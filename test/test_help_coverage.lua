-- "Every surface has help" (spec §12), enforced instead of remembered. Checks settings.lua and
-- help_topics.lua directly, plus a static text scan of gui/*.lua for the info-button convention.
local __ = require("fake_gui") -- installs api.gui for item 5's dynamic window build; return value unused
local settings = require("anujctrl/alnp/settings")
local topics = require("anujctrl/alnp/help_topics")
local t = {}

local topicsByKey = {}
for __, topic in ipairs(topics.list) do topicsByKey[topic.key] = topic end

-- Other tasks are writing gui/*.lua files right now; find() only ever lists what already exists,
-- so a file that has not landed yet is simply absent from the scan, not an error.
local function guiFiles()
    local files = {}
    local listing = assert(io.popen("find res/scripts/anujctrl/alnp/gui -name '*.lua'"))
    for path in listing:lines() do files[#files + 1] = path end
    listing:close()
    table.sort(files)
    return files
end

-- nil (not an error) for a file another task has not written yet, or a transient read race.
local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end

local function splitLines(text)
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = line end
    return lines
end

local function readLines(path)
    local text = readFile(path)
    return text and splitLines(text)
end

-- Every string literal key passed to help.button(, help.labelled(...,  or topics.get( across
-- every gui/*.lua file, as { key = key, where = "file:line: call text" }. help.labelled's own
-- label argument (usually `_("English text")`) is skipped over with `[^,]-` up to the first
-- comma; none of the label text passed to it today contains a comma of its own.
local function scanTopicKeyUses()
    local uses = {}
    for __, path in ipairs(guiFiles()) do
        local lines = readLines(path)
        if lines then
            for n, line in ipairs(lines) do
                for key in line:gmatch('help%.button%(%s*["\']([%w%.]+)["\']') do
                    uses[#uses + 1] = { key = key, where = path .. ":" .. n .. ": help.button(\"" .. key .. "\")" }
                end
                for key in line:gmatch('help%.labelled%([^,]-,%s*["\']([%w%.]+)["\']') do
                    uses[#uses + 1] = { key = key, where = path .. ":" .. n .. ": help.labelled(..., \"" .. key .. "\")" }
                end
                for key in line:gmatch('topics%.get%(%s*["\']([%w%.]+)["\']') do
                    uses[#uses + 1] = { key = key, where = path .. ":" .. n .. ": topics.get(\"" .. key .. "\")" }
                end
            end
        end
    end
    return uses
end

function t.every_schema_row_has_a_label_and_help()
    for __, row in ipairs(settings.schema) do
        assert(type(row.label) == "string" and row.label ~= "", "row " .. tostring(row.path) .. " needs a label")
        assert(type(row.help) == "string" and row.help ~= "", "row " .. tostring(row.path) .. " needs help")
    end
end

function t.every_section_has_a_label_and_help()
    for __, section in ipairs(settings.sections) do
        assert(type(section.label) == "string" and section.label ~= "", "section " .. tostring(section.key) .. " needs a label")
        assert(type(section.help) == "string" and section.help ~= "", "section " .. tostring(section.key) .. " needs help")
    end
end

function t.every_topic_has_a_title_and_text()
    for __, topic in ipairs(topics.list) do
        assert(type(topic.title) == "string" and topic.title ~= "", "topic " .. tostring(topic.key) .. " needs a title")
        assert(type(topic.text) == "string" and topic.text ~= "", "topic " .. tostring(topic.key) .. " needs text")
    end
end

function t.every_help_key_referenced_in_gui_files_is_a_known_topic()
    local offenders = {}
    for __, use in ipairs(scanTopicKeyUses()) do
        if not topicsByKey[use.key] then
            offenders[#offenders + 1] = use.where .. " -- no such topic in help_topics.lua"
        end
    end
    assert(#offenders == 0, "unknown help topic key referenced:\n  " .. table.concat(offenders, "\n  "))
end

-- Looser than scanTopicKeyUses: a topic key reaching help.button often passes through a small
-- local helper first (window.lua's buildTab, schema_form.lua's buildFooterButton, one call site
-- per tab/button rather than one help.button call each), so the literal key sits at the helper's
-- call site, not inside help.button( itself. "Used somewhere" only needs the key to appear as a
-- quoted literal anywhere in the scanned files, not adjacent to one specific function name.
local function collectAllQuotedLiterals()
    local found = {}
    for __, path in ipairs(guiFiles()) do
        local lines = readLines(path)
        if lines then
            for __, line in ipairs(lines) do
                for literal in line:gmatch('"([%w][%w%.]*)"') do found[literal] = true end
                for literal in line:gmatch("'([%w][%w%.]*)'") do found[literal] = true end
            end
        end
    end
    return found
end

function t.every_help_topic_is_referenced_at_least_once()
    local found = collectAllQuotedLiterals()
    local unused = {}
    for __, topic in ipairs(topics.list) do
        if not found[topic.key] then unused[#unused + 1] = topic.key end
    end
    assert(#unused == 0, "help topic(s) never referenced from gui/*.lua:\n  " .. table.concat(unused, "\n  "))
end

-- Spec §12 says the scan fires on a file that creates "a tab, a table header or a button"; a
-- table header is `Table.new` (the table itself) or `setHeader(` (attaching the header row).
-- CheckBox.new is deliberately not a trigger (controller ruling 1): schema_form.lua's per-type
-- editor builders (buildBoolEditor and friends) return a bare check box and their one shared
-- caller, buildRow, adds the info button once for every editor type -- the right shape, not a gap.
local WIDGET_TRIGGER_PATTERNS = { "Button%.new", "Table%.new", "setHeader%(", "TabWidget%.new", "addTab" }
-- A direct `topics.get(` lookup counts as a help call too (controller ruling 3): window.lua's
-- top-bar button is spec'd as "tooltip only" (§10.1) and gets its tooltip straight from a topic's
-- `.text` field via `help_topics.get(...)` rather than through an "i" button.
local HELP_CALL_PATTERNS = { "help%.button", "help%.buttonFor", "help%.labelled", "topics%.get%(" }
local FUNCTION_START_PATTERNS = { "^%s*local%s+function%s", "^%s*function%s", "=%s*function%s*%(" }
local EXEMPT_BASENAMES = { ["help.lua"] = true, ["sync.lua"] = true }

local function basename(path)
    return path:match("([^/]+)$") or path
end

local function containsAny(text, patterns)
    for __, pattern in ipairs(patterns) do
        if text:find(pattern) then return true end
    end
    return false
end

local function isCommentLine(line)
    return line:match("^%s*%-%-") ~= nil
end

-- One entry per source line that opens a function (named or `= function(`, but not an anonymous
-- callback passed straight as an argument, e.g. `checkbox:onToggle(function(v) ... end)`, which
-- matches none of the three start patterns and so stays part of its enclosing function). Each
-- chunk runs from its own start line up to (not including) the next function's start line, or the
-- end of the file for the last one -- which, naively, would also swallow whatever comment sits
-- between one function and the next, so comment lines are dropped before matching against them:
-- window.lua's own header comment for buildTab happens to say "...compound help.labelled()..."
-- while explaining why it is NOT used there, which would otherwise clear addTopBarButton by
-- accident.
local function functionChunks(lines)
    local starts = {}
    for n, line in ipairs(lines) do
        if containsAny(line, FUNCTION_START_PATTERNS) then starts[#starts + 1] = n end
    end
    local chunks = {}
    for i, startLine in ipairs(starts) do
        local endLine = (starts[i + 1] or (#lines + 1)) - 1
        local text = {}
        for n = startLine, endLine do
            if not isCommentLine(lines[n]) then text[#text + 1] = lines[n] end
        end
        chunks[#chunks + 1] = { startLine = startLine, text = table.concat(text, "\n") }
    end
    return chunks
end

-- Spec §10.1/§12: every button, table header and tab carries its own info button -- except a
-- table ROW builder (a function whose body calls `:addRow(`), which is covered by its own
-- table's column headers instead (controller ruling 2): exempt only when the same file also
-- builds that table's header with help (some function calling both `setHeader(` and
-- `help.labelled(`). A file with `:addRow(` but no such helped header is NOT exempt.
--
-- Takes raw source text rather than a path so it can be run against in-memory strings, not only
-- real files (see the self-test below). If a legitimate builder still fails this, the fix belongs
-- in that builder (move the info button into it), never in this test -- but this test does not
-- own any gui/*.lua file, so it only reports.
local function widgetHelpOffendersIn(fileName, sourceText)
    if EXEMPT_BASENAMES[basename(fileName)] then return {} end

    local chunks = functionChunks(splitLines(sourceText))

    local hasHelpedHeader = false
    for __, chunk in ipairs(chunks) do
        if chunk.text:find("setHeader%(") and chunk.text:find("help%.labelled%(") then
            hasHelpedHeader = true
            break
        end
    end

    local offenders = {}
    for __, chunk in ipairs(chunks) do
        local isRowBuilder = chunk.text:find(":addRow%(") ~= nil
        local exempt = isRowBuilder and hasHelpedHeader
        if not exempt and containsAny(chunk.text, WIDGET_TRIGGER_PATTERNS) and not containsAny(chunk.text, HELP_CALL_PATTERNS) then
            offenders[#offenders + 1] = fileName .. ":" .. chunk.startLine
        end
    end
    return offenders
end

function t.every_widget_builder_calls_a_help_function_in_the_same_function()
    local offenders = {}
    for __, path in ipairs(guiFiles()) do
        local source = readFile(path)
        if source then
            for __, offender in ipairs(widgetHelpOffendersIn(path, source)) do
                offenders[#offenders + 1] = offender
            end
        end
    end
    assert(#offenders == 0, "widget built without a help call in the same function:\n  " .. table.concat(offenders, "\n  "))
end

local function listContains(list, value)
    for __, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end

-- Guards against over-loosening rulings 1-3: proves widgetHelpOffendersIn still reports a genuine
-- violation, still exempts a row builder whose file has a properly-helped header, and still
-- reports a row builder whose file's header has no help of its own -- all against in-memory
-- source, never real files.
function t.widget_help_checker_still_catches_real_violations()
    local unhelpedButton = table.concat({
        "local function buildThing()",
        "    local button = api.gui.comp.Button.new(x, true)",
        "    return button",
        "end",
    }, "\n")
    local offenders = widgetHelpOffendersIn("probe.lua", unhelpedButton)
    assert(#offenders == 1, "expected exactly one offender for an unhelped Button.new, got " .. #offenders)
    assert(offenders[1] == "probe.lua:1", "expected the offender at probe.lua:1, got " .. tostring(offenders[1]))

    local helpedHeaderRowBuilder = table.concat({
        'local function buildHeader()',
        '    local headers = { help.labelled(_("Col"), "topic.key") }',
        '    tableWidget:setHeader(headers)',
        'end',
        '',
        'local function addRow(id)',
        '    local button = api.gui.comp.Button.new(x, true)',
        '    tableWidget:addRow({ button })',
        'end',
    }, "\n")
    offenders = widgetHelpOffendersIn("probe.lua", helpedHeaderRowBuilder)
    assert(#offenders == 0, "a row builder covered by a helped header must not be reported, got:\n  "
        .. table.concat(offenders, "\n  "))

    local unhelpedHeaderRowBuilder = table.concat({
        'local function buildHeader()',
        '    local headers = { api.gui.comp.TextView.new(_("Col")) }',
        '    tableWidget:setHeader(headers)',
        'end',
        '',
        'local function addRow(id)',
        '    local button = api.gui.comp.Button.new(x, true)',
        '    tableWidget:addRow({ button })',
        'end',
    }, "\n")
    offenders = widgetHelpOffendersIn("probe.lua", unhelpedHeaderRowBuilder)
    assert(listContains(offenders, "probe.lua:6"),
        "a row builder with no helped header must be reported, got:\n  " .. table.concat(offenders, "\n  "))
end

-- Fixed, schema-independent "i" buttons that exist exactly once regardless of how many settings
-- rows, sections or kinds there are: the window overview, the four tab headers, and the two
-- footer buttons ("Reset everything" on General, "Run API check" on Advanced).
local FIXED_TOPIC_COUNT = 7

-- window.lua exposes only init/setState/update (Part A); nothing hands back the built tree, so
-- counting is done by intercepting every Button built during window.init() instead of walking a
-- tree the test has no way to reach. Every info button is `Button.new(TextView.new("i"), true)`
-- (gui/help.lua's buildButton), so a Button whose label TextView's own constructor argument is
-- exactly "i" is counted; anything else (label widgets, "Reset section", etc.) is not.
function t.default_window_has_enough_info_buttons_for_full_help_coverage()
    local ok, window = pcall(require, "anujctrl/alnp/gui/window")
    if not ok then return end -- gui/window.lua not written yet: skip silently

    local formSectionKeys, formSectionCount = {}, 0
    for __, section in ipairs(settings.sections) do
        if section.tab == "general" or section.tab == "advanced" then
            formSectionKeys[section.key] = true
            formSectionCount = formSectionCount + 1
        end
    end
    local formRowCount = 0
    for __, row in ipairs(settings.schema) do
        if formSectionKeys[row.section] then formRowCount = formRowCount + 1 end
    end

    local iButtonCount = 0
    local originalNew = api.gui.comp.Button.new
    api.gui.comp.Button.new = function(...)
        local args = { ... }
        local label = args[1]
        local labelText = nil
        if type(label) == "table" then
            labelText = label.args and label.args[1]
        elseif type(label) == "string" then
            labelText = label
        end
        if labelText == "i" then iButtonCount = iButtonCount + 1 end
        return originalNew(...)
    end

    local function noopSend() end
    local ranOk, err = pcall(window.init, noopSend)
    api.gui.comp.Button.new = originalNew
    assert(ranOk, "window.init raised: " .. tostring(err))

    local expected = formRowCount + formSectionCount + FIXED_TOPIC_COUNT
    assert(iButtonCount >= expected,
        ('only %d "i" buttons, expected at least %d (%d schema rows + %d sections + %d fixed topics)')
            :format(iButtonCount, expected, formRowCount, formSectionCount, FIXED_TOPIC_COUNT))
end

return t
