-- Lines tab: a table of the player's lines with kind, current name, proposed name and lock
-- state. Reads the game only through `facts`; never renames anything itself -- it only sends
-- events through the `send` function it is given. GUI-only module: may call api.gui.
--
-- Building the tab reads no lines at all, so the window opens instantly even on a save with
-- hundreds of lines. All reading happens in small chunks inside update(), driven by "Preview all".
local facts = require "anujctrl/alnp/facts"
local classify = require "anujctrl/alnp/classify"
local propose = require "anujctrl/alnp/propose"
local tracker = require "anujctrl/alnp/tracker"
local kinds = require "anujctrl/alnp/kinds"
local help = require "anujctrl/alnp/gui/help"

local linesTab = {}

-- Replaceable so tests can control "once per second" behaviour without waiting on a real clock.
linesTab.clock = os.time

local state = nil
local send = nil

local tableWidget = nil
local statusView = nil
local rows = {}

local scanIds = nil    -- the ids being previewed, or nil when no scan is running
local scanIndex = 1    -- 1-based index of the next id in scanIds to read
local scanTotal = 0    -- #scanIds at the moment the scan started
local scanChanged = 0  -- rows that started ticked, counted as the scan proceeds
local scanTaken = nil  -- { [numberKey] = { [n] = true, ... } }, mutated as proposals are made
local scanWords = nil  -- tracker.defaultWords(state.settings, _("Line")), computed once per scan
local scanDecideView = nil -- state.settings seen with enabled = true, for tracker.decide (see addRow)

local everPreviewed = false
local lastRefreshAt = nil
local pendingRefresh = nil -- a state refresh() had to drop to the throttle, awaiting update()

local LOCK_LABEL = {
    player = "locked",
    edited = "locked: you edited the name",
    prefix = "locked: prefix",
}

local function lockLabelFor(lock)
    local key = lock and LOCK_LABEL[lock]
    if not key then return "" end
    return _(key)
end

local function scanningStatus(done, total)
    return (_("Reading lines... %d / %d")):format(done, total)
end

local function scanDoneStatus(total, changed)
    return (_("%d lines, %d would change")):format(total, changed)
end

-- Frees this line's own currently-recorded number in the shared taken map, so pickNumber can
-- keep it; the caller reserves whatever number the fresh proposal actually ends up with.
local function releaseOwnNumber(record, taken)
    if record and record.numberKey and record.number and taken[record.numberKey] then
        taken[record.numberKey][record.number] = nil
    end
end

local function reserveNumber(taken, key, n)
    if not key or not n then return end
    taken[key] = taken[key] or {}
    taken[key][n] = true
end

local function addRow(id, f, tbl)
    local record = state.records[id]
    local kind = classify.kind(f)

    releaseOwnNumber(record, scanTaken)
    local name, n, key = propose.name(f, record, tbl, scanTaken)
    reserveNumber(scanTaken, key, n)

    local lock = tracker.lockState(record, f.name, tbl)
    local hasProposal = name ~= nil
    -- decide() is asked with kindAutoRename = true and, through scanDecideView, enabled = true:
    -- the preview answers "may the mod touch this name", not "is automatic renaming switched on".
    -- Both switches only govern the engine's own passes; an explicit Apply works regardless, and
    -- the engine's apply handler does not consult `enabled` either.
    local checked = false
    if hasProposal and name ~= f.name and lock == nil then
        checked = tracker.decide(record, f.name, true, scanDecideView, scanWords) == "rename"
    end
    if checked then scanChanged = scanChanged + 1 end

    local applyBox = api.gui.comp.CheckBox.new("")
    applyBox:setSelected(checked, false)
    if not hasProposal then applyBox:setEnabled(false) end

    local kindView = api.gui.comp.TextView.new(_(kinds.label[kind]))
    local currentView = api.gui.comp.TextView.new(f.name)
    local proposedView = api.gui.comp.TextView.new(hasProposal and name or _("(left alone)"))
    local lockBox = api.gui.comp.CheckBox.new(lockLabelFor(lock))
    lockBox:setSelected(lock ~= nil, false)
    local renameButton = api.gui.comp.Button.new(api.gui.comp.TextView.new(_("Rename now")), true)

    -- nameAtPreview is what the proposal was computed against; the engine is told it with every
    -- apply item and refuses anything whose line has been renamed since (see engine handlers.apply).
    local row = {
        id = id, applyBox = applyBox, currentView = currentView, proposedView = proposedView,
        lockBox = lockBox, name = name, n = n, key = key, hasProposal = hasProposal, lock = lock,
        nameAtPreview = f.name, stale = false,
    }
    rows[#rows + 1] = row

    lockBox:onToggle(function(newValue)
        if newValue == false and (row.lock == "edited" or row.lock == "prefix") then
            row.lockBox:setSelected(true, false)
            statusView:setText(_("This lock clears by renaming the line, or by removing the lock "
                .. "prefix -- not by unticking it here."))
            return
        end
        row.lock = newValue and "player" or nil
        row.lockBox:setText(lockLabelFor(row.lock))
        send("lock", { line = id, locked = newValue })
    end)

    renameButton:onClick(function()
        send("renameNow", { line = id })
    end)

    tableWidget:addRow({ applyBox, kindView, currentView, proposedView, lockBox, renameButton })
end

local function startScan()
    -- The GUI thread holds its own copy of facts.lua, and so its own industry cache; the engine's
    -- clearCache() calls never reach it. "Preview all" is the one place that can go stale, so it
    -- starts from nothing rather than from whatever the first preview of the session saw.
    facts.clearCache()
    scanIds = facts.playerLines()
    scanIndex = 1
    scanTotal = #scanIds
    scanChanged = 0
    scanTaken = propose.takenByKey(state.records, nil)
    scanWords = tracker.defaultWords(state.settings, _("Line"))
    scanDecideView = setmetatable({ enabled = true }, { __index = state.settings })
    pendingRefresh = nil -- these rows are built from live facts; a dropped refresh has nothing to add
    tableWidget:deleteAll()
    rows = {}
    everPreviewed = true
    statusView:setText(scanningStatus(0, scanTotal))
end

local function applyChecked()
    local renames = {}
    local checkedRows = {}
    for __, row in ipairs(rows) do
        if row.hasProposal and not row.stale and row.applyBox:isSelected() then
            renames[#renames + 1] = { line = row.id, name = row.name, from = row.nameAtPreview,
                n = row.n, key = row.key }
            checkedRows[#checkedRows + 1] = row
        end
    end
    if #renames == 0 then
        statusView:setText(_("Nothing is ticked to apply."))
        return
    end
    send("apply", { renames = renames })
    for __, row in ipairs(checkedRows) do
        row.applyBox:setSelected(false, false)
    end
    statusView:setText((_("Applied %d line(s).")):format(#renames))
end

function linesTab.build(newState, newSend)
    linesTab.reset()
    state = newState
    send = newSend

    local outer = api.gui.layout.BoxLayout.new("VERTICAL")

    local buttonsLayout = api.gui.layout.BoxLayout.new("HORIZONTAL")
    local previewButton = api.gui.comp.Button.new(api.gui.comp.TextView.new(_("Preview all")), true)
    buttonsLayout:addItem(previewButton)
    buttonsLayout:addItem(help.button("lines.previewAll"))
    local applyButton = api.gui.comp.Button.new(api.gui.comp.TextView.new(_("Apply checked")), true)
    buttonsLayout:addItem(applyButton)
    buttonsLayout:addItem(help.button("lines.applyChecked"))
    statusView = api.gui.comp.TextView.new("")
    buttonsLayout:addItem(statusView)

    local buttonsComponent = api.gui.comp.Component.new("alnpLinesButtons")
    buttonsComponent:setLayout(buttonsLayout)
    outer:addItem(buttonsComponent)

    local headers = {
        help.labelled(_("Apply"), "lines.col.apply"),
        help.labelled(_("Kind"), "lines.col.kind"),
        help.labelled(_("Current name"), "lines.col.current"),
        help.labelled(_("Proposed name"), "lines.col.proposed"),
        help.labelled(_("Lock"), "lines.col.lock"),
        help.labelled(_("Rename now"), "lines.col.renameNow"),
    }
    tableWidget = api.gui.comp.Table.new(6, "NONE")
    tableWidget:setHeader(headers)

    local placeholder = api.gui.comp.Component.new(" ")
    local scrollArea = api.gui.comp.ScrollArea.new(placeholder, " ")
    scrollArea:setContent(tableWidget)
    -- Caps the table's height inside the 900x600 window (window.lua), leaving room for the button
    -- row, the tab strip and the docked help panel; comp.Component:setMaximumSize is documented,
    -- and is how the bus line tool sizes its own scroll area.
    scrollArea:setMaximumSize(api.gui.util.Size.new(860, 380))
    outer:addItem(scrollArea)

    previewButton:onClick(startScan)
    applyButton:onClick(applyChecked)

    local component = api.gui.comp.Component.new("alnpLinesTab")
    component:setLayout(outer)
    return component
end

local function applyRefresh()
    local tbl = state.settings
    for __, row in ipairs(rows) do
        local currentName = facts.name(row.id)
        row.currentView:setText(currentName)
        local lock = tracker.lockState(state.records[row.id], currentName, tbl)
        row.lock = lock
        row.lockBox:setText(lockLabelFor(lock))
        row.lockBox:setSelected(lock ~= nil, false)
        -- The proposal was computed against a name (and an unlocked state) that no longer holds,
        -- so this row is stale: it is untickable until the player previews again. Staleness never
        -- clears on its own -- a name that changed back is still a name the mod did not propose for.
        if not row.stale and (currentName ~= row.nameAtPreview or lock ~= nil) then
            row.stale = true
            row.applyBox:setSelected(false, false)
            row.proposedView:setText(_("(name changed: preview again)"))
        end
    end
end

-- window.lua records a version as refreshed before it calls us, so a state the throttle drops is
-- never offered again: it is kept here and applied by the next update() once the second is up.
function linesTab.refresh(newState)
    state = newState
    if not everPreviewed then return end
    local now = linesTab.clock()
    if lastRefreshAt and (now - lastRefreshAt) < 1 then
        pendingRefresh = newState
        return
    end
    pendingRefresh = nil
    lastRefreshAt = now
    applyRefresh()
end

function linesTab.update()
    if pendingRefresh then
        local now = linesTab.clock()
        if not lastRefreshAt or (now - lastRefreshAt) >= 1 then
            state = pendingRefresh
            pendingRefresh = nil
            lastRefreshAt = now
            applyRefresh()
        end
    end
    if not scanIds then return end
    local tbl = state.settings
    local budget = tbl.preview.linesPerFrame
    local processed = 0
    while scanIndex <= scanTotal and processed < budget do
        local id = scanIds[scanIndex]
        scanIndex = scanIndex + 1
        processed = processed + 1
        local f = facts.forLine(id, tbl)
        if f then addRow(id, f, tbl) end
    end
    if scanIndex > scanTotal then
        statusView:setText(scanDoneStatus(scanTotal, scanChanged))
        scanIds = nil
        scanTaken = nil
        scanWords = nil
        scanDecideView = nil
    else
        statusView:setText(scanningStatus(scanIndex - 1, scanTotal))
    end
end

function linesTab.reset()
    state = nil
    send = nil
    tableWidget = nil
    statusView = nil
    rows = {}
    scanIds = nil
    scanIndex = 1
    scanTotal = 0
    scanChanged = 0
    scanTaken = nil
    scanWords = nil
    scanDecideView = nil
    everPreviewed = false
    lastRefreshAt = nil
    pendingRefresh = nil
    linesTab.clock = os.time
end

return linesTab
