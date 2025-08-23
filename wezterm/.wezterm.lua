local wezterm = require("wezterm")
local config = wezterm.config_builder and wezterm.config_builder() or {}

-- === Font & metrics (match VS Code) ===
config.font = wezterm.font("Dank Mono", { weight = "Bold" })
config.font_size = 18.0 -- VS Code “18” equivalent
config.line_height = 1.30 -- same as your VS Code feel
config.cell_width = 1.0 -- keep default glyph width

-- Ligatures/features similar to Chromium rendering
config.harfbuzz_features = {
	"calt=1", -- contextual alternates
	"liga=1", -- standard ligatures
	"clig=1", -- contextual ligatures
	"kern=1", -- kerning
}

-- Render with the modern GPU backend (closest to Chromium’s pipeline)
config.front_end = "WebGpu"

-- === Platform-specific smoothing to mimic VS Code ===
local triple = wezterm.target_triple

-- macOS (CoreText). VS Code uses grayscale AA; CoreText already matches closely.
if triple:find("darwin") then
	-- Nothing special needed; CoreText AA is already VS Code–like.
	-- If you still want a touch more softness, uncomment:
	-- config.freetype_load_flags = "NO_HINTING" -- (ignored on macOS)
end

-- Windows (DirectWrite) – match ClearType feel
if triple:find("windows") then
	-- DirectWrite is already subpixel; the WebGPU front_end helps match VS Code.
	-- Keep defaults; no extra knobs needed.
end

-- Linux/*BSD (FreeType) – explicitly pick light hinting + LCD like Chromium
if not (triple:find("darwin") or triple:find("windows")) then
	config.freetype_load_target = "Light" -- softer, VS Code–like
	config.freetype_render_target = "HorizontalLcd" -- subpixel AA
	config.freetype_load_flags = "NO_HINTING" -- avoid chunky stems
end

-- Optional: make bold NOT map to bright color (closer to VS Code editor)
config.bold_brightens_ansi_colors = false
config.enable_tab_bar = false
config.color_scheme = "nightfox"

return config
