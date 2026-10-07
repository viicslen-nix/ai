# CONTEXT

What `modules.programs.claude-code` owns, and the reasoning behind the settings
it pins.

## Scope

Global Claude Code preferences — the whole of `settings.json` apart
from the hooks, which each integrating module contributes for itself
(`modules.programs.ai` for mempalace/superset, `modules.programs.herdr`).

Claude Code rewrites this file itself (`/config`, model switches), as do the
mempalace/ponytail/superset hook installers. Once home-manager owns it those
runtime edits land in `settings.json.backup` and are dropped on the next
activation, so change settings here rather than in the TUI.

That is also why `home.file."${configDir}/settings.json".force` is set: Claude
Code and the hook installers replace the symlink with a real file at runtime, so
activation backs it up every time, and without `force` the next one aborts on
the stale `settings.json.backup`.

## `autoCompactWindow = 500000`

Auto-compact at half the 1M window instead of the model-tuned default. The
effective threshold is min(this, the model's max context) less a summary buffer.
`CLAUDE_CODE_AUTO_COMPACT_WINDOW` outranks it, and `/autocompact auto` returns
to the default.

## `statusLine.command`

A store path, not `npx -y ccstatusline@latest`: npx re-resolves the version
against the registry on every render, so the statusline paid a network
round-trip and an `npm exec` process per refresh, in every session at once.

## `configDir` is `$XDG_CONFIG_HOME/claude`

Home-manager exports `CLAUDE_CONFIG_DIR` whenever this differs from upstream's
`~/.claude`, and the CLI resolves `.claude.json` against the same variable —
so one option moves both the directory and the JSON file off the home root.
herdr reads `CLAUDE_CONFIG_DIR` too, which is why
`modules.programs.herdr`'s SessionStart hook points at `configDir` rather than
a literal path: herdr installs `herdr-agent-state.sh` wherever that variable
says, and the two must agree or the hook silently never fires.

The variable only reaches processes started after a re-login. A Claude Code
already running when the option lands keeps writing to `~/.claude`, so the
migration is `mv ~/.claude ~/.config/claude` plus a temporary
`~/.claude -> .config/claude` symlink, dropped once the session restarts.

## `pluginDirs` and `mods`

`CLAUDE_CODE_PLUGIN_DIRS` is one string in `settings.json`, and home-manager's
JSON type refuses two different definitions of it. The ai module's integration
plugins and this module's mods both need it, so `pluginDirs` is the list they
join and this module the only writer. The ai module still writes the variable
itself when imported without this one (`hasClaudePluginDirsOption`).

Mods are copied to the store with `builtins.path` and a filter: a local `path:`
flake ignores `.gitignore`, so the `.claude-plugin/types/` and `tsconfig.json`
Claude Code writes beside a `--plugin-dir` mod would otherwise reach the store
and change its hash on every Claude Code update. A read-only mod directory loads
fine; Claude Code just skips writing the types there.

## `readable-output`

Restyles the transcript through `ui.render`, terminal only; remote surfaces and
anything it does not recognise go to `next(e)` untouched. What it learned:

- Ink's `Box` here has no per-side borders, so a left accent bar is a
  `width={1}` Box with a `backgroundColor`, stretched by the row to the
  content's height. `borderStyle` would add a top and bottom row to every
  result.
- Replies, tool results and the diff keep the engine's own drawing (the
  `{type: 'engine'}` node from `next(e)`) inside the bar, so markdown,
  highlighting and clickable paths survive. Only the tool row header and the
  collapsed group line are drawn from scratch; the result body, the diff and
  the running command's progress are separate sites.
- Like opencode, it folds what you skim: a tool's result shows only when it
  errs or changes a file (Edit, Write, NotebookEdit), and narration (text the
  model followed with a tool call) is one dim line. Neither site says when
  ctrl+o is open, so both stay folded there too. A Skill call is the one
  bright badge, so you notice it at once.
- Narration can't be told from the row alone: the engine draws a text block
  when it ends, before the tool call that follows it arrives, and
  `$.session.messages()` doesn't have that call yet either. So `narration.ts`
  watches each `turn.step` stream, and a row whose text is still in a live step
  waits (at most 1.5s) for the step's next text, tool or stop chunk. Block
  starts and ends arrive as `engine` chunks in between and must not settle the
  wait. A resumed session falls back to the transcript.
- `claude plugin validate` only follows `$` into functions in the same file,
  so `narration.ts` keeps state and pure logic, and every `$` call stays in
  `register.tsx`.
- The spinner is a column with a top margin and a tip row beneath, so wrapping
  it in a row misaligns everything; the mod rewrites its `word` prop instead.
- Badges sit in a `flexShrink={0}` Box, or a neighbour taking the width wraps
  them onto two lines.
- Colours started as theme keys and were too loud: the dark theme's keys are
  pastels meant for text, not filled blocks. A mod cannot read whether the
  light or dark theme is on, so `PALETTE` holds fixed muted mid-tones that
  read on both; only the prompt band keeps a theme key
  (`userMessageBackground`). Strong colour is kept for what needs attention:
  errors, running and interrupted calls, diff counts and Skill calls. A finished call's
  check mark is dimmed.
- tmux without RGB makes chalk downsample to 256 colours, and it quantises
  each channel as `round(v / 51)`, not to the cube's own levels. A first muted
  palette collapsed Bash and Read onto 102, and Edit and the prompt onto 103.
  Every channel is now 0x48, 0x7e or 0xb0, which land on the cube's 5f, 87 and
  af.
- Prompts and replies never share a colour (blue against rose). Glyphs are
  Nerd Font codicons (`nf-cod-*`), all present in FiraCode Nerd Font Mono.
- `TurnDuration` drops the engine's `done 12:28 PM`: the props carry no
  timestamp, and one taken at first render would be wrong after a resume.
