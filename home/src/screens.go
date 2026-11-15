package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"

	tea "github.com/charmbracelet/bubbletea"
)

func reviewArgs(number int) []string { return []string{"nvim", fmt.Sprintf("+PR review %d", number)} }

// -- the menu ------------------------------------------------------------------

type action struct {
	name, about string
	run         func() tea.Msg
}

// menuScreen is the picker behind prefix+Space: the actions, then every port
// forward, so that typing a few letters of its name and Enter toggles it.
func menuScreen() *screen {
	push := func(s func() *screen) func() tea.Msg {
		return func() tea.Msg { return pushMsg{s()} }
	}
	actions := []action{
		{"Review a pull request", "waiting for your review, or yours; opens in a worktree", push(pullScreen)},
		{"Open a repository", "a linked repository or one of its worktrees, in a new window", push(repoScreen)},
		{"Sessions", "switch to a tmux session or start a tmuxinator project", push(sessionScreen)},
		{"Worktrees", "the review worktrees home made; remove the finished ones", push(worktreeScreen)},
		{"Next agent", "go to a window where an agent waits for you", func() tea.Msg {
			if err := cmdNext(""); err != nil {
				return status(err)
			}
			return doneMsg{}
		}},
		{"Port forward dashboard", "logs and details (pf)", func() tea.Msg {
			if _, err := exec.LookPath("pf"); err != nil {
				return status(fmt.Errorf("pf is not installed"))
			}
			return doneMsg{after: execv("", "pf")}
		}},
	}
	return &screen{
		verb: "run",
		busy: "working…",
		load: func() ([]item, error) {
			forwards := loadForwards()
			rows := make([][]string, 0, len(actions)+len(forwards))
			vals := make([]action, 0, cap(rows))
			for _, a := range actions {
				rows = append(rows, []string{sAccent.Render("›"), sText.Render(a.name), sGray.Render(a.about)})
				vals = append(vals, a)
			}
			for _, f := range forwards {
				verb := "start"
				if f.state == "running" {
					verb = "stop"
				}
				rows = append(rows, []string{forwardIcon(f.state), sText.Render(f.name), sGray.Render(verb + " · :" + f.port + " · " + f.state)})
				vals = append(vals, action{name: "forward " + f.name, run: func() tea.Msg { return toggleForward(f) }})
			}
			items := make([]item, len(vals))
			for i, line := range columns(rows) {
				items[i] = item{key: vals[i].name, line: line, val: vals[i]}
			}
			return items, nil
		},
		enter: func(it item) tea.Cmd { return it.val.(action).run },
	}
}

// -- port forwards ---------------------------------------------------------------

type forward struct{ name, port, state string }

// loadForwards asks pf for its forwards; none when pf is not installed.
func loadForwards() []forward {
	out, err := exec.Command("pf", "state").Output()
	if err != nil {
		return nil
	}
	var fs []forward
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if f := strings.Split(line, "\t"); len(f) >= 3 {
			fs = append(fs, forward{f[0], f[1], f[2]})
		}
	}
	return fs
}

func forwardIcon(state string) string {
	switch state {
	case "running":
		return sOK.Render("●")
	case "died":
		return sErr.Render("✗")
	case "busy":
		return sWarn.Render("!")
	}
	return sGray.Render("○")
}

// toggleForward starts or stops a forward and closes the picker, leaving the
// outcome in the tmux message line. A port held by something pf did not
// start is left to the dashboard, which asks before killing.
func toggleForward(f forward) tea.Msg {
	if f.state == "busy" {
		return statusMsg{fmt.Sprintf("port :%s is held by something else; use the dashboard", f.port), false}
	}
	out, err := exec.Command("pf", "toggle", f.name).CombinedOutput()
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	last := lines[len(lines)-1]
	if err != nil {
		return statusMsg{last, false}
	}
	if inTmux() {
		tmux("display-message", "pf: "+last)
		return doneMsg{}
	}
	return reloadMsg{last}
}

// -- sessions --------------------------------------------------------------------

type session struct {
	name    string
	project bool // a tmuxinator project that is not running
}

func sessionScreen() *screen {
	return &screen{
		title: "sessions",
		verb:  "switch / start",
		empty: "no tmux sessions and no tmuxinator projects",
		load: func() ([]item, error) {
			var rows [][]string
			var vals []session
			running := map[string]bool{}
			if out, err := run("", "tmux", "list-sessions", "-F", "#{session_name}\t#{session_windows}\t#{session_attached}"); err == nil && out != "" {
				for _, line := range strings.Split(out, "\n") {
					f := strings.Split(line, "\t")
					if len(f) < 3 {
						continue
					}
					running[f[0]] = true
					state := sOK.Render("●")
					note := f[1] + " windows"
					if f[2] != "0" {
						note += ", attached"
					}
					rows = append(rows, []string{state, sText.Render(f[0]), sGray.Render(note)})
					vals = append(vals, session{name: f[0]})
				}
			}
			files, _ := filepath.Glob(filepath.Join(os.Getenv("HOME"), ".config/tmuxinator/*.yml"))
			sort.Strings(files)
			for _, f := range files {
				name := strings.TrimSuffix(filepath.Base(f), ".yml")
				if running[name] {
					continue
				}
				rows = append(rows, []string{sGray.Render("○"), sDim.Render(name), sGray.Render("tmuxinator project")})
				vals = append(vals, session{name: name, project: true})
			}
			items := make([]item, len(vals))
			for i, line := range columns(rows) {
				items[i] = item{key: vals[i].name, line: line, val: vals[i]}
			}
			return items, nil
		},
		enter: func(it item) tea.Cmd {
			s := it.val.(session)
			return func() tea.Msg {
				switch {
				case s.project:
					return doneMsg{after: execv("", "tmuxinator", "start", s.name)}
				case inTmux():
					if _, err := run("", "tmux", "switch-client", "-t", "="+s.name); err != nil {
						return status(err)
					}
					return doneMsg{}
				}
				return doneMsg{after: execv("", "tmux", "attach-session", "-t", "="+s.name)}
			}
		},
	}
}

// -- workspaces: linked repositories and their worktrees ------------------------

type tree struct {
	repo, path, branch string
	main               bool
}

func repoScreen() *screen {
	return &screen{
		title: "open",
		verb:  "open in a new window",
		empty: "nothing linked yet: run `home link` in a clone, or `home link --root DIR`",
		load: func() ([]item, error) {
			entries := loadRegistry().sorted()
			found := make([][]tree, len(entries))
			var wg sync.WaitGroup
			for i, e := range entries {
				wg.Add(1)
				go func() {
					defer wg.Done()
					for _, w := range worktrees(e.Path) {
						if isDir(w.path) {
							found[i] = append(found[i], tree{e.Name, w.path, w.branch, w.path == e.Path})
						}
					}
				}()
			}
			wg.Wait()
			var trees []tree
			var rows [][]string
			for _, list := range found {
				for _, t := range list {
					name, branch := sText.Render(filepath.Base(t.path)), t.branch
					if !t.main {
						name = sGray.Render("└ ") + sDim.Render(filepath.Base(t.path))
					}
					if branch == "" {
						branch = "detached"
					}
					trees = append(trees, t)
					rows = append(rows, []string{name, sAccent.Render(trunc(branch, 40)), sGray.Render(tilde(filepath.Dir(t.path)))})
				}
			}
			items := make([]item, len(trees))
			for i, line := range columns(rows) {
				items[i] = item{key: trees[i].repo + " " + filepath.Base(trees[i].path) + " " + trees[i].branch, line: line, val: trees[i]}
			}
			return items, nil
		},
		enter: func(it item) tea.Cmd {
			t := it.val.(tree)
			return func() tea.Msg { return open(filepath.Base(t.path), t.path) }
		},
	}
}

// -- review worktrees ------------------------------------------------------------

type reviewTree struct {
	repo, clone, path string
	number            int
	state, title      string
}

var reviewTreeName = regexp.MustCompile(`-pr-(\d+)$`)

// loadReviewTrees finds the <clone>-pr-<number> worktrees of every linked
// repository and asks GitHub what became of each pull request.
func loadReviewTrees() ([]item, error) {
	var (
		mu    sync.Mutex
		wg    sync.WaitGroup
		trees []*reviewTree
	)
	for _, e := range loadRegistry().sorted() {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for _, w := range worktrees(e.Path) {
				m := reviewTreeName.FindStringSubmatch(w.path)
				if m == nil || !strings.HasPrefix(w.path, e.Path+"-pr-") || !isDir(w.path) {
					continue
				}
				n, _ := strconv.Atoi(m[1])
				t := &reviewTree{repo: e.Name, clone: e.Path, path: w.path, number: n, state: "?"}
				if out, err := run("", "gh", "pr", "view", m[1], "-R", e.Name, "--json", "state,title"); err == nil {
					var v struct{ State, Title string }
					if json.Unmarshal([]byte(out), &v) == nil {
						t.state, t.title = strings.ToLower(v.State), v.Title
					}
				}
				mu.Lock()
				trees = append(trees, t)
				mu.Unlock()
			}
		}()
	}
	wg.Wait()
	sort.Slice(trees, func(i, j int) bool { return trees[i].path < trees[j].path })

	rows := make([][]string, len(trees))
	for i, t := range trees {
		state := sGray.Render(t.state)
		switch t.state {
		case "open":
			state = sOK.Render(t.state)
		case "merged":
			state = sAccent.Render(t.state)
		case "closed":
			state = sErr.Render(t.state)
		}
		rows[i] = []string{sText.Render(filepath.Base(t.repo)), sDim.Render(fmt.Sprintf("#%d", t.number)), state, trunc(t.title, 60), sGray.Render(tilde(t.path))}
	}
	items := make([]item, len(trees))
	for i, line := range columns(rows) {
		t := trees[i]
		items[i] = item{key: fmt.Sprintf("%s #%d %s %s", t.repo, t.number, t.state, t.title), line: line, val: *t}
	}
	return items, nil
}

func worktreeScreen() *screen {
	return &screen{
		title: "worktrees",
		load:  loadReviewTrees,
		verb:  "review",
		empty: "no review worktrees",
		enter: func(it item) tea.Cmd {
			t := it.val.(reviewTree)
			return func() tea.Msg {
				return open(fmt.Sprintf("%s#%d", filepath.Base(t.repo), t.number), t.path, reviewArgs(t.number)...)
			}
		},
		// No --force: git refuses when the worktree has changes or untracked
		// files, and that refusal is shown.
		keys: []keybind{{"ctrl+x", "remove", func(it item) tea.Cmd {
			t := it.val.(reviewTree)
			return func() tea.Msg {
				if _, err := run(t.clone, "git", "worktree", "remove", t.path); err != nil {
					return status(err)
				}
				return reloadMsg{"removed " + tilde(t.path)}
			}
		}}},
	}
}
