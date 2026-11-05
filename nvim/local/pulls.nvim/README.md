# pulls.nvim

Review GitHub pull requests in Neovim: check the branch out and walk its
changed files as ordinary buffers (with your LSP, splits and gitsigns), or
read one in a tab page without touching your checkout.

- Left: the pull requests of a repository (state, author, checks, review
  decision), with a preview of the one under the cursor. Once one is opened,
  its **Overview** and the changed files, with a count of review threads.
- Overview: state, branches, labels, reviewers, merge status, checks
  (failing and pending listed first), description, commits and the
  conversation (comments and reviews in order).
- Files: the diff of each file drawn inline: removed lines red, added lines
  green, word-level highlighting, old and new line numbers in the gutter,
  and review threads drawn under the lines they comment on. Outdated
  threads are listed at the end of the file.
- Tick GitHub's "Viewed" box per file; viewed files get a ✓ in the panel.
- Comment on a line or a selected range, reply to threads, comment on the
  pull request, approve or request changes, check out the branch.

Everything goes through the [`gh`](https://cli.github.com) CLI, so it uses
your `gh auth login` and works for any repository you can see, cloned or not.
Needs Neovim 0.10+.

## Commands

```
:PR                         pull requests of the repository of the current directory
:PR owner/name              of another repository
:PR 123                     open #123 directly
:PR owner/name 123
:PR https://github.com/owner/name/pull/123
:PR review [123]            check #123 out here and review it (no number: picker)
:PR files                   show / hide the changed-files sidebar
:PR done                    back to your branch, your work restored
:PR install                 run bun/pnpm/yarn/npm install here, then restart LSP
:PR pick                    quick picker: waiting for your review, recent, yours
:PR close | toggle | refresh
```

## Reviewing in your checkout

`:PR review 123` (or `<CR>` in the picker) checks the pull request out in the
clone you are in, with `gh pr checkout`:

1. Uncommitted changes? You choose: **stash** them (untracked files too), or
   **commit** them as a WIP commit on your branch (message asked, hooks
   skipped), or cancel. Unsaved buffers stop it before anything happens.
2. The base branch is fetched and the changes are measured from the merge
   base, like GitHub does.
   If the branch is already checked out in another worktree, the head
   commit is checked out detached instead.
3. The sidebar (`<leader>n`; it replaces the explorer) shows the changed
   files as a tree, single-directory chains folded: status, ✓ when viewed,
   `+`/`-` counts and review threads.
   `<CR>`/`l` opens a file at its first change, `<C-v>`/`<C-s>` in a split,
   `v` ticks Viewed, `o` the overview tab, `<C-o>` the browser.
   `<leader>n` again hides it; `<leader>N` is always the full explorer.
4. Files are your real files on the PR's branch, so `gd`, `K`, references
   and splits just work (and `node_modules` etc. are already there).
   gitsigns diffs against the merge base and, like the pulls tab, tints
   changed lines green, marks the changed words and shows removed lines
   inline in red (`<leader>hd` toggles that, `review_colors = false` turns
   it off; `:PR done` restores your gitsigns settings). `]h`/`[h` move
   between the hunks of the file.
5. Review threads are diagnostics on their lines (`<leader>e` shows the
   whole thread).
6. When the pull request changes a `package.json` or the lockfile, you are
   asked to run the install (bun, pnpm, yarn or npm, from the lockfile);
   language servers restart afterwards. Again on `:PR done`. Set
   `install = true` to always do it, `false` never.

While reviewing:

| Key | Action |
| --- | --- |
| `n` / `N` | next / previous change, on into the next / previous file (while a search is highlighted they search as usual; `<Esc>`/`:noh` switches back) |
| `]f` / `[f` | next / previous changed file |
| `<leader>pc` | comment on the line, or the selected lines |
| `<leader>pr` | reply to the thread on the line |
| `<leader>pv` | toggle Viewed for the file |
| `<leader>ps` | submit a review: approve, request changes or comment |
| `<leader>po` | overview and conversation (the pulls tab) |
| `R` | refresh: pull the PR's new commits (if any) and reload files, hunks and comments (`:PR refresh`) |
| `<leader>pd` | done: `:PR done` |

`:PR done` checks your branch out again and pops the stash, or offers to
undo the WIP commit (`git reset HEAD~`, the changes stay). It refuses while
the PR branch has uncommitted changes. The session is saved, so after a
restart `<leader>n` picks the review up again and `:PR done` still works.
`C` in the pulls tab starts the same review.

## Quick picker

`:PR pick` (`<leader>fp` in the dotfiles). In a clone of a GitHub repository
it lists that repository:

- **review**: open pull requests waiting for your review,
- **recent**: the ones you opened here lately (kept in `stdpath("data")/pulls`),
- **mine**: your own open pull requests,
- **open**: every other open pull request.

`<C-a>` switches to all repositories (review requests, recent and yours
everywhere), which is also what you get outside a clone. Fuzzy-find and
preview the description. `<CR>` reviews it in your checkout when it belongs
to the repository you are in (otherwise opens the pulls tab), `<C-t>` opens
the pulls tab without checking out, `<C-o>` the browser. It shows the last
known results at once and updates them from GitHub while it is open. Uses
snacks.nvim's picker, `vim.ui.select` without it.

## Keys

| Where | Key | Action |
| --- | --- | --- |
| list | `j` / `k` | move; the preview follows |
| list | `<CR>` `l` | open the pull request |
| list | `s` | cycle open / merged / closed / all |
| list | `f` | search, gh syntax: `author:@me`, `review-requested:@me`, `label:bug` |
| list | `r` | switch repository |
| panel | `j` / `k` | move between Overview and files; the right side follows |
| panel | `<CR>` `l` | focus the overview or diff |
| panel | `<BS>` `h` | back to the list |
| diff | `]c` / `[c` | next / previous change |
| diff | `]t` / `[t` | next / previous review thread |
| diff | `c` | comment on the line; `V` then `c` for a range |
| diff | `r` | reply to the thread on this line (or under this change) |
| diff, panel | `v` | mark the file as viewed, like GitHub's "Viewed" box; again to undo |
| diff | `gf` `<CR>` | open the file in your checkout at this line (previous tab) |
| diff, overview | `<Tab>` / `<S-Tab>` | next / previous file |
| diff, overview | `-` | back to the panel |
| anywhere | `c` | comment on the pull request (outside the diff) |
| anywhere | `A` / `X` | approve / request changes |
| anywhere | `C` | review in your checkout (`:PR review`, closes the tab) |
| anywhere | `o` | open in the browser |
| anywhere | `R` `q` `?` | refresh, close, help |

Comments, replies and reviews open a markdown buffer at the bottom: `:w` or
`<C-s>` sends it, `q` cancels. Line comments are posted straight away as
single comments, not collected into a pending review.

## Your checkout

`gf` and `C` need the current directory to be a clone of the repository.
`gf` opens the file in your own checkout as it is; for `gd`, hover and the
rest of your LSP, review the pull request in your checkout with `C`
(`:PR review`).

## Setup

```lua
require("pulls").setup({
  panel_width = 50,
  limit = 50,          -- pull requests per list
  state = "open",      -- initial filter: open, merged, closed, all
  search = "",         -- initial search, e.g. "review-requested:@me"
  compose_height = 12,
})
```

With lazy.nvim, point `dir` at this folder and set `main = "pulls"`; see
`lua/plugins/pulls-c.lua` in the dotfiles.

## Highlights

`PullsAdd`, `PullsDelete`, `PullsAddWord`, `PullsDeleteWord`, `PullsHunk`,
`PullsLineNr`, `PullsTitle`, `PullsDim`, `PullsOpen`, `PullsDraft`,
`PullsMerged`, `PullsClosed`, `PullsPass`, `PullsFail`, `PullsPending`,
`PullsThread`, `PullsThreadBorder`, `PullsThreadAuthor`, `PullsStatusA`,
`PullsStatusM`, `PullsStatusD`, `PullsStatusR`. All are `default` links.

## Tests

```
tests/run.sh            # everything
tests/run.sh actions    # only tests/test_actions.lua
```

Headless with `nvim -u NONE`. `tests/bin/gh` stands in for the GitHub CLI:
it answers from `tests/fixtures` and logs every call, so the tests check the
exact `gh` arguments of comments and reviews without touching GitHub.
