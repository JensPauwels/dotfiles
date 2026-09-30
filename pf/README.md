# pf

Start, stop and watch long-running port forwards without keeping a terminal
tab hostage. Works for `kubectl port-forward`, `cloud-sql-proxy`, or anything
that listens on a local port.

`pf` with no arguments opens a small dashboard (`pf-tui`, Go + Bubble Tea):

```
 pf  12 forwards · 2 running
╭─ list ─────────────────────────╮╭─ prod-db ─────────────────────────────╮
│▎● prod-db   :3310 running ││ state    running · pid 4159                │
│ ○ staging-db   :3314 stopped ││ port     127.0.0.1:3310                    │
│ ! api-pod   :3316 busy    ││ command  cloud-sql-proxy ...               │
│ ✗ redis      :3324 died    ││ ──────────────────────────────────────────  │
│                                ││ 2026/09/30 10:31 Listening on 127.0.0.1... │
╰────────────────────────────────╯╰────────────────────────────────────────────╯
 enter toggle · x stop · r restart · S stop all · e edit · ? help · q quit
```

The list refreshes every second and the right pane tails the selected log.
`enter` toggles, `s`/`x`/`r` start/stop/restart, `S` stops everything, `e`
opens the definitions in `$EDITOR`, `q` quits (forwards keep running).

States: `●` running, `○` stopped, `✗` died on its own (the log tells why),
`!` the port is held by something pf did not start. Toggling a busy one shows
the owner and asks first. If the owner is a Docker container (OrbStack or
Docker Desktop publish ports through their VM helper, which must never be
killed) it offers `docker stop <container>` instead of a kill.

## Command line

```
pf start NAME...      run detached, wait until the port listens
pf stop NAME... | --all
pf toggle NAME        pf restart NAME
pf status             every forward with state and pid
pf logs NAME [-f|N]   pf show NAME
pf edit               open the definitions file
pf -f ...             skip the "kill it?" question (or PF_FORCE=1)
```

`pf-<name>` aliases exist for every forward (see `pf.zsh`), so
`pf-prod-db` still works, now detached instead of blocking the tab.

## Files

- `~/.config/pf/forwards` (gitignored, start from `forwards.example`): one
  forward per line, `NAME  LOCAL_PORT  COMMAND...`. Commands run through
  `zsh -c`, so `$(...)` works.
- `~/.local/state/pf/<name>.log` and `.pid`.

## Install

```sh
cd ~/dotfiles && stow pf      # links ~/.local/bin/pf, ~/.local/bin/pf-tui, ~/.config/pf
./pf/build.sh                 # builds pf-tui (needs Go); without it `pf` falls back to fzf
```

Then `source ~/.config/pf/pf.zsh` from `.zshrc` for completion and aliases.
