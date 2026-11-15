package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"
)

// Aura Soft Dark, the palette of the rest of the dotfiles.
var (
	cPurple = lipgloss.Color("#a277ff")
	cGreen  = lipgloss.Color("#61ffca")
	cOrange = lipgloss.Color("#ffca85")
	cRed    = lipgloss.Color("#ff6767")
	cFg     = lipgloss.Color("#edecee")
	cDim    = lipgloss.Color("#b4b2c0")
	cGray   = lipgloss.Color("#6d6d6d")

	sTitle  = lipgloss.NewStyle().Bold(true).Foreground(cPurple)
	sText   = lipgloss.NewStyle().Foreground(cFg)
	sDim    = lipgloss.NewStyle().Foreground(cDim)
	sGray   = lipgloss.NewStyle().Foreground(cGray)
	sOK     = lipgloss.NewStyle().Foreground(cGreen)
	sWarn   = lipgloss.NewStyle().Foreground(cOrange)
	sErr    = lipgloss.NewStyle().Foreground(cRed)
	sAccent = lipgloss.NewStyle().Foreground(cPurple)
)

func envOr(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

func isDir(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.IsDir()
}

// tilde shortens the home directory to ~ for display.
func tilde(p string) string {
	if h := os.Getenv("HOME"); h != "" && strings.HasPrefix(p, h+"/") {
		return "~" + p[len(h):]
	}
	return p
}

// run executes a command in dir and returns its trimmed stdout. On failure
// the error carries the last line of stderr, which is what git and gh put
// the reason on.
func run(dir, name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		msg := strings.TrimSpace(stderr.String())
		if i := strings.LastIndex(msg, "\n"); i >= 0 {
			msg = msg[i+1:]
		}
		if msg == "" {
			msg = err.Error()
		}
		return "", fmt.Errorf("%s %s: %s", name, firstArg(args), msg)
	}
	return strings.TrimSpace(string(out)), nil
}

func firstArg(args []string) string {
	for _, a := range args {
		if !strings.HasPrefix(a, "-") && !filepath.IsAbs(a) {
			return a
		}
	}
	return ""
}

// execv returns a function that replaces this process with argv, started in
// dir. It runs after the picker has given the terminal back.
func execv(dir string, argv ...string) func() error {
	return func() error {
		if dir != "" {
			if err := os.Chdir(dir); err != nil {
				return err
			}
		}
		bin, err := exec.LookPath(argv[0])
		if err != nil {
			return err
		}
		return syscall.Exec(bin, argv, os.Environ())
	}
}

func trunc(s string, w int) string {
	if w <= 0 {
		return ""
	}
	return ansi.Truncate(s, w, "…")
}

// columns pads the cells of every row so the columns line up. Cells may be
// styled; the last column is left unpadded.
func columns(rows [][]string) []string {
	var widths []int
	for _, r := range rows {
		for i, c := range r {
			if i >= len(widths) {
				widths = append(widths, 0)
			}
			if w := lipgloss.Width(c); w > widths[i] {
				widths[i] = w
			}
		}
	}
	out := make([]string, len(rows))
	for n, r := range rows {
		var b strings.Builder
		for i, c := range r {
			b.WriteString(c)
			if i < len(r)-1 {
				b.WriteString(strings.Repeat(" ", widths[i]-lipgloss.Width(c)+2))
			}
		}
		out[n] = b.String()
	}
	return out
}

func age(t time.Time) string {
	d := time.Since(t)
	switch {
	case d < time.Hour:
		return fmt.Sprintf("%dm", int(d.Minutes()))
	case d < 24*time.Hour:
		return fmt.Sprintf("%dh", int(d.Hours()))
	case d < 14*24*time.Hour:
		return fmt.Sprintf("%dd", int(d.Hours()/24))
	case d < 365*24*time.Hour:
		return fmt.Sprintf("%dw", int(d.Hours()/24/7))
	}
	return fmt.Sprintf("%dy", int(d.Hours()/24/365))
}
