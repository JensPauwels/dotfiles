// home: one picker for the things done all day, outside Neovim, and the agent
// marks on the tmux window names. See ../README.md.
package main

import (
	"fmt"
	"os"
)

const usage = `home                      the picker: actions and port forwards
home pr                   pick a pull request and review it in a worktree
home pr OWNER/NAME#123    review that one (a pull request URL works too)
home open                 open a linked repository or worktree in a new window
home sessions             tmux sessions and tmuxinator projects
home wt                   review worktrees: reopen, remove
home pf                   the port forward dashboard

home link [PATH]          link the clone here (or at PATH) to its GitHub repository
home link --root DIR...   link every clone under DIR
home link --list          what is linked
home unlink OWNER/NAME

home agent STATE          working | waiting | done | clear; called by agent hooks
home next                 go to a window where an agent waits for you
`

func main() {
	args := os.Args[1:]
	arg := func(i int) string {
		if i < len(args) {
			return args[i]
		}
		return ""
	}
	var err error
	switch arg(0) {
	case "", "menu":
		err = runTUI(menuScreen())
	case "open":
		err = runTUI(repoScreen())
	case "pr":
		err = cmdPR(args[1:])
	case "pf":
		err = execv("", "pf")()
	case "sessions":
		err = runTUI(sessionScreen())
	case "wt":
		err = runTUI(worktreeScreen())
	case "link":
		err = cmdLink(args[1:])
	case "unlink":
		err = cmdUnlink(args[1:])
	case "next":
		err = cmdNext(arg(1))
	case "agent":
		cmdAgent(arg(1))
	case "-h", "--help", "help":
		fmt.Print(usage)
	default:
		fmt.Fprint(os.Stderr, usage)
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "home:", err)
		os.Exit(1)
	}
}
