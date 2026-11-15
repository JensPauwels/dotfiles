package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// The registry maps a GitHub repository to its clone on this machine, one
// "owner/name<TAB>path" per line. `home link` writes it.

type repoEntry struct{ Name, Path string }

type registry map[string]repoEntry // keyed by lower-cased owner/name

func registryPath() string {
	return envOr("HOME_REPOS", filepath.Join(os.Getenv("HOME"), ".config/home/repos"))
}

func loadRegistry() registry {
	reg := registry{}
	f, err := os.Open(registryPath())
	if err != nil {
		return reg
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		name, path, ok := strings.Cut(sc.Text(), "\t")
		if !ok || strings.HasPrefix(name, "#") {
			continue
		}
		reg[strings.ToLower(name)] = repoEntry{name, path}
	}
	return reg
}

func (r registry) sorted() []repoEntry {
	out := make([]repoEntry, 0, len(r))
	for _, e := range r {
		out = append(out, e)
	}
	sort.Slice(out, func(i, j int) bool { return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name) })
	return out
}

func (r registry) save() error {
	p := registryPath()
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	var b strings.Builder
	for _, e := range r.sorted() {
		fmt.Fprintf(&b, "%s\t%s\n", e.Name, e.Path)
	}
	return os.WriteFile(p, []byte(b.String()), 0o644)
}

var githubRemote = regexp.MustCompile(`github\.com[:/]([^/\s]+)/([^/\s]+?)(?:\.git)?/?$`)

// repoOf returns the owner/name of the GitHub remote of the clone at path:
// origin, or else the first remote that points at GitHub.
func repoOf(path string) (string, error) {
	remotes, err := run(path, "git", "remote")
	if err != nil {
		return "", err
	}
	names := append([]string{"origin"}, strings.Fields(remotes)...)
	for _, n := range names {
		url, err := run(path, "git", "remote", "get-url", n)
		if err != nil {
			continue
		}
		if m := githubRemote.FindStringSubmatch(url); m != nil {
			return m[1] + "/" + m[2], nil
		}
	}
	return "", fmt.Errorf("no GitHub remote")
}

// mainClone resolves path (anywhere inside a clone or one of its worktrees)
// to the main working tree, the one that owns the .git directory.
func mainClone(path string) (string, error) {
	common, err := run(path, "git", "rev-parse", "--path-format=absolute", "--git-common-dir")
	if err != nil {
		return "", fmt.Errorf("%s is not inside a git repository", tilde(path))
	}
	if filepath.Base(common) != ".git" {
		return "", fmt.Errorf("%s is a bare repository", tilde(common))
	}
	return filepath.Dir(common), nil
}

// findClones walks root and reports every main clone (a directory whose .git
// is a directory; worktrees have a .git file and are skipped). It does not
// look inside a repository.
func findClones(root string, depth int, found func(string)) {
	if st, err := os.Lstat(filepath.Join(root, ".git")); err == nil {
		if st.IsDir() {
			found(root)
		}
		return
	}
	if depth == 0 {
		return
	}
	entries, err := os.ReadDir(root)
	if err != nil {
		return
	}
	for _, e := range entries {
		if !e.IsDir() || strings.HasPrefix(e.Name(), ".") || e.Name() == "node_modules" {
			continue
		}
		findClones(filepath.Join(root, e.Name()), depth-1, found)
	}
}

// cmdLink implements `home link`.
func cmdLink(args []string) error {
	reg := loadRegistry()
	if len(args) > 0 && (args[0] == "-l" || args[0] == "--list") {
		for _, row := range columns(registryRows(reg)) {
			fmt.Println(row)
		}
		return nil
	}
	if len(args) > 0 && (args[0] == "-r" || args[0] == "--root") {
		if len(args) < 2 {
			return fmt.Errorf("usage: home link --root DIR...")
		}
		added := 0
		for _, root := range args[1:] {
			abs, err := filepath.Abs(root)
			if err != nil || !isDir(abs) {
				return fmt.Errorf("%s is not a directory", root)
			}
			findClones(abs, 4, func(path string) {
				name, err := repoOf(path)
				if err != nil {
					fmt.Printf("  skip   %s (%v)\n", tilde(path), err)
					return
				}
				if old, ok := reg[strings.ToLower(name)]; ok && old.Path != path && isDir(old.Path) {
					fmt.Printf("  kept   %s -> %s (also at %s)\n", name, tilde(old.Path), tilde(path))
					return
				}
				reg[strings.ToLower(name)] = repoEntry{name, path}
				fmt.Printf("  link   %s -> %s\n", name, tilde(path))
				added++
			})
		}
		fmt.Printf("%d repositories linked, %d in total\n", added, len(reg))
		return reg.save()
	}

	path := "."
	if len(args) > 0 {
		path = args[0]
	}
	abs, err := filepath.Abs(path)
	if err != nil {
		return err
	}
	clone, err := mainClone(abs)
	if err != nil {
		return err
	}
	name, err := repoOf(clone)
	if err != nil {
		return fmt.Errorf("%s: %v", tilde(clone), err)
	}
	reg[strings.ToLower(name)] = repoEntry{name, clone}
	fmt.Printf("linked %s -> %s\n", name, tilde(clone))
	return reg.save()
}

// cmdUnlink implements `home unlink owner/name`.
func cmdUnlink(args []string) error {
	if len(args) != 1 {
		return fmt.Errorf("usage: home unlink OWNER/NAME")
	}
	reg := loadRegistry()
	key := strings.ToLower(args[0])
	if _, ok := reg[key]; !ok {
		return fmt.Errorf("%s is not linked", args[0])
	}
	delete(reg, key)
	fmt.Printf("unlinked %s\n", args[0])
	return reg.save()
}

func registryRows(reg registry) [][]string {
	var rows [][]string
	for _, e := range reg.sorted() {
		rows = append(rows, []string{e.Name, tilde(e.Path)})
	}
	return rows
}
