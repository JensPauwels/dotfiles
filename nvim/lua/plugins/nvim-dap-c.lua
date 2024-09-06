return {
	"mfussenegger/nvim-dap",
	dependencies = {
		"rcarriga/nvim-dap-ui",
		"leoluz/nvim-dap-go", -- Plugin specifically for Go debugging
	},
	config = function()
		local dap, dapui = require("dap"), require("dapui")
		local dap_go = require("dap-go")

		-- Setup dap-go
		dap_go.setup()
		dapui.setup()

		dap.set_log_level("TRACE")

		-- Open DAP UI before events
		dap.listeners.before.event_initialized["dapui_config"] = function()
			dapui.open()
		end
		dap.listeners.before.event_terminated["dapui_config"] = function()
			dapui.close()
		end
		dap.listeners.before.event_exited["dapui_config"] = function()
			dapui.close()
		end

		-- Key mappings for DAP
		vim.keymap.set("n", "<Leader>dt", dap.toggle_breakpoint, {})
		vim.keymap.set("n", "<Leader>dc", dap.continue, {})
		vim.keymap.set("n", "<Leader>dr", dap.repl.open, {})
		vim.keymap.set("n", "<Leader>ds", dap.step_over, {})
		vim.keymap.set("n", "<Leader>di", dap.step_into, {})
		vim.keymap.set("n", "<Leader>do", dap.step_out, {})

		-- Key mapping for Go specific debugging
		vim.keymap.set("n", "<Leader>dg", dap_go.debug_test, {}) -- Debug test function in Go

		-- Automatically install delve if not found
		dap_go.setup({
			dap_configurations = {
				{
					name = "Launch Go Program",
					type = "go",
					request = "launch",
					program = "${workspaceFolder}/main.go", -- Replace with the relative path to your main.go file
					cwd = "${workspaceFolder}", -- Set the current working directory to the root of your workspace
					env = {
						MODE = "DEVELOPMENT",
					}, -- Optional: Environment variables
					args = {}, -- Optional: Command-line arguments
					envFile = "${workspaceFolder}/.env", -- Optional: Path to an env file
				},
				{
					type = "go",
					name = "Debug test (Go)",
					request = "launch",
					mode = "test",
					program = "${file}",
				},
			},
			-- Automatically installs delve if not found
			delve = {
				initialize_timeout_sec = 20,
				port = "${port}",
			},
		})
	end,
}
