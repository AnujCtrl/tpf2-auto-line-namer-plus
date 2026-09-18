-- Engine tests: locks, reload names, and line-number lifecycle (cases 9-12 of task 9).
-- See .superpowers/sdd/2026-09-18-auto-line-namer-plus/engine-tests-instructions.md
local H = require("engine_helpers")
local eq = H.fake.eq
local t = {}

function t.case09_reload_name_renames_even_when_locked_edited()
    local world = H.world({ [1] = H.busLine("r") })
    local sent = H.installCmd(world)
    local engine = H.freshEngine(H.saved({}, { [1] = { locked = "edited" } }))
    H.tickRange(engine, 100, 105)
    eq(sent[1], { id = 1, name = "Bus Springfield – Shelbyville" })
    eq(engine.save().records[1].locked, nil)
end

function t.case10_lock_event_then_unlock_makes_eligible_again()
    local world = H.world({ [1] = H.busLine("Line 1") })
    local sent = H.installCmd(world)
    local engine = H.freshEngine(H.saved({ ["scan.settleSeconds"] = 0 }))
    engine.handleEvent("lock", { line = 1, locked = true })
    engine.tick(os.time() + 1)
    eq(#sent, 0)
    eq(engine.save().records[1].locked, "player")
    engine.handleEvent("lock", { line = 1, locked = false })
    engine.tick(os.time() + 2)
    eq(sent[1], { id = 1, name = "Bus Springfield – Shelbyville" })
    eq(engine.save().records[1].locked, nil)
end

-- Line 3 starts with no stops, so the engine ignores it until world.setStops gives it some.
function t.case11_freed_number_is_reused_by_a_new_line()
    local world = H.world({
        [1] = H.busLine("Line 1"),
        [2] = H.busLine("Line 2"),
        [3] = { name = "", stops = {}, modes = { "BUS" }, vehicles = { 501 } },
    })
    local sent = H.installCmd(world)
    local engine = H.freshEngine(nil)
    H.tickRange(engine, 100, 112)
    eq(sent[1], { id = 2, name = "Bus Springfield – Shelbyville" })
    eq(sent[2], { id = 1, name = "Bus Springfield – Shelbyville 2" })
    eq(engine.save().records[2].number, 1)
    world.removeLine(2)
    world.setStops(3, { 11, 12 })
    H.tickRange(engine, 113, 125)
    eq(sent[3], { id = 3, name = "Bus Springfield – Shelbyville" })
    eq(engine.save().records[3].number, 1)
end

function t.case12_removed_line_record_disappears_after_queue_refill()
    local world = H.world({ [1] = H.busLine("Line 1") })
    local sent = H.installCmd(world)
    local engine = H.freshEngine(nil)
    H.tickRange(engine, 100, 105)
    eq(sent[1], { id = 1, name = "Bus Springfield – Shelbyville" })
    eq(engine.save().records[1].lastAssigned, "Bus Springfield – Shelbyville")
    world.removeLine(1)
    engine.tick(106) -- the sole line's queue slot forces an immediate refillQueue
    eq(engine.save().records[1], nil)
end

return t
