-- Minimal headless test runner. Each tests/test_*.lua returns a list of
-- { name, fn }. Run with tests/run.sh, optionally filtered by TEST=<substr>.
local here = debug.getinfo(1, "S").source:sub(2)
local plugin = vim.fn.fnamemodify(here, ":p:h:h")
vim.opt.runtimepath:append(plugin)
package.path = plugin .. "/tests/?.lua;" .. package.path

local H = require("helpers")
local files = vim.fn.glob(plugin .. "/tests/test_*.lua", true, true)
table.sort(files)
local filter = vim.env.TEST
if filter == "" then
	filter = nil
end

local passed, failed = 0, 0
for _, file in ipairs(files) do
	if not filter or file:find(filter, 1, true) then
		print(vim.fn.fnamemodify(file, ":t"))
		for _, t in ipairs(dofile(file)) do
			H.before_each()
			local ok, err = xpcall(t[2], debug.traceback)
			H.after_each()
			if ok then
				passed = passed + 1
				print("  ok    " .. t[1])
			else
				failed = failed + 1
				print("  FAIL  " .. t[1] .. "\n" .. tostring(err):gsub("\n", "\n        "))
			end
		end
	end
end
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	vim.cmd("cquit 1")
else
	vim.cmd("qa!")
end
