package main

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

type pull struct {
	Number     int       `json:"number"`
	Title      string    `json:"title"`
	URL        string    `json:"url"`
	IsDraft    bool      `json:"isDraft"`
	UpdatedAt  time.Time `json:"updatedAt"`
	Repository struct {
		NameWithOwner string `json:"nameWithOwner"`
	} `json:"repository"`
	Author struct {
		Login string `json:"login"`
	} `json:"author"`
	mine bool
}

func searchPulls(qualifier string) ([]pull, error) {
	out, err := run("", "gh", "search", "prs", "--state=open", "--limit=50", qualifier,
		"--json", "number,title,repository,author,updatedAt,isDraft,url")
	if err != nil {
		return nil, err
	}
	var prs []pull
	return prs, json.Unmarshal([]byte(out), &prs)
}

// loadPulls lists the open pull requests waiting for your review, then your
// own.
func loadPulls() ([]item, error) {
	var (
		wg            sync.WaitGroup
		asked, mine   []pull
		errAsk, errMy error
	)
	wg.Add(2)
	go func() { defer wg.Done(); asked, errAsk = searchPulls("--review-requested=@me") }()
	go func() { defer wg.Done(); mine, errMy = searchPulls("--author=@me") }()
	wg.Wait()
	if errAsk != nil {
		return nil, errAsk
	}
	if errMy != nil {
		return nil, errMy
	}
	for i := range mine {
		mine[i].mine = true
	}
	byAge := func(p []pull) {
		sort.SliceStable(p, func(i, j int) bool { return p[i].UpdatedAt.After(p[j].UpdatedAt) })
	}
	byAge(asked)
	byAge(mine)
	prs := append(asked, mine...)

	reg := loadRegistry()
	rows := make([][]string, len(prs))
	for i, p := range prs {
		tag := sAccent.Render("review")
		if p.mine {
			tag = sGray.Render("yours")
		}
		repo := sText.Render(filepath.Base(p.Repository.NameWithOwner))
		if _, ok := reg[strings.ToLower(p.Repository.NameWithOwner)]; !ok {
			repo = sGray.Render(filepath.Base(p.Repository.NameWithOwner) + " (not linked)")
		}
		title := trunc(p.Title, 70)
		if p.IsDraft {
			title = sGray.Render("draft ") + title
		}
		rows[i] = []string{tag, repo, sDim.Render(fmt.Sprintf("#%d", p.Number)), title, sDim.Render(p.Author.Login), sGray.Render(age(p.UpdatedAt))}
	}
	items := make([]item, len(prs))
	for i, line := range columns(rows) {
		p := prs[i]
		items[i] = item{
			key:  fmt.Sprintf("%s #%d %s %s", p.Repository.NameWithOwner, p.Number, p.Title, p.Author.Login),
			line: line,
			val:  p,
		}
	}
	return items, nil
}

func pullScreen() *screen {
	return &screen{
		title: "pull requests",
		load:  loadPulls,
		verb:  "review in a worktree",
		busy:  "preparing the worktree…",
		empty: "no open pull requests waiting for you",
		enter: func(it item) tea.Cmd {
			p := it.val.(pull)
			return func() tea.Msg { return review(p.Repository.NameWithOwner, p.Number) }
		},
		keys: []keybind{{"ctrl+o", "browser", func(it item) tea.Cmd {
			p := it.val.(pull)
			return func() tea.Msg {
				if err := exec.Command("open", p.URL).Run(); err != nil {
					return status(err)
				}
				return statusMsg{"opened " + p.URL, true}
			}
		}}},
	}
}

// review gets a worktree for the pull request and opens Neovim in it, in a
// new window, with pulls.nvim reviewing it.
func review(repo string, number int) tea.Msg {
	dir, err := prepare(repo, number)
	if err != nil {
		return status(err)
	}
	return open(fmt.Sprintf("%s#%d", filepath.Base(repo), number), dir, reviewArgs(number)...)
}

type worktree struct{ path, branch string }

func worktrees(clone string) []worktree {
	out, err := run(clone, "git", "worktree", "list", "--porcelain")
	if err != nil {
		return nil
	}
	var list []worktree
	for _, line := range strings.Split(out, "\n") {
		if p, ok := strings.CutPrefix(line, "worktree "); ok {
			list = append(list, worktree{path: p})
		} else if b, ok := strings.CutPrefix(line, "branch refs/heads/"); ok && len(list) > 0 {
			list[len(list)-1].branch = b
		}
	}
	return list
}

// prepare returns the directory to review pull request `number` of `repo`
// in. A worktree that already has the branch checked out is reused (also
// your own, or the clone itself); otherwise a new one is made next to the
// clone, named <clone>-pr-<number>.
func prepare(repo string, number int) (string, error) {
	entry, ok := loadRegistry()[strings.ToLower(repo)]
	if !ok {
		return "", fmt.Errorf("%s is not linked: run `home link` in its clone", repo)
	}
	clone := entry.Path
	if !isDir(clone) {
		return "", fmt.Errorf("%s is linked to %s, which is gone", repo, tilde(clone))
	}
	num := strconv.Itoa(number)
	out, err := run("", "gh", "pr", "view", num, "-R", repo, "--json", "headRefName,isCrossRepository")
	if err != nil {
		return "", err
	}
	var head struct {
		HeadRefName       string `json:"headRefName"`
		IsCrossRepository bool   `json:"isCrossRepository"`
	}
	if err := json.Unmarshal([]byte(out), &head); err != nil {
		return "", err
	}
	// A fork's branch name says nothing about a local branch of that name.
	if !head.IsCrossRepository {
		for _, w := range worktrees(clone) {
			if w.branch == head.HeadRefName && isDir(w.path) {
				return w.path, nil
			}
		}
	}
	dir := clone + "-pr-" + num
	if isDir(dir) {
		return dir, nil
	}
	if _, err := run(clone, "git", "worktree", "add", "--detach", dir); err != nil {
		return "", err
	}
	if _, err := run(dir, "gh", "pr", "checkout", num, "-R", repo); err != nil {
		run(clone, "git", "worktree", "remove", "--force", dir) // just made, nothing in it
		return "", err
	}
	return dir, nil
}

var pullRef = regexp.MustCompile(`^(?:https://github\.com/)?([^/\s]+/[^/\s#]+)(?:#|/pull/)(\d+)`)

// cmdPR implements `home pr [owner/name#123 | URL]`.
func cmdPR(args []string) error {
	if len(args) == 0 {
		return runTUI(pullScreen())
	}
	m := pullRef.FindStringSubmatch(args[0])
	if m == nil {
		return fmt.Errorf("usage: home pr [OWNER/NAME#NUMBER | URL]")
	}
	number, _ := strconv.Atoi(m[2])
	switch msg := review(m[1], number).(type) {
	case statusMsg:
		return fmt.Errorf("%s", msg.text)
	case doneMsg:
		if msg.after != nil {
			return msg.after()
		}
	}
	return nil
}
