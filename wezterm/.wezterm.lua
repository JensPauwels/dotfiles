-- Pull in the wezterm API
local wezterm = require("wezterm")

-- This table will hold the configuration.
local config = {}

-- In newer versions of wezterm, use the config_builder which will
-- help provide clearer error messages
if wezterm.config_builder then
	config = wezterm.config_builder()
end

-- This is where you actually apply your config choices

-- For example, changing the color scheme:
config.color_scheme = "tokyonight-storm"

config.font_size = 15

config.enable_tab_bar = false

config.font = wezterm.font("MonacoLigaturized Nerd Font Mono", { weight = "Bold", italic = false })
-- config.font = wezterm.font("Menlo", { weight = "Bold" })

-- and finally, return the configuration to wezterm
return config
