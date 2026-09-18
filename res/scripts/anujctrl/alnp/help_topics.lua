-- Every help topic shown behind an "i" button in the settings window. Plain English strings:
-- gui/help.lua wraps title and text in _() when it displays them, so this file needs neither
-- api nor _(). Each text line is at most 72 characters, written for someone who has never seen
-- the mod before. Topic keys are fixed (see the task plan); other modules use them verbatim.
local topics = {}

topics.list = {
    {
        key = "topbar.button",
        title = "Auto Line Namer Plus",
        text = "Opens the Auto Line Namer Plus settings window. The mod\n"
            .. "automatically renames your bus, tram, truck, train, ship and\n"
            .. "air lines from their stops, towns, industries and cargo,\n"
            .. "without ever overwriting a name you wrote yourself. Click\n"
            .. "this button to see and change every option.",
    },
    {
        key = "window.overview",
        title = "How this window works",
        text = "Every game tick the mod checks a few lines, in rotation. When\n"
            .. "a line's stops, name or vehicle count change, it waits for a\n"
            .. "short settle delay before deciding what to do, so a line\n"
            .. "that is mid-edit is left alone.\n"
            .. "\n"
            .. "A line is skipped once it is locked. Locking happens when you\n"
            .. "tick the lock box on the Lines tab, automatically when you\n"
            .. "type your own name for it (if that option is on), or\n"
            .. "whenever the name starts with the configured lock prefix.\n"
            .. "Anything else -- a default game name, or a name the mod\n"
            .. "assigned before -- gets renamed.\n"
            .. "\n"
            .. "Settings and per-line locks are saved with your game, so\n"
            .. "each save keeps its own configuration.\n"
            .. "res/scripts/anujctrl/alnp/user_defaults.lua sets the\n"
            .. "starting values used for brand-new saves only; it never\n"
            .. "changes a save already in progress.",
    },
    {
        key = "tab.general",
        title = "General tab",
        text = "General holds the master switch, the lock prefix, whether\n"
            .. "typing a name locks a line automatically, the words that\n"
            .. "trigger a one-off rename (like \"reload\"), which default and\n"
            .. "mod-assigned names are eligible for renaming, the minimum\n"
            .. "stop count, and the text used for each line kind and scope.\n"
            .. "\n"
            .. "Usual workflow: turn the mod on, optionally set a lock\n"
            .. "prefix for lines you always want left alone, then check the\n"
            .. "Lines tab to see the result. Reset everything from here if\n"
            .. "you want to start over.",
    },
    {
        key = "tab.advanced",
        title = "Advanced tab",
        text = "Advanced holds scope thresholds, the separators used to join\n"
            .. "names, cargo and intermediate-town shaping, the industry\n"
            .. "lookup, line numbering, how much work the mod does per\n"
            .. "tick, and the log level.\n"
            .. "\n"
            .. "The shipped defaults work well for most games -- it is safe\n"
            .. "to leave this tab alone. Come back here to fine-tune wording\n"
            .. "or performance once you have seen a few lines get named.",
    },
    {
        key = "tab.patterns",
        title = "Patterns tab",
        text = "A pattern is a template made of tokens, like \"{type} {towns}\",\n"
            .. "that the mod fills in with a line's own facts to build its\n"
            .. "name. Every kind of line (bus, cargo train, and so on) uses\n"
            .. "the default pattern unless you give it a custom one of its\n"
            .. "own.\n"
            .. "\n"
            .. "The preview next to each pattern updates as you type, using\n"
            .. "the same code that names real lines, so what you see is\n"
            .. "what you get.",
    },
    {
        key = "tab.lines",
        title = "Lines tab",
        text = "Lists every line you own: its detected kind, current name,\n"
            .. "and the name the mod would give it. Tick a row to include\n"
            .. "it in \"Apply checked\", or use \"rename now\" to rename just\n"
            .. "that one line.\n"
            .. "\n"
            .. "Usual workflow: click \"Preview all\" to fill in proposed\n"
            .. "names, check them over, then click \"Apply checked\" to\n"
            .. "rename the ticked rows.",
    },
    {
        key = "patterns.preset",
        title = "Pattern presets",
        text = "Simple applies the shipped defaults: a plain name for\n"
            .. "passenger lines, and cargo with its industries for freight\n"
            .. "lines. Upstream matches the original Auto Line Namer's\n"
            .. "layout. Detailed spells out the route by its first and last\n"
            .. "stop, with any stops between.\n"
            .. "\n"
            .. "Choosing a preset overwrites the default pattern and every\n"
            .. "kind's pattern, replacing anything you have typed.",
    },
    {
        key = "patterns.default",
        title = "Default pattern",
        text = "The pattern used by every kind of line that does not have\n"
            .. "its own custom pattern below. Change this first; only give\n"
            .. "a kind its own pattern when it genuinely needs different\n"
            .. "wording.",
    },
    {
        key = "patterns.kind",
        title = "Kind pattern",
        text = "One row per line kind (bus, cargo train, and so on). Its\n"
            .. "pattern applies only to lines the mod detects as that kind.\n"
            .. "Leave \"custom pattern\" unticked and the kind inherits the\n"
            .. "default pattern above; tick it to give this kind its own\n"
            .. "wording instead.",
    },
    {
        key = "patterns.autoRename",
        title = "Auto-rename",
        text = "Off: lines of this kind are never renamed automatically, no\n"
            .. "matter what else changes about them. \"Apply checked\" and\n"
            .. "\"rename now\" on the Lines tab still work, so you can still\n"
            .. "rename them by hand.",
    },
    {
        key = "patterns.custom",
        title = "Custom pattern",
        text = "Ticked: this kind uses the pattern typed in on its own row.\n"
            .. "Unticked: it ignores that pattern and inherits the default\n"
            .. "pattern instead.",
    },
    {
        key = "patterns.tokens",
        title = "Pattern tokens",
        text = "A token like {towns} is replaced with that line's own\n"
            .. "facts. Add modifiers after a colon, in any order: a number\n"
            .. "shortens each word to that many letters, u upper-cases, l\n"
            .. "lower-cases -- {towns:3u} turns \"Springfield\" into \"SPR\".\n"
            .. "\n"
            .. "Square brackets mark an optional group: [ #{n}] is dropped\n"
            .. "entirely if {n} would be blank, so you never get a\n"
            .. "dangling \"#\" or space. Groups cannot be nested.\n"
            .. "\n"
            .. "Some tokens have an older, upstream name (for example\n"
            .. "{lineNumber} for {n}); both spellings work. A token that is\n"
            .. "not recognised is left exactly as typed, so a typo shows\n"
            .. "up in the preview instead of disappearing silently.\n"
            .. "\n"
            .. "Every available token is listed below, with an example.",
    },
    {
        key = "lines.col.apply",
        title = "Apply column",
        text = "Tick to include this line the next time you click \"Apply\n"
            .. "checked\". Locked lines and lines you have renamed by hand\n"
            .. "start unticked, so a bulk apply cannot undo work you did\n"
            .. "not ask it to touch.",
    },
    {
        key = "lines.col.kind",
        title = "Kind column",
        text = "The line kind the mod detected from its stops and cargo\n"
            .. "(bus, cargo train, and so on). This decides which pattern\n"
            .. "-- the kind's own, or the default -- gets used to name the\n"
            .. "line.",
    },
    {
        key = "lines.col.current",
        title = "Current name column",
        text = "The line's name right now, exactly as it appears in-game.",
    },
    {
        key = "lines.col.proposed",
        title = "Proposed name column",
        text = "The name \"Preview all\" would give this line. Blank means\n"
            .. "the line would be skipped -- usually because it has fewer\n"
            .. "stops than the configured minimum.",
    },
    {
        key = "lines.col.lock",
        title = "Lock column",
        text = "Shows why a line will not be renamed automatically:\n"
            .. "\n"
            .. "player -- you ticked the lock box for this row yourself.\n"
            .. "Untick it to let the mod rename the line again.\n"
            .. "\n"
            .. "edited -- you typed a name and the mod locked it for you.\n"
            .. "Untick the same lock box to release it.\n"
            .. "\n"
            .. "prefix -- the name starts with the lock prefix set on the\n"
            .. "General tab. Rename the line, or change or clear that\n"
            .. "setting, to clear it.",
    },
    {
        key = "lines.col.renameNow",
        title = "Rename now",
        text = "Renames this one line immediately, using its proposed name,\n"
            .. "even if it is locked or you named it by hand. Use this to\n"
            .. "fix one line without touching the rest.",
    },
    {
        key = "lines.previewAll",
        title = "Preview all",
        text = "Reads every line you own and fills in the \"proposed\"\n"
            .. "column. It changes nothing in the game -- it only computes\n"
            .. "what a rename would produce. Runs in small chunks over\n"
            .. "several frames, so it will not stall on a save with a lot\n"
            .. "of lines.",
    },
    {
        key = "lines.applyChecked",
        title = "Apply checked",
        text = "Renames every ticked line to its proposed name. This\n"
            .. "cannot be undone except by renaming the line again -- there\n"
            .. "is no separate undo. From then on the mod considers that\n"
            .. "name its own, the same as any other name it assigned\n"
            .. "automatically.",
    },
    {
        key = "reset.section",
        title = "Reset section",
        text = "Restores every option on this section back to its shipped\n"
            .. "default. Per-line locks and the mod's own naming records\n"
            .. "are kept -- this only resets settings, never anything\n"
            .. "about your lines.",
    },
    {
        key = "reset.all",
        title = "Reset everything",
        text = "Restores every option and every pattern back to its\n"
            .. "shipped default, across every tab. Per-line locks and the\n"
            .. "mod's own naming records are kept -- this only resets\n"
            .. "settings, never anything about your lines.",
    },
    {
        key = "advanced.apiCheck",
        title = "Run API check",
        text = "Writes a short report to your game's stdout.txt --\n"
            .. "~/.local/share/Steam/userdata/204184616/1066780/local/\n"
            .. "crash_dump/stdout.txt -- describing what the industry\n"
            .. "lookup finds for each cargo stop, and the game's own\n"
            .. "translation of the word \"Line\".\n"
            .. "\n"
            .. "If a cargo stop shows no industry, the industry tokens\n"
            .. "will fall back per the industry setting below instead of\n"
            .. "failing. If \"Line\" is translated to a word the mod does\n"
            .. "not already recognise, add it to \"extra default-name\n"
            .. "words\" on the General tab so lines named that way still\n"
            .. "get picked up for renaming.",
    },
}

local byKey = {}
for __, topic in ipairs(topics.list) do
    byKey[topic.key] = topic
end

function topics.get(key)
    return byKey[key]
end

return topics
