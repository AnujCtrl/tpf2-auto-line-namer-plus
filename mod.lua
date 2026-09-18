---@diagnostic disable-next-line: lowercase-global
function data()
    return {
        info = {
            minorVersion = 0,
            severityAdd = "NONE",
            severityRemove = "NONE",
            name = _("Auto Line Namer Plus"),
            description = _([[
Names your lines for you, from their stops, towns, industries and cargo.

- Works on every line, including ones made in the normal line manager
- Never overwrites a name you wrote: editing a name locks that line
- A naming pattern per kind of line (bus, tram, truck, train, ship, aircraft)
- Tokens for towns, stops, via towns, industries, cargo and a running number
- Preview every rename before applying it
- Every option is a setting, and every part of the window has an "i" button that explains it
- Looks at a bounded number of lines per tick, however many lines the save has

A fork of Auto Line Namer by erkanercan, rebuilt.
]]),
            tags = { "Script Mod", "Misc" },
            authors = {
                {
                    name = "AnujCtrl",
                    role = "CREATOR",
                },
                {
                    name = "erkanercan",
                    role = "BASED_ON",
                },
            },
        },
    }
end
