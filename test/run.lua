-- Run from the repo root:
--   lua5.4 test/run.lua                 every test/test_*.lua
--   lua5.4 test/run.lua test_naming     only the named files
package.path = "res/scripts/?.lua;test/?.lua;" .. package.path
local fake = require("fake_api")

local files = {}
if #arg > 0 then
    for i = 1, #arg do files[#files + 1] = (arg[i]:gsub("%.lua$", "")) end
else
    local listing = assert(io.popen("ls test"))
    for entry in listing:lines() do
        local name = entry:match("^(test_[%w_]+)%.lua$")
        if name then files[#files + 1] = name end
    end
    listing:close()
    table.sort(files)
end

local passed, failed = 0, 0
for __, file in ipairs(files) do
    fake.reset()
    local ok, cases = pcall(require, file)
    if not ok or type(cases) ~= "table" then
        failed = failed + 1
        print(("FAIL %s: could not load: %s"):format(file, tostring(cases)))
    else
        local names = {}
        for name in pairs(cases) do names[#names + 1] = name end
        table.sort(names)
        for __, name in ipairs(names) do
            fake.reset()
            local ok2, err = xpcall(cases[name], debug.traceback)
            if ok2 then
                passed = passed + 1
            else
                failed = failed + 1
                print(("FAIL %s.%s: %s"):format(file, name, tostring(err)))
            end
        end
    end
end
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
