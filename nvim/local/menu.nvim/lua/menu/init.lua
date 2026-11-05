-- menu.nvim: one fuzzy list of everything you can do where you are.
--
-- Built from the keymaps themselves, so it never goes stale: every normal
-- mode mapping with a description is an entry, showing its key. Keys of the
-- current buffer (a plugin's panel, the diff view, …) come first as "here",
-- then the global ones grouped by their description prefix ("Review: …"),
-- or their <leader> prefix. Extra entries (commands without a key) come from
-- the config. <CR> runs the entry in the window you were in.
local api = vim.api

local M = {}

M.config = {
	-- <leader> prefixes to group names; descriptions like "Group: action"
	-- take precedence.
	groups = {
		["<leader>f"] = "Find",
		["<leader>g"] = "Git",
		["<leader>h"] = "Hunk",
		["<leader>p"] = "Review",
		["<leader>c"] = "Code",
		["<leader>t"] = "Tabs",
	},
	-- Groups listed first, in this order (after "here").
	order = { "Review", "Find", "Code", "AI", "Git", "Pulls", "Changes", "Hunk", "Explorer", "Edit", "Window", "Tabs", "General" },
	-- Entries without a key: { group, desc, cmd } where cmd is an Ex command;
	-- a trailing space leaves it on the command line for you to finish.
	extras = {},
}

local function leader_name(lhs)
	local leader = vim.g.mapleader or "\\"
	local l = lhs
	if leader == " " then
		l = l:gsub("^<Space>", "<leader>"):gsub("^ ", "<leader>")
	elseif vim.startswith(l, leader) then
		l = "<leader>" .. l:sub(#leader + 1)
	end
	return l
end

--- Group and action text of a mapping description.
local function split_desc(desc)
	local g, rest = desc:match("^(%u[%w ]-):%s+(.+)$")
	if g and #g <= 20 then
		return g, rest
	end
	return nil, desc
end

local runtime = vim.fs.normalize(vim.env.VIMRUNTIME or "")

--- Mappings Neovim itself defines (]q, gcc, grn, …).
local function builtin(km)
	if km.callback then
		local src = debug.getinfo(km.callback, "S").source:gsub("^@", "")
		-- vim/_core/defaults.lua is compiled in: its source is a module path
		return vim.startswith(src, "vim/") or vim.startswith(vim.fs.normalize(src), runtime)
	end
	return (km.desc or ""):match("^:help ") ~= nil
end

local function group_of(key, desc_group)
	if desc_group then
		return desc_group
	end
	local best, best_len = nil, 0
	for prefix, name in pairs(M.config.groups) do
		if vim.startswith(key, prefix) and #prefix > best_len then
			best, best_len = name, #prefix
		end
	end
	return best or "General"
end

--- Menu entries for the current buffer.
--- @param opts? { here?: boolean, group?: string }
--- @return table[]
function M.items(opts)
	opts = opts or {}
	local out, seen = {}, {}
	local function add(km, here)
		local desc = km.desc
		if not desc or desc == "" or km.lhs:match("^<Plug>") or km.lhs:match("^<SNR>") then
			return
		end
		local key = leader_name(km.lhs)
		if seen[key] then
			return -- a buffer mapping hides the global one
		end
		seen[key] = true
		local dg, text = split_desc(desc)
		local group
		if here and vim.bo.buftype ~= "" then
			group = "here" -- a plugin's window: its own keys
		elseif here then
			group = group_of(key, dg)
			group = group == "General" and "Code" or group -- LSP and friends
		elseif not dg and builtin(km) then
			group = "Neovim" -- listed last
		else
			group = group_of(key, dg)
		end
		out[#out + 1] = {
			text = group .. " " .. text .. " " .. key,
			group = group,
			desc = text,
			key = key,
			lhs = km.lhs,
		}
	end
	for _, km in ipairs(api.nvim_buf_get_keymap(0, "n")) do
		add(km, true)
	end
	if not opts.here then
		for _, km in ipairs(api.nvim_get_keymap("n")) do
			add(km, false)
		end
		for _, e in ipairs(M.config.extras) do
			out[#out + 1] = {
				text = e[1] .. " " .. e[2] .. " :" .. e[3],
				group = e[1],
				desc = e[2],
				key = ":" .. vim.trim(e[3]),
				cmd = e[3],
			}
		end
	end
	if opts.group then
		out = vim.tbl_filter(function(i)
			return i.group == opts.group
		end, out)
	end
	local rank = { here = 0, Neovim = 1000 }
	for i, g in ipairs(M.config.order) do
		rank[g] = i
	end
	table.sort(out, function(a, b)
		local ra, rb = rank[a.group] or 100, rank[b.group] or 100
		if ra ~= rb then
			return ra < rb
		end
		if a.group ~= b.group then
			return a.group < b.group
		end
		return a.desc:lower() < b.desc:lower()
	end)
	return out
end

--- Run an entry in the current window.
function M.run(item)
	if item.cmd then
		if item.cmd:sub(-1) == " " then
			api.nvim_feedkeys(":" .. item.cmd, "n", false)
		else
			vim.cmd(item.cmd)
		end
		return
	end
	api.nvim_feedkeys(vim.keycode(item.lhs), "m", false)
end

local function format(item)
	local gw = 10
	return {
		{ string.format("%-" .. gw .. "s", item.group), item.group == "here" and "MenuHere" or "MenuGroup" },
		{ item.desc .. "  " },
		{ item.key, "MenuKey" },
	}
end

local function set_hl()
	api.nvim_set_hl(0, "MenuGroup", { link = "Title", default = true })
	api.nvim_set_hl(0, "MenuHere", { link = "Special", default = true })
	api.nvim_set_hl(0, "MenuKey", { link = "Comment", default = true })
end

--- Open the menu.
--- @param opts? { here?: boolean, group?: string, title?: string }
function M.open(opts)
	opts = opts or {}
	local win = api.nvim_get_current_win()
	local items = M.items(opts)
	local title = opts.title or (opts.here and "Keys here" or "Menu")
	local has_snacks = rawget(_G, "Snacks") and Snacks.picker
	if not has_snacks then
		vim.ui.select(items, {
			prompt = title,
			format_item = function(i)
				return string.format("%-10s %s  %s", i.group, i.desc, i.key)
			end,
		}, function(item)
			if item then
				M.run(item)
			end
		end)
		return
	end
	Snacks.picker.pick({
		source = "menu",
		title = title,
		items = items,
		format = format,
		layout = { preset = "select" },
		matcher = { sort_empty = false },
		sort = { fields = { "score:desc", "idx" } },
		confirm = function(picker, item)
			picker:close()
			if not item then
				return
			end
			vim.schedule(function()
				if api.nvim_win_is_valid(win) then
					api.nvim_set_current_win(win)
				end
				M.run(item)
			end)
		end,
	})
end

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
	set_hl()
	api.nvim_create_autocmd("ColorScheme", {
		group = api.nvim_create_augroup("menu.hl", { clear = true }),
		callback = set_hl,
	})
	api.nvim_create_user_command("Menu", function(c)
		M.open({ here = c.args == "here" })
	end, { nargs = "?", complete = function() return { "here" } end, desc = "Menu of actions and keys" })
end

return M
