# pf

Start, stop and pick long-running port forwards without keeping a terminal
tab hostage. Works for `kubectl port-forward`, `cloud-sql-proxy`, or anything
that listens on a local port.

```
pf                    picker: enter toggles, tab marks several, ctrl-r refreshes, esc quits
pf start NAME...      run detached, wait until the port listens
pf stop NAME... | --all
pf toggle NAME        pf restart NAME
pf status             every forward with state and pid
pf logs NAME [-f|N]   pf show NAME (what the picker's preview shows)
pf edit               open the definitions file
```

States: `●` running, `○` stopped, `✗` died on its own (see `pf logs`),
`!` the port is taken by something pf did not start.

Definitions live in `~/.config/pf/forwards` (gitignored, start from `forwards.example`), one per line:
`NAME  LOCAL_PORT  COMMAND...`. Logs and pid files in `~/.local/state/pf`.

Install with `stow pf` from the dotfiles root (links `~/.local/bin/pf` and
`~/.config/pf`), then add `source ~/.config/pf/pf.zsh` to `.zshrc` for
completion and the `pf-<name>` aliases. Needs `fzf` for the picker.
