# home

Two small things on top of tmux, which otherwise stays as it is:

- a **picker** in a popup (`prefix + Space`) for the things done all day:
  toggle a port forward, review a pull request, open a repository;
- **agent marks** on the window names in the status line, so you see which
  tab has a Claude Code or Codex that needs you.

Go + Bubble Tea, like `pf-tui`.

## The picker

```
 home  18
 ❯ api▏
 ▎ ●  api-db                  stop · :5432 · running
   ●  api-redis               stop · :6379 · running
 enter run · ^r reload · esc quit
```

Type to filter, `enter` to run, `esc` to go back or close. It lists the
actions first, then every port forward: Enter on one starts or stops it,
closes the picker and leaves pf's answer in the tmux message line. A port
held by something pf did not start is left to the dashboard, which asks
before killing.

| Entry | Enter |
| --- | --- |
| Review a pull request | those waiting for your review, then yours; makes a worktree and opens a window with `nvim "+PR review N"` (`^o` opens the browser) |
| Open a repository | a linked repository or one of its worktrees, in a new window |
| Sessions | switch to a tmux session, or start a tmuxinator project |
| Worktrees | the `-pr-` worktrees with the state of their pull request; `^x` removes one |
| Next agent | go to a window where an agent waits for you |
| Port forward dashboard | `pf` |

Each is also a command: `home pr`, `home open`, `home sessions`, `home wt`,
`home pf`. `home pr OWNER/NAME#123` (or a pull request URL) skips the picker.

## Agent marks

```
 1 nvim  2 claude ●  3 api ✓  4 claude ◐           ● work:2  ~/dotfiles  12:37
```

| Mark | Meaning |
| --- | --- |
| `●` orange | the agent asks for your input |
| `✓` green | it finished while you were elsewhere; gone once you visit the window |
| `◐` purple | it is working |

Windows in other sessions that ask for input are listed on the right as
`session:window`. `prefix + a` goes to the next waiting one (asking first,
then finished).

When an agent asks for input or finishes while you are not looking at its
window, you are told. In another tmux window: a line in the tmux message
area for two seconds. With another app in front: a desktop notification
(`home` writes an OSC 9 sequence to the terminal, which Ghostty shows as a
system notification; it does not show one while it is the focused app).
`HOME_NOTIFY=0` in the agent's environment turns both off.

Claude Code and Codex report through hooks that run `home agent STATE`,
which sets the window option `@home_agent`; `~/.config/home/tmux.conf` turns
it into the mark.

| Event | State |
| --- | --- |
| prompt submitted, tool finished | `working` |
| permission asked (Claude: `Notification`, Codex: `PermissionRequest`) | `waiting` |
| turn finished (`Stop`) | `done` |
| session ended (Claude) | cleared |

The hooks are in `~/.claude/settings.json` and `~/.codex/hooks.json`. After
you allow a tool, the mark stays `●` until that tool finishes: there is no
hook for the moment you answer. An agent that is killed leaves its last mark
behind; `home agent clear` in that window removes it.

## Linking repositories

`home pr` needs to know where a repository is cloned:

```
home link [PATH]          link the clone here (or at PATH) to its GitHub repository
home link --root DIR...   link every clone under DIR (worktrees are skipped)
home link --list          what is linked
home unlink OWNER/NAME
```

The registry is `~/.config/home/repos`, `owner/name<TAB>path` per line.

Reviewing a pull request: if a worktree of the clone already has the branch
checked out, it is used. Otherwise `<clone>-pr-<number>` is made next to the
clone and `gh pr checkout` runs in it. A new worktree has no `node_modules`;
`:PR install` in Neovim runs the install.

## Install

```sh
./home/build.sh               # builds home/.local/bin/home (needs Go)
cd ~/dotfiles && stow home    # links ~/.local/bin/home and ~/.config/home/tmux.conf
home link --root ~/code/work ~/code/private
tmux source-file ~/.tmux.conf
```

`.tmux.conf` sources `~/.config/home/tmux.conf` last, and its window formats
end in `#{E:@home_mark}`.

## Adding a command

A picker is a `screen` (`src/ui.go`): a `load` that returns the rows and an
`enter` for the selected one. Add it to `actions` in `menuScreen`
(`src/screens.go`) and to the switch in `src/main.go`.
