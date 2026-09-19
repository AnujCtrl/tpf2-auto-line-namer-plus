-- Base of the host-side stand-ins for the Transport Fever 2 scripting globals.
-- fake_game.lua (engine API) and fake_gui.lua (GUI API) build on this by registering reset hooks,
-- so no task needs to edit this file.
local fake = {}

-- MIRROR OF THE GAME'S STANDARD LIBRARY. Transport Fever 2's own res/scripts/init.lua makes exactly
-- one change to it, and that change broke this mod in the game while every host test passed:
--     local oldunpack = table.unpack
--     table.unpack = function(t) if type(t) == "userdata" then ... else return oldunpack(t) end end
-- i.e. table.unpack DROPS its (i, j) arguments, and (Lua 5.2.2) there is no global `unpack`. Every
-- test runs under the same rule, on every interpreter, so code that leans on unpack fails here too.
do
    local oldunpack = table.unpack or unpack
    unpack = nil
    table.unpack = function(tbl) return oldunpack(tbl) end
end

local resetHooks = {}

-- Register a function that runs at the end of every fake.reset().
function fake.addReset(fn)
    resetHooks[#resetHooks + 1] = fn
end

function fake.reset()
    -- The game's translation function returns its argument when there is no translation.
    _ = function(s) return s end
    api = { engine = {}, res = {}, cmd = {}, gui = {}, type = {} }
    game = { interface = {} }
    fake.printed = {}
    for __, fn in ipairs(resetHooks) do fn() end
end

local function show(v, indent)
    indent = indent or ""
    if type(v) ~= "table" then return type(v) == "string" and ("%q"):format(v) or tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for __, k in ipairs(keys) do
        parts[#parts + 1] = indent .. "  [" .. show(k) .. "] = " .. show(v[k], indent .. "  ")
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end
fake.show = show

local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- Deep equality with a readable failure message.
function fake.eq(actual, expected, label)
    if not same(actual, expected) then
        error((label and (label .. ": ") or "") .. "expected " .. show(expected) .. "\n  got " .. show(actual), 2)
    end
end

return fake
