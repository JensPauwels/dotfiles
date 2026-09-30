// pf-tui: a small dashboard for the port forwards managed by the `pf` script.
// All process management goes through `pf` (which sits next to this binary);
// this program only renders state, tails logs and asks before killing.
package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type fwd struct {
	Name, Port, State, Pid, Owner, Cmd string
}

type model struct {
	items    []fwd
	cursor   int
	width    int
	height   int
	status   string // one-line message under the panes
	statusOK bool
	confirm  *fwd   // waiting for y/n to kill what holds this port
	pending  string // verb to run after confirmation
	logLines []string
	help     bool
	inflight int
}

type (
	stateMsg  struct{ items []fwd }
	stateErr  struct{ err error }
	actionMsg struct{ out string; err error }
	logMsg    []string
	tickMsg   struct{}
)

var (
	pfScript = findScript()
	stateDir = envOr("PF_STATE", filepath.Join(os.Getenv("HOME"), ".local/state/pf"))

	// Catppuccin Mocha
	cGreen  = lipgloss.Color("#a6e3a1")
	cRed    = lipgloss.Color("#f38ba8")
	cYellow = lipgloss.Color("#f9e2af")
	cMauve  = lipgloss.Color("#cba6f7")
	cBlue   = lipgloss.Color("#89b4fa")
	cDim    = lipgloss.Color("#6c7086")
	cText   = lipgloss.Color("#cdd6f4")
	cSurf   = lipgloss.Color("#313244")

	sTitle    = lipgloss.NewStyle().Bold(true).Foreground(cMauve)
	sDim      = lipgloss.NewStyle().Foreground(cDim)
	sKey      = lipgloss.NewStyle().Foreground(cBlue)
	sCursor   = lipgloss.NewStyle().Background(cSurf).Bold(true)
	sOK       = lipgloss.NewStyle().Foreground(cGreen)
	sErr      = lipgloss.NewStyle().Foreground(cRed)
	sWarn     = lipgloss.NewStyle().Foreground(cYellow).Bold(true)
	sPane     = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(cDim).Padding(0, 1)
	sPaneFoc  = sPane.BorderForeground(cMauve)
	sLogLine  = lipgloss.NewStyle().Foreground(cText)
)

func envOr(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

func findScript() string {
	if exe, err := os.Executable(); err == nil {
		if real, err := filepath.EvalSymlinks(exe); err == nil {
			p := filepath.Join(filepath.Dir(real), "pf")
			if st, err := os.Stat(p); err == nil && st.Mode()&0o111 != 0 {
				return p
			}
		}
	}
	return "pf"
}

func loadState() tea.Msg {
	out, err := exec.Command(pfScript, "state").Output()
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok && len(ee.Stderr) > 0 {
			return stateErr{fmt.Errorf("%s", strings.TrimSpace(string(ee.Stderr)))}
		}
		return stateErr{err}
	}
	var items []fwd
	for _, line := range strings.Split(strings.TrimRight(string(out), "\n"), "\n") {
		f := strings.SplitN(line, "\t", 6)
		if len(f) < 6 {
			continue
		}
		items = append(items, fwd{f[0], f[1], f[2], f[3], f[4], f[5]})
	}
	return stateMsg{items}
}

func runAction(verb, name string) tea.Cmd {
	return func() tea.Msg {
		out, err := exec.Command(pfScript, verb, "-f", name).CombinedOutput()
		return actionMsg{strings.TrimSpace(string(out)), err}
	}
}

func stopAll() tea.Msg {
	out, err := exec.Command(pfScript, "stop", "--all").CombinedOutput()
	return actionMsg{strings.TrimSpace(string(out)), err}
}

func loadLog(name string, n int) tea.Cmd {
	return func() tea.Msg {
		if name == "" {
			return logMsg(nil)
		}
		f, err := os.Open(filepath.Join(stateDir, name+".log"))
		if err != nil {
			return logMsg(nil)
		}
		defer f.Close()
		var lines []string
		sc := bufio.NewScanner(f)
		sc.Buffer(make([]byte, 1024*1024), 1024*1024)
		for sc.Scan() {
			lines = append(lines, sc.Text())
			if len(lines) > n {
				lines = lines[1:]
			}
		}
		return logMsg(lines)
	}
}

func tick() tea.Cmd {
	return tea.Tick(time.Second, func(time.Time) tea.Msg { return tickMsg{} })
}

func (m model) Init() tea.Cmd {
	return tea.Batch(loadState, tick())
}

func (m model) current() *fwd {
	if len(m.items) == 0 || m.cursor >= len(m.items) {
		return nil
	}
	return &m.items[m.cursor]
}

func (m model) logCapacity() int {
	// pane height minus header, details (4 lines), separator, borders
	n := m.height - 4 - 4 - 2 - 2
	if n < 3 {
		n = 3
	}
	return n
}

func (m model) refreshLog() tea.Cmd {
	if c := m.current(); c != nil {
		return loadLog(c.Name, m.logCapacity())
	}
	return nil
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		return m, m.refreshLog()

	case tickMsg:
		return m, tea.Batch(loadState, m.refreshLog(), tick())

	case stateMsg:
		prev := ""
		if c := m.current(); c != nil {
			prev = c.Name
		}
		m.items = msg.items
		if prev != "" {
			for i, it := range m.items {
				if it.Name == prev {
					m.cursor = i
				}
			}
		}
		if m.cursor >= len(m.items) && len(m.items) > 0 {
			m.cursor = len(m.items) - 1
		}
		return m, nil

	case stateErr:
		m.status, m.statusOK = msg.err.Error(), false
		return m, nil

	case actionMsg:
		m.inflight--
		lines := strings.Split(msg.out, "\n")
		m.status, m.statusOK = lines[len(lines)-1], msg.err == nil
		if msg.err != nil && len(lines) > 1 {
			m.status = strings.Join(lines, " · ")
		}
		return m, tea.Batch(loadState, m.refreshLog())

	case logMsg:
		m.logLines = msg
		return m, nil

	case tea.KeyMsg:
		return m.handleKey(msg)
	}
	return m, nil
}

func (m model) act(verb string) (tea.Model, tea.Cmd) {
	c := m.current()
	if c == nil {
		return m, nil
	}
	if c.State == "busy" && (verb == "toggle" || verb == "start" || verb == "stop" || verb == "restart") {
		m.confirm, m.pending = c, verb
		return m, nil
	}
	m.inflight++
	m.status, m.statusOK = fmt.Sprintf("%s %s…", verb, c.Name), true
	return m, runAction(verb, c.Name)
}

func (m model) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	if m.confirm != nil {
		switch msg.String() {
		case "y", "Y", "enter":
			c, verb := m.confirm, m.pending
			m.confirm, m.pending = nil, ""
			m.inflight++
			m.status, m.statusOK = fmt.Sprintf("freeing :%s and running %s…", c.Port, verb), true
			return m, runAction(verb, c.Name)
		default:
			m.confirm, m.pending = nil, ""
			m.status, m.statusOK = "left it alone", true
			return m, nil
		}
	}
	if m.help {
		m.help = false
		return m, nil
	}
	switch msg.String() {
	case "q", "ctrl+c", "esc":
		return m, tea.Quit
	case "j", "down":
		if m.cursor < len(m.items)-1 {
			m.cursor++
		}
		return m, m.refreshLog()
	case "k", "up":
		if m.cursor > 0 {
			m.cursor--
		}
		return m, m.refreshLog()
	case "g", "home":
		m.cursor = 0
		return m, m.refreshLog()
	case "G", "end":
		if len(m.items) > 0 {
			m.cursor = len(m.items) - 1
		}
		return m, m.refreshLog()
	case "enter", " ":
		return m.act("toggle")
	case "s":
		return m.act("start")
	case "x":
		return m.act("stop")
	case "r":
		return m.act("restart")
	case "S":
		m.inflight++
		m.status, m.statusOK = "stopping everything…", true
		return m, stopAll
	case "R":
		return m, loadState
	case "e":
		editor := envOr("EDITOR", "nvim")
		cfg := envOr("PF_CONFIG", filepath.Join(os.Getenv("HOME"), ".config/pf/forwards"))
		c := exec.Command(editor, cfg)
		return m, tea.ExecProcess(c, func(error) tea.Msg { return tickMsg{} })
	case "?":
		m.help = true
	}
	return m, nil
}

func icon(state string) string {
	switch state {
	case "running":
		return sOK.Render("●")
	case "died":
		return sErr.Render("✗")
	case "busy":
		return sWarn.Render("!")
	}
	return sDim.Render("○")
}

func trunc(s string, w int) string {
	if w <= 0 {
		return ""
	}
	r := []rune(s)
	if len(r) <= w {
		return s
	}
	if w == 1 {
		return "…"
	}
	return string(r[:w-1]) + "…"
}

func (m model) View() string {
	if m.width == 0 {
		return "loading…"
	}
	if m.help {
		return m.helpView()
	}
	running := 0
	for _, it := range m.items {
		if it.State == "running" {
			running++
		}
	}
	header := lipgloss.JoinHorizontal(lipgloss.Top,
		sTitle.Render(" pf "),
		sDim.Render(fmt.Sprintf(" %d forwards · %d running", len(m.items), running)),
	)

	listW := 44
	if m.width < 100 {
		listW = m.width * 45 / 100
	}
	if listW > m.width-30 {
		listW = m.width - 30
	}
	detailW := m.width - listW - 6
	paneH := m.height - 4
	if paneH < 5 {
		paneH = 5
	}

	// left: the list
	var rows []string
	nameW := 20
	for _, it := range m.items {
		if len(it.Name) > nameW {
			nameW = len(it.Name)
		}
	}
	for i, it := range m.items {
		line := fmt.Sprintf("%s %-*s :%-5s %s", icon(it.State), nameW, it.Name, it.Port, sDim.Render(it.State))
		if i == m.cursor {
			line = sCursor.Render("▎") + line
		} else {
			line = " " + line
		}
		rows = append(rows, trunc(line, listW-2))
	}
	if len(rows) == 0 {
		rows = append(rows, sDim.Render("no forwards defined, press e to add some"))
	}
	for len(rows) < paneH-2 {
		rows = append(rows, "")
	}
	left := sPane.Width(listW).Height(paneH - 2).Render(strings.Join(rows[:min(len(rows), paneH-2)], "\n"))

	// right: details + log of the selected forward
	var d []string
	if c := m.current(); c != nil {
		state := c.State
		if c.Pid != "" {
			state += " · pid " + c.Pid
		}
		d = append(d,
			sTitle.Render(c.Name),
			sDim.Render("state    ")+state,
			sDim.Render("port     ")+"127.0.0.1:"+c.Port,
			sDim.Render("command  ")+trunc(c.Cmd, detailW-9),
		)
		if c.State == "busy" {
			d = append(d, sWarn.Render("owner    ")+trunc(c.Owner, detailW-9))
		}
		d = append(d, sDim.Render(strings.Repeat("─", max(detailW, 1))))
		for _, l := range m.logLines {
			d = append(d, sLogLine.Render(trunc(l, detailW)))
		}
	}
	for len(d) < paneH-2 {
		d = append(d, "")
	}
	right := sPaneFoc.Width(detailW + 2).Height(paneH - 2).Render(strings.Join(d[:min(len(d), paneH-2)], "\n"))

	body := lipgloss.JoinHorizontal(lipgloss.Top, left, right)

	// bottom: status / confirmation, then key hints
	var status string
	switch {
	case m.confirm != nil:
		verb := "kill it?"
		if strings.HasPrefix(m.confirm.Owner, "docker container ") {
			verb = "stop the container?"
		}
		status = sWarn.Render(fmt.Sprintf(" port :%s is held by %s — %s ", m.confirm.Port, trunc(m.confirm.Owner, m.width-50), verb)) + sKey.Render("y") + sDim.Render("/") + sKey.Render("n")
	case m.status != "":
		if m.statusOK {
			status = " " + m.status
		} else {
			status = " " + sErr.Render(m.status)
		}
	}
	hint := func(k, what string) string { return sKey.Render(k) + sDim.Render(" "+what) }
	keys := " " + strings.Join([]string{
		hint("enter", "toggle"), hint("x", "stop"), hint("r", "restart"), hint("S", "stop all"),
		hint("e", "edit"), hint("?", "help"), hint("q", "quit"),
	}, sDim.Render("  ·  "))

	return strings.Join([]string{header, body, trunc(status, m.width), keys}, "\n")
}

func (m model) helpView() string {
	lines := []string{
		sTitle.Render(" pf — keys"),
		"",
		"  j / k, ↑ / ↓    move          g / G   first / last",
		"  enter, space    toggle the selected forward",
		"  s / x / r       start / stop / restart",
		"  S               stop every running forward",
		"  e               edit the definitions file ($EDITOR)",
		"  R               refresh now (also happens every second)",
		"  q, esc          quit; forwards keep running",
		"",
		"  " + icon("running") + " running   " + icon("stopped") + " stopped   " + icon("died") + " died on its own   " + icon("busy") + " port held by something else",
		"",
		sDim.Render("  Toggling a busy forward asks before killing the process on that port."),
		sDim.Render("  Logs and pids: " + stateDir),
		"",
		sDim.Render("  press any key to go back"),
	}
	return strings.Join(lines, "\n")
}

func main() {
	p := tea.NewProgram(model{}, tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "pf-tui:", err)
		os.Exit(1)
	}
}
