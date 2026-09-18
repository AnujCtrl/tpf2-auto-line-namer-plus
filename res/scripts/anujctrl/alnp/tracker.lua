-- The safety core: decides whether a line's name may be touched by the mod. Pure Lua, no
-- api/game/_ access, so it can be unit-tested on the host and reasoned about in isolation.
-- When in doubt it answers "skip" - a name the player wrote by hand must never be overwritten.
local tracker = {}

-- A line the mod has not seen before.
function tracker.newRecord()
    return {}
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Splits a comma-separated string into trimmed, non-empty entries with duplicates removed,
-- keeping first-seen order.
local function splitUnique(s)
    local seen = {}
    local out = {}
    for raw in (s .. ","):gmatch("([^,]*),") do
        local entry = trim(raw)
        if entry ~= "" and not seen[entry] then
            seen[entry] = true
            out[#out + 1] = entry
        end
    end
    return out
end

-- Escapes Lua pattern-magic characters so a word matches only its literal text.
local function escapePattern(word)
    return (word:gsub("%p", "%%%0"))
end

-- True when name is nil, empty, whitespace-only, or exactly "<word> <digits>" for some word.
function tracker.isDefaultName(name, words)
    if name == nil then return true end
    if trim(name) == "" then return true end
    for __, word in ipairs(words) do
        if name:match("^" .. escapePattern(word) .. " %d+$") then return true end
    end
    return false
end

-- Builds the list of default-name words: "Line", the translated word for "Line" (if distinct
-- and non-empty), then each entry of tbl.defaults.extraPrefixes, de-duplicated in order.
function tracker.defaultWords(tbl, translatedLine)
    local seen = { Line = true }
    local words = { "Line" }
    if type(translatedLine) == "string" and translatedLine ~= "" and not seen[translatedLine] then
        seen[translatedLine] = true
        words[#words + 1] = translatedLine
    end
    for __, entry in ipairs(splitUnique(tbl.defaults.extraPrefixes)) do
        if not seen[entry] then
            seen[entry] = true
            words[#words + 1] = entry
        end
    end
    return words
end

-- True when tbl.lock.prefix is non-empty and name starts with it, as plain text.
local function hasLockPrefix(name, tbl)
    local prefix = tbl.lock.prefix
    return prefix ~= "" and name:sub(1, #prefix) == prefix
end

-- True when trim(name), lower-cased, matches one of tbl.reload.names (comma-separated, trimmed,
-- lower-cased).
local function isReloadName(name, tbl)
    local wanted = trim(name):lower()
    for __, entry in ipairs(splitUnique(tbl.reload.names)) do
        if entry:lower() == wanted then return true end
    end
    return false
end

-- First match wins; see spec section 6 and the task brief's rules table.
function tracker.decide(record, name, kindAutoRename, tbl, words)
    record = record or tracker.newRecord()

    -- 1. Mod disabled, or this line's kind has auto-rename off.
    if not tbl.enabled or not kindAutoRename then return "skip" end

    -- 2. The player locked this line from the Lines tab.
    if record.locked == "player" then return "skip" end

    -- 3. The name starts with the configured lock prefix.
    if hasLockPrefix(name, tbl) then return "skip" end

    -- 4. The name asks for a one-off rename.
    if isReloadName(name, tbl) then return "rename" end

    -- 5. The name is a game default name.
    if tracker.isDefaultName(name, words) then
        return tbl.eligible.defaultNames and "rename" or "skip"
    end

    -- 6. The name is what the mod last assigned.
    if record.lastAssigned ~= nil and name == record.lastAssigned then
        return tbl.eligible.modAssigned and "rename" or "skip"
    end

    -- 7. Anything else: the player wrote this name.
    return tbl.lock.autoLockEdited and "autoLock" or "skip"
end

-- The lock badge shown in the Lines tab, or nil when the line isn't locked.
function tracker.lockState(record, name, tbl)
    record = record or tracker.newRecord()
    if record.locked == "player" then return "player" end
    if hasLockPrefix(name, tbl) then return "prefix" end
    if record.locked == "edited" then return "edited" end
    return nil
end

return tracker
