# Dotfiles - Catppuccin Setup

This repository contains my dotfiles configured with the beautiful Catppuccin theme across Neovim, tmux, and Ghostty.

## Features

- **Neovim**: Catppuccin Mocha theme with full integration
- **Tmux**: Catppuccin Mocha theme with custom status bar
- **Ghostty**: Catppuccin Mocha theme with rounded borders and transparency

## Installation

Use [GNU Stow](https://www.gnu.org/software/stow/) to symlink these configurations:

```bash
# Install individual packages
stow nvim     # Symlinks ~/.config/nvim
stow tmux     # Symlinks ~/.tmux.conf
stow ghostty  # Symlinks ~/.config/ghostty

# Or install all at once
stow */
```

## Prerequisites

### Neovim
- Install [lazy.nvim](https://github.com/folke/lazy.nvim) plugin manager
- The Catppuccin theme will be automatically installed via the plugin configuration

### Tmux
- Install [TPM (Tmux Plugin Manager)](https://github.com/tmux-plugins/tpm):
  ```bash
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
  ```
- After symlinking the config, install plugins: `prefix + I` (default: `Ctrl-s + I`)

### Ghostty
- Install [Ghostty terminal](https://mitchellh.com/ghostty)
- Install a Nerd Font like [JetBrains Mono](https://www.nerdfonts.com/font-downloads)

## Theme Details

All configurations use **Catppuccin Mocha** flavor for consistency:
- Background: `#1e1e2e`
- Primary accent: `#89b4fa` (blue)
- Secondary accents match the Catppuccin palette

## Customization

Each configuration file is well-commented and can be easily customized:
- `nvim/lua/plugins/theme-c.lua` - Neovim theme settings
- `tmux/.tmux.conf` - Tmux configuration and theme
- `ghostty/config` - Ghostty terminal settings

## Key Bindings

### Tmux (Colemak layout optimized)
- Prefix: `Ctrl-s`
- Split horizontal: `prefix + -`
- Split vertical: `prefix + _`
- Navigate panes: `prefix + h/j/k/l`

### Ghostty
- New window: `Cmd+n`
- New tab: `Cmd+t`
- Copy: `Cmd+c`
- Paste: `Cmd+v`
- Font size: `Cmd++` / `Cmd+-` / `Cmd+0`

Enjoy your beautiful, consistent development environment! 🎨