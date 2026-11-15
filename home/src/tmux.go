package main

import (
	"os"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
)

// Everything that talks to tmux.

func inTmux() bool { return os.Getenv("TMUX") != "" }

func tmux(args ...string) (string, error) { return run("", "tmux", args...) }

// open starts argv in dir (a shell when argv is empty): in a new tmux window
// when inside tmux, otherwise in this terminal.
func open(name, dir string, argv ...string) tea.Msg {
	if !isDir(dir) {
		return statusMsg{tilde(dir) + " is gone", false}
	}
	if inTmux() {
		args := append([]string{"new-window", "-n", name, "-c", dir}, argv...)
		if _, err := tmux(args...); err != nil {
			return status(err)
		}
		return doneMsg{}
	}
	if len(argv) == 0 {
		argv = []string{envOr("SHELL", "zsh")}
	}
	return doneMsg{after: execv(dir, argv...)}
}

// cmdAgent records what the agent in this pane's window is doing, in the
// window option @home_agent; the status line draws it next to the window
// name. Claude Code and Codex call it from their hooks. Outside tmux it does
// nothing.
//
// When the agent asks for input or finishes while you are not looking at its
// window, it also tells you: in the tmux message line when you are in another
// window, and with a desktop notification when the terminal is not the
// focused app.
func cmdAgent(state string) {
	p := os.Getenv("TMUX_PANE")
	if p == "" || !inTmux() {
		return
	}
	defer tmux("refresh-client", "-S")
	if state != "working" && state != "waiting" && state != "done" {
		tmux("set-option", "-wu", "-t", p, "@home_agent")
		return
	}
	if state == "working" {
		tmux("set-option", "-w", "-t", p, "@home_agent", state)
		return
	}
	out, _ := tmux("display-message", "-p", "-t", p, "#{window_active}\t#{session_name}\t#{window_index}\t#{pane_current_command}\t#{@home_agent}\t#{b:pane_current_path}")
	f := strings.Split(out+"\t\t\t\t\t", "\t")
	active, session, was := f[0] == "1", f[1], f[4]
	who := "Agent"
	switch cmd := strings.ToLower(f[3]); {
	case strings.Contains(cmd, "claude"):
		who = "Claude"
	case strings.Contains(cmd, "codex"):
		who = "Codex"
	}
	where := f[5] + " (tab " + f[2] + ")" // the folder it works in, and its window

	// The terminals showing this session, and whether one of them has focus.
	var ttys, watching []string // watching: terminals that have focus, on any session
	focused := false
	clients, _ := tmux("list-clients", "-F", "#{client_tty}\t#{client_session}\t#{client_flags}")
	for _, line := range strings.Split(clients, "\n") {
		c := strings.Split(line, "\t")
		if len(c) < 3 {
			continue
		}
		ttys = append(ttys, c[0])
		if strings.Contains(c[2], "focused") {
			watching = append(watching, c[0])
			if c[1] == session {
				focused = true
			}
		}
	}
	// tmux keeps calling a client focused after you switch to another app,
	// so ask the system which app is in front.
	if front, ok := terminalInFront(); ok && !front {
		focused, watching = false, nil
	}
	if active && focused {
		// You are looking at it: a finished turn is nothing to tell you.
		if state == "done" {
			tmux("set-option", "-wu", "-t", p, "@home_agent")
		} else {
			tmux("set-option", "-w", "-t", p, "@home_agent", state)
		}
		return
	}
	tmux("set-option", "-w", "-t", p, "@home_agent", state)
	if was == state || os.Getenv("HOME_NOTIFY") == "0" {
		return
	}
	text := who + " finished working · " + where
	if state == "waiting" {
		text = who + " needs your input · " + where
	}
	// In the terminal but in another window: the terminal does not raise a
	// notification for itself, so say it in the tmux message line.
	for _, c := range watching {
		tmux("display-message", "-c", c, "-d", "2000", text)
	}
	notify(ttys, text)
}

// notify asks the terminal for a desktop notification with OSC 9, which
// Ghostty (and iTerm2, WezTerm, kitty) turn into a system notification. It
// is written straight to the terminal of each tmux client, past tmux.
func notify(ttys []string, text string) {
	text = strings.Map(func(r rune) rune {
		if r < 0x20 || r == 0x7f {
			return ' '
		}
		return r
	}, text)
	for _, tty := range ttys {
		if f, err := os.OpenFile(tty, os.O_WRONLY, 0); err == nil {
			f.WriteString("\x1b]9;" + text + "\x1b\\")
			f.Close()
		}
	}
}

// cmdNext jumps to a window whose agent waits for you: first one asking for
// input, then one that finished (prefix+a).
func cmdNext(client string) error {
	out, err := tmux("list-windows", "-a", "-F", "#{window_id}\t#{@home_agent}\t#{&&:#{window_active},#{session_attached}}")
	if err != nil {
		return err
	}
	for _, want := range []string{"waiting", "done"} {
		for _, line := range strings.Split(out, "\n") {
			f := strings.Split(line, "\t")
			if len(f) < 3 || f[1] != want || f[2] == "1" {
				continue
			}
			args := []string{"switch-client", "-t", f[0]}
			if client != "" {
				args = append(args, "-c", client)
			}
			_, err := tmux(args...)
			return err
		}
	}
	tmux("display-message", "home: no agent is waiting for you")
	return nil
}

// terminalInFront reports whether the frontmost macOS app is the terminal
// tmux runs in (TERM_PROGRAM of the tmux server, "ghostty"). ok is false
// when that cannot be told, as on other systems.
func terminalInFront() (front, ok bool) {
	asn, err := run("", "lsappinfo", "front")
	if err != nil || asn == "" {
		return false, false
	}
	app, err := run("", "lsappinfo", "info", "-only", "bundleid", asn)
	if err != nil {
		return false, false
	}
	env, err := tmux("show-environment", "-g", "TERM_PROGRAM")
	_, term, found := strings.Cut(env, "=")
	if err != nil || !found || term == "" {
		return false, false
	}
	return strings.Contains(strings.ToLower(app), strings.ToLower(term)), true
}
