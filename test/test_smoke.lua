-- End-to-end smoke test: loads the real game script file with dofile and drives its data() table
-- (load/save/update/handleEvent/guiInit/guiUpdate) against fake_game + fake_gui, exactly as the
-- game would call it, so a wiring mistake between any two real modules shows up here even though
-- every module's own unit tests pass.
local fakeGame = require("fake_game")
local fakeGui = require("fake_gui")
local eq = require("fake_api").eq
local facts = require("anujctrl/alnp/facts")
local engine = require("anujctrl/alnp/engine")
local log = require("anujctrl/alnp/log")

local t = {}

local GAME_SCRIPT = "res/config/game_script/auto_line_namer_plus.lua"

-- Routes api.cmd exactly as the real game would: setName commands rename the fake world,
-- sendScriptEvent commands are delivered back into the script's own handleEvent(file, id, name,
-- param) -- synchronously, since this fake has no "next frame" to wait for.
local function installCmd(world, scriptData)
    local sent = {}
    api.cmd = {
        make = {
            setName = function(id, name) return { op = "setName", id = id, name = name } end,
            sendScriptEvent = function(fileName, id, name, param)
                return { op = "sendScriptEvent", fileName = fileName, id = id, name = name, param = param }
            end,
        },
        sendCommand = function(cmd)
            sent[#sent + 1] = cmd
            if cmd.op == "setName" then
                world.renameLine(cmd.id, cmd.name)
            elseif cmd.op == "sendScriptEvent" then
                scriptData.handleEvent(cmd.fileName, cmd.id, cmd.name, cmd.param)
            end
        end,
    }
    return sent
end

local function busWorld()
    return fakeGame.world({
        towns = { [900] = "Springfield", [901] = "Shelbyville" },
        stationGroups = {
            [11] = { name = "Springfield Central", station = 111, town = 900, position = { 0, 0, 0 } },
            [12] = { name = "Shelbyville East", station = 112, town = 901, position = { 500, 0, 0 } },
        },
        vehicles = { [501] = { capacities = { PASSENGERS = 40 } } },
        lines = { [1] = { name = "Line 1", stops = { 11, 12 }, modes = { "BUS" }, vehicles = { 501 } } },
        player = 1,
    })
end

-- 1. a whole session: boot, an automatic rename, a settings change and a manual apply. -----------

function t.whole_session_boots_renames_and_applies_from_the_gui()
    log.reset()
    log.sink = function() end -- the mod's own logging is not under test here

    local world = busWorld()
    dofile(GAME_SCRIPT)
    local scriptData = data()
    local sent = installCmd(world, scriptData)

    scriptData.load(nil)
    local getWindow = fakeGui.captureNew("comp.Window")
    scriptData.guiInit()

    -- Settle instantly, so the tick right below can rename on its very first pass.
    scriptData.handleEvent("file", "alnp", "set", { path = "scan.settleSeconds", value = 0 })

    eq(facts.name(1), "Line 1")
    scriptData.update()
    assert(facts.name(1) ~= "Line 1", "the default-named line should have been renamed")
    assert(#sent >= 1 and sent[1].op == "setName", "a setName command should have been sent")

    -- The engine's save() -> GUI's load() -> guiUpdate() channel: must not raise while hidden.
    local saved = scriptData.save()
    scriptData.load(saved)
    scriptData.guiUpdate()

    -- Click the top-bar button to show the window.
    local gameInfo = api.gui.util.getById("gameInfo")
    local topBarButton = fakeGui.find(gameInfo, function(w) return w.class == "comp.Button" end)
    assert(topBarButton, "guiInit should have added the top-bar button")
    fakeGui.click(topBarButton)
    local windowWidget = getWindow()
    eq(windowWidget:isVisible(), true)

    -- Toggle a General-tab setting from the GUI and confirm the engine's own saved settings moved.
    eq(engine.save().settings.enabled, true)
    local enabledRow = fakeGui.find(windowWidget, function(w)
        return w.class == "comp.Component" and fakeGui.text(w) == "alnpRow:enabled"
    end)
    assert(enabledRow, "should find the Enabled row")
    local enabledCheckbox = fakeGui.find(enabledRow, function(w) return w.class == "comp.CheckBox" end)
    assert(enabledCheckbox, "should find the Enabled row's checkbox")
    enabledCheckbox:setSelected(false, true)
    eq(engine.save().settings.enabled, false)

    -- Simulate the line getting a fresh default name (e.g. after a "reload"), then use the Lines
    -- tab to preview and apply a rename entirely from the GUI side.
    world.renameLine(1, "Line 5")

    local function buttonLabelled(text)
        local label = fakeGui.find(windowWidget, function(w) return w.class == "comp.TextView" and fakeGui.text(w) == text end)
        assert(label, "missing label " .. text)
        return fakeGui.find(windowWidget, function(w) return w.class == "comp.Button" and w.children[1] == label end)
    end

    local previewButton = buttonLabelled("Preview all")
    assert(previewButton, "should find the Preview all button")
    fakeGui.click(previewButton)
    scriptData.guiUpdate() -- chunked preview: one line easily fits in one frame's budget

    local applyButton = buttonLabelled("Apply checked")
    assert(applyButton, "should find the Apply checked button")
    fakeGui.click(applyButton)

    assert(facts.name(1) ~= "Line 5", "the manually applied line should have been renamed")
end

-- 1b (A1). The headline promise, end to end through the real game script: a name the player
-- typed after the preview is never overwritten by "Apply checked". Returns facts.name(1).
local function previewThenHandRenameThenApply(autoRename)
    log.reset()
    log.sink = function() end

    local world = busWorld()
    dofile(GAME_SCRIPT)
    local scriptData = data()
    installCmd(world, scriptData)

    scriptData.load(nil)
    -- Both settings are changed BEFORE the window exists, and the resulting state is handed to the
    -- GUI thread before guiInit, so that from here on only the story's own events move the version.
    scriptData.handleEvent("file", "alnp", "set", { path = "kinds.bus.autoRename", value = autoRename })
    scriptData.handleEvent("file", "alnp", "set", { path = "scan.settleSeconds", value = 0 })
    scriptData.load(scriptData.save())

    local getWindow = fakeGui.captureNew("comp.Window")
    scriptData.guiInit()

    local gameInfo = api.gui.util.getById("gameInfo")
    fakeGui.click(fakeGui.find(gameInfo, function(w) return w.class == "comp.Button" end))
    local windowWidget = getWindow()

    local function buttonLabelled(text)
        local label = fakeGui.find(windowWidget, function(w)
            return w.class == "comp.TextView" and fakeGui.text(w) == text
        end)
        assert(label, "missing label " .. text)
        return fakeGui.find(windowWidget, function(w) return w.class == "comp.Button" and w.children[1] == label end)
    end

    -- Preview while the line still has its default name: its row starts ticked.
    fakeGui.click(buttonLabelled("Preview all"))
    scriptData.guiUpdate()

    -- The player renames the line by hand, and the engine gets a chance to notice (settle = 0).
    -- With autoRename on it auto-locks the line (a version bump the GUI will see); with it off
    -- the engine decides "skip", nothing bumps the version and the GUI is never told anything.
    world.renameLine(1, "Airport Express")
    scriptData.update()

    -- The engine's save reaches the GUI thread, then a frame, then the player clicks Apply.
    scriptData.load(scriptData.save())
    scriptData.guiUpdate()
    local tableWidget = fakeGui.find(windowWidget, function(w) return w.class == "comp.Table" end)
    local stillTicked = tableWidget.rows[1][1]:isSelected()
    fakeGui.click(buttonLabelled("Apply checked"))
    return facts.name(1), stillTicked
end

function t.a_hand_written_name_survives_apply_checked()
    local name, stillTicked = previewThenHandRenameThenApply(true)
    eq(name, "Airport Express", "the name the player typed after the preview must survive Apply checked")
    eq(stillTicked, false, "the refresh that saw the auto-lock must have unticked the row")
end

-- The nastier variant: with auto-rename off for this kind the engine never auto-locks, so nothing
-- bumps the version and the GUI is never refreshed -- the row is still ticked and still shows the
-- stale proposal. Only the engine's own `from` check stops the overwrite.
function t.a_hand_written_name_survives_apply_checked_with_auto_rename_off()
    eq(previewThenHandRenameThenApply(false), "Airport Express",
        "the engine-side check must save the hand-written name even with no GUI refresh")
end

-- 2. an error inside engine.tick (via a broken facts.playerLines) is logged once and update()
-- itself never raises -- log.guard must be doing its job for the real, wired-up entry point. ------

function t.error_inside_tick_is_logged_once_and_update_does_not_raise()
    log.reset()
    local logLines = {}
    log.sink = function(line) logLines[#logLines + 1] = line end

    busWorld()
    dofile(GAME_SCRIPT)
    local scriptData = data()
    installCmd({ renameLine = function() end }, scriptData)

    scriptData.load(nil)
    local realPlayerLines = facts.playerLines
    facts.playerLines = function() error("boom: facts.playerLines is broken") end

    -- Same call site both times, so the two tracebacks are byte-identical and log.lua's own
    -- duplicate-suppression (its reason to exist: a broken callback must not flood the log) kicks in.
    local allOk = true
    for __ = 1, 2 do
        local ok = pcall(scriptData.update)
        allOk = allOk and ok
    end
    facts.playerLines = realPlayerLines

    assert(allOk, "update() must not raise even when engine.tick errors, on either call")
    eq(#logLines, 1)
    assert(logLines[1]:find("boom", 1, true), "the logged line should mention the underlying error")
end

return t
