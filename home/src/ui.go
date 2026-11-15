package main

import (
	"fmt"
	"sort"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
)

// One generic fuzzy list. Every command is a screen: a loader for its rows
// and what Enter (and a few extra keys) do with the selected row.

type item struct {
	key  string // what the filter matches on
	line string // the rendered row
	val  any
}

type keybind struct {
	key, hint string
	fn        func(item) tea.Cmd
}

type screen struct {
	title string
	load  func() ([]item, error)
	enter func(item) tea.Cmd
	verb  string    // hint for Enter
	busy  string    // shown while Enter is working; empty when it is instant
	keys  []keybind // extra keys
	empty string    // shown when there are no rows

	items   []item
	shown   []item
	loading bool
	err     error
	filter  string
	cursor  int
	top     int
}

type (
	loadedMsg struct {
		s     *screen
		items []item
		err   error
	}
	statusMsg struct {
		text string
		ok   bool
	}
	pushMsg   struct{ s *screen }
	reloadMsg struct{ text string }
	// doneMsg closes the picker; after (if any) then takes over the terminal.
	doneMsg struct{ after func() error }
)

func status(err error) tea.Msg { return statusMsg{err.Error(), false} }

func loadCmd(s *screen) tea.Cmd {
	s.loading = true
	return func() tea.Msg {
		items, err := s.load()
		return loadedMsg{s, items, err}
	}
}

// score rates text against the query: every word must match, as a substring
// (better, and better still near the start) or as letters in order inside
// one word of the text ("mwb" finds my-web).
func score(text, query string) (int, bool) {
	total := 0
	for word := range strings.FieldsSeq(query) {
		if i := strings.Index(text, word); i >= 0 {
			total += 100 - min(i, 50)
			continue
		}
		found := false
		for target := range strings.FieldsSeq(text) {
			if inOrder(target, word) {
				found = true
				break
			}
		}
		if !found {
			return 0, false
		}
		total += 10
	}
	return total, true
}

func inOrder(text, letters string) bool {
	for _, r := range letters {
		i := strings.IndexRune(text, r)
		if i < 0 {
			return false
		}
		text = text[i+len(string(r)):]
	}
	return true
}

func (s *screen) refilter() {
	q := strings.ToLower(strings.TrimSpace(s.filter))
	if q == "" {
		s.shown = s.items
	} else {
		type hit struct {
			it item
			n  int
		}
		var hits []hit
		for _, it := range s.items {
			if n, ok := score(strings.ToLower(it.key), q); ok {
				hits = append(hits, hit{it, n})
			}
		}
		sort.SliceStable(hits, func(i, j int) bool { return hits[i].n > hits[j].n })
		s.shown = make([]item, len(hits))
		for i, h := range hits {
			s.shown[i] = h.it
		}
	}
	if s.cursor >= len(s.shown) {
		s.cursor = max(len(s.shown)-1, 0)
	}
}

func (s *screen) setFilter(f string) {
	s.filter = f
	s.cursor, s.top = 0, 0
	s.refilter()
}

func (s *screen) current() (item, bool) {
	if s.cursor < len(s.shown) {
		return s.shown[s.cursor], true
	}
	return item{}, false
}

type app struct {
	stack    []*screen
	width    int
	height   int
	status   string
	statusOK bool
	busy     string
	after    func() error
}

func (a *app) top() *screen { return a.stack[len(a.stack)-1] }

func (a *app) Init() tea.Cmd { return loadCmd(a.top()) }

func (a *app) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		a.width, a.height = msg.Width, msg.Height
	case loadedMsg:
		msg.s.loading, msg.s.items, msg.s.err = false, msg.items, msg.err
		msg.s.refilter()
	case statusMsg:
		a.busy, a.status, a.statusOK = "", msg.text, msg.ok
	case pushMsg:
		a.busy, a.status = "", ""
		a.stack = append(a.stack, msg.s)
		return a, loadCmd(msg.s)
	case reloadMsg:
		a.busy, a.status, a.statusOK = "", msg.text, true
		return a, loadCmd(a.top())
	case doneMsg:
		a.after = msg.after
		return a, tea.Quit
	case tea.KeyMsg:
		return a.key(msg)
	}
	return a, nil
}

func (a *app) key(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	s := a.top()
	k := msg.String()
	if k == "ctrl+c" {
		return a, tea.Quit
	}
	if a.busy != "" {
		return a, nil
	}
	rows := max(a.height-4, 1)
	switch k {
	case "esc":
		switch {
		case s.filter != "":
			s.setFilter("")
		case len(a.stack) > 1:
			a.stack = a.stack[:len(a.stack)-1]
			a.status = ""
		default:
			return a, tea.Quit
		}
	case "up", "ctrl+p", "ctrl+k":
		s.cursor = max(s.cursor-1, 0)
	case "down", "ctrl+n", "ctrl+j":
		s.cursor = max(min(s.cursor+1, len(s.shown)-1), 0)
	case "pgup":
		s.cursor = max(s.cursor-rows, 0)
	case "pgdown":
		s.cursor = max(min(s.cursor+rows, len(s.shown)-1), 0)
	case "enter":
		if it, ok := s.current(); ok && s.enter != nil {
			a.busy, a.status = s.busy, ""
			return a, s.enter(it)
		}
	case "backspace":
		if r := []rune(s.filter); len(r) > 0 {
			s.setFilter(string(r[:len(r)-1]))
		}
	case "ctrl+u":
		s.setFilter("")
	case "ctrl+w":
		f := strings.TrimRight(s.filter, " ")
		s.setFilter(f[:strings.LastIndex(f, " ")+1])
	case "ctrl+r":
		a.status = ""
		return a, loadCmd(s)
	default:
		for _, kb := range s.keys {
			if kb.key == k {
				if it, ok := s.current(); ok {
					a.status = ""
					return a, kb.fn(it)
				}
				return a, nil
			}
		}
		if (msg.Type == tea.KeyRunes || msg.Type == tea.KeySpace) && !msg.Alt {
			s.setFilter(s.filter + string(msg.Runes))
		}
	}
	return a, nil
}

func (a *app) View() string {
	if a.width == 0 {
		return ""
	}
	s := a.top()

	crumbs := sTitle.Render(" home")
	for _, sc := range a.stack {
		if sc.title != "" {
			crumbs += sGray.Render(" › ") + sText.Render(sc.title)
		}
	}
	count := ""
	if !s.loading && s.err == nil {
		count = fmt.Sprintf("%d", len(s.shown))
		if len(s.shown) != len(s.items) {
			count = fmt.Sprintf("%d/%d", len(s.shown), len(s.items))
		}
	}
	head := crumbs + "  " + sGray.Render(count)
	prompt := sAccent.Render(" ❯ ") + sText.Render(s.filter) + sAccent.Render("▏")

	rows := max(a.height-4, 1)
	if s.cursor < s.top {
		s.top = s.cursor
	}
	if s.cursor >= s.top+rows {
		s.top = s.cursor - rows + 1
	}
	var body []string
	switch {
	case s.loading && len(s.items) == 0:
		body = append(body, sGray.Render("   loading…"))
	case s.err != nil:
		body = append(body, "   "+sErr.Render(s.err.Error()))
	case len(s.items) == 0:
		body = append(body, sGray.Render("   "+s.empty))
	case len(s.shown) == 0:
		body = append(body, sGray.Render("   nothing matches"))
	}
	if s.err == nil {
		for i := s.top; i < len(s.shown) && i < s.top+rows; i++ {
			mark := "   "
			if i == s.cursor {
				mark = sAccent.Render(" ▎ ")
			}
			body = append(body, trunc(mark+s.shown[i].line, a.width))
		}
	}
	for len(body) < rows {
		body = append(body, "")
	}

	line := ""
	switch {
	case a.busy != "":
		line = " " + sWarn.Render(a.busy)
	case a.status != "" && a.statusOK:
		line = " " + sOK.Render(a.status)
	case a.status != "":
		line = " " + sErr.Render(a.status)
	}

	hint := func(k, what string) string { return sAccent.Render(k) + sGray.Render(" "+what) }
	var hints []string
	if s.enter != nil {
		hints = append(hints, hint("enter", s.verb))
	}
	for _, kb := range s.keys {
		hints = append(hints, hint(strings.Replace(kb.key, "ctrl+", "^", 1), kb.hint))
	}
	back := "quit"
	if len(a.stack) > 1 {
		back = "back"
	}
	hints = append(hints, hint("^r", "reload"), hint("esc", back))
	foot := " " + strings.Join(hints, sGray.Render(" · "))

	return strings.Join([]string{trunc(head, a.width), prompt, strings.Join(body[:rows], "\n"), trunc(line, a.width), trunc(foot, a.width)}, "\n")
}

// runTUI shows the picker starting at s. When a row hands the terminal to
// another program (pf, nvim outside tmux), that happens after the picker
// has cleaned up.
func runTUI(s *screen) error {
	a := &app{stack: []*screen{s}}
	if _, err := tea.NewProgram(a, tea.WithAltScreen()).Run(); err != nil {
		return err
	}
	if a.after != nil {
		return a.after()
	}
	return nil
}
