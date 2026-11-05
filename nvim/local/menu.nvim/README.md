# menu.nvim

One fuzzy list of everything you can do where you are, with the key for it.

- `<leader><leader>` (or `:Menu`): all actions. The keys of the current
  window come first: a plugin's panel shows its own keys as **here**, a code
  buffer its LSP and hunk keys under **Code** and **Hunk**. Then the global
  keys by group, Neovim's built-in ones last.
- `?` in pulls.nvim and changes.nvim (or `:Menu here`): only the keys of that
  window.
- `<CR>` runs the entry in the window you came from.

Built from the keymaps themselves, so it cannot go stale: any normal-mode
mapping with a `desc` shows up. A description `"Group: action"` puts it in
that group; otherwise the `<leader>` prefix decides (`config.groups`).
Commands without a key go in `extras = { { group, desc, cmd } }`; a `cmd`
ending in a space is left on the command line to finish.
