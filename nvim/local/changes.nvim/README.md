# changes.nvim

A VSCode-style inline diff of your git changes, in one tab page.

- Left: changed files, grouped into **Staged** and **Changes**, or the files
  that differ from a branch.
- Right: the selected file as a single buffer. Removed lines are drawn in
  red where they used to be, added lines are green, and unchanged code is
  folded into `⋯ N hidden lines` (open with `zo`, like the arrows in VSCode).
- Word-level highlighting inside changed lines.
- Stage, unstage and discard per file, per hunk, or per selected lines.
- Blame for the cursor line at the end of the line, like VSCode's
  "You, 6 hours ago • message".
- Commit what is staged and push, with ahead/behind counters in the header.
- Compare with a branch, or switch to another git worktree.
- Hover documentation from the language server of the real file.

Depends only on Neovim 0.10+, `vim.diff` and the `git` executable.

## Keys

| Where | Key | Action |
| --- | --- | --- |
| panel | `j` / `k` | move between files, the diff follows |
| panel | `<CR>` `l` `o` | focus the diff |
| panel | `s` | stage / unstage the file |
| panel | `X` | discard the file's changes (asks first) |
| panel | `b` | compare with a branch, or back to working changes |
| panel | `w` | switch to another git worktree of the same repo |
| diff | `]c` / `[c` | next / previous change |
| diff | `<Tab>` / `<S-Tab>` | next / previous file |
| diff | `s` | stage (or unstage, in Staged) the change under the cursor |
| diff | `V` then `s` | stage / unstage only the selected lines |
| diff | `X` | discard the change under the cursor (asks first); `V` then `X` for lines |
| diff | `<CR>` / `gf` | open the real file at this line |
| diff | `<leader>k` / `K` | hover info from the language server of the real file |
| diff | `zo` `za` `zR` | unfold hidden lines |
| diff | `-` | back to the panel |
| both | `c` | commit what is staged (asks for the message) |
| both | `P` | push the current branch (offers to set the upstream) |
| both | `R` | refresh |
| both | `q` | close |
| both | `?` | help |

The view refreshes itself when you write a file or come back to Neovim.
Unsaved edits in an open buffer are shown immediately.

### Selecting lines

Select lines with `V` and press `s` to stage only those, the way VSCode's
"Stage Selected Ranges" works. Added lines inside the selection are staged.
The removed lines of a change are included when the selection starts at the
top of that change (that is where they are drawn), or always for a pure
deletion. The same rule applies to `X`.

## Commands

```
:Changes                      toggle the view
:Changes open|close|refresh
:Changes status               back to working changes
:Changes diff <ref>           what this branch changed compared to <ref>:
                              merge-base(<ref>, HEAD) against the working tree
:Changes diff <ref> <ref2>    two commits against each other
:Changes <ref>                shortcut for :Changes diff <ref>
:Changes worktree <path>      open the view on that worktree
:Changes commit
:Changes push
```

Staging and discarding are only available for working changes, not in a
branch comparison.

## Setup

```lua
require("changes").setup({
  context = 3,             -- unchanged lines kept around each change
  panel_width = 40,
  algorithm = "histogram", -- any algorithm vim.diff() accepts
  sign = "+",              -- gutter sign for added lines
  blame = true,            -- blame the cursor line
  blame_delay = 250,       -- ms of cursor rest before blame is fetched
})
```

With lazy.nvim, pointing `dir` at this folder and setting `main = "changes"`
is enough; see `lua/plugins/changes-c.lua` in the dotfiles for an example.

## Highlights

`ChangesAdd`, `ChangesDelete`, `ChangesAddWord`, `ChangesDeleteWord`,
`ChangesSignAdd`, `ChangesBlame`, `ChangesTitle`, `ChangesDim`,
`ChangesStatusM`, `ChangesStatusA`, `ChangesStatusD`, `ChangesStatusU`,
`ChangesStatusUntracked`. All are `default` links to standard groups, so
override freely.

## Tests

```
tests/run.sh            # everything
tests/run.sh partial    # only tests/test_partial.lua
```

Runs headless with `nvim -u NONE`, builds throwaway repositories under the
temp directory, and needs nothing but `git`. Hover is not covered because it
needs a language server; check it by hand on a Lua file with lua_ls.

## How staging a hunk works

Patches are built with zero context and applied with `git apply --cached
--unidiff-zero`. Git positions such a hunk by the line number of the side it
is about to rewrite, so each hunk is numbered as if it were the only change
in the file, and when several hunks are applied in one go the numbers are
shifted by what the earlier hunks added or removed. Reverse patches (unstage)
use the same rule the other way round.
