# claude.nvim

Hand code to the Claude Code session running in tmux, without typing paths.

| Key | Sends |
| --- | --- |
| `<leader>aa` | `@path line 12 ` for the cursor line, `@path lines 10-20 ` for a selection |
| `<leader>af` | `@path ` of the whole file |
| `<leader>ad` | the line / selection plus the diagnostics on it |
| `<leader>ap` | choose which Claude pane to send to (`:ClaudePane`) |

The text is typed into Claude's prompt, not submitted, and the Claude pane
gets focus so you can write the question. The pane is found in the current
tmux window, else the session (one in the same directory first); with
several you choose once and it is remembered. `focus = false` stays in nvim.
