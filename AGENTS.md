# AGENTS.md

Rules for agents changing this repo. `content/AGENTS.md` is a different file:
it is the global prompt this flake ships to every harness, so repo rules never
go there. The story behind each rule lives in `CONTEXT.md` (root, and the one in
the directory you touch); read it before changing the code a rule guards.

## Skills

A skill reaches `modules.programs.ai.skills` through one of three layers, last
wins (`hmModules/profile.nix`): upstream verbatim, upstream patched, local.

- **Upstream edit** → a `patchSkill` file in `content/skill-patches/<name>.nix`,
  anchored on plain ASCII spans. It returns a string, so use it only on
  single-file skills. A local copy in `content/skills` is the last resort: it
  stops tracking upstream.
- **"Call our skill instead of theirs"** (a local fork under another name) →
  `skillRenames.<old> = "<new>"`, never one patch per caller. `review-code`
  for upstream `code-review` is the worked example.
- **Upstream bump** (`mattpocock-skills`) → diff the curated list in
  `profile.nix` against `find skills -name SKILL.md` in the new rev. A removed
  skill fails the eval inside `selectFromInput` with a trace that never names it.
- **Rewriting skill bodies** goes through `builders/renameSkills.nix`. Keep a
  multi-file skill a directory (copy it, replace `SKILL.md`), read only real
  paths and text, and pass store-path strings through untouched: reading one
  is IFD.
- **Every file or text skill** a harness receives is a one-file store directory
  (`builders/skillDir.nix`). A bare store file makes opencode watch all of
  `/nix/store`.

## Namespaces

A namespace follows Claude Code plugins: Claude gets `/<ns>:<short>` from a
plugin, every other harness gets flat `<ns>-<short>`; `short` drops an upstream
`<ns>-` prefix.

- **Integrations** with more than one skill are namespaced by default
  (`integrations.<name>.skillNamespace`); single-skill ones stay flat.
- **Vendored collections** get `skillNamespaces.<ns>` only when they drive a
  tool or integration (stitch: yes; effective-html, plan-it, mattpocock: no).
  Select members by their recorded `github-repo` (`fromRepo` in `profile.nix`),
  not a hand-kept list.
- **Claude plugins load through `CLAUDE_CODE_PLUGIN_DIRS`** in `settings.json`
  `env`, from the store. Keep them out of `skills/`: opencode scans
  `~/.claude/skills` recursively and lists every short name as its own skill.
- **References** rewrite per view: `ns:x`, the flat name, `../old/` links, and
  a bare old name only when it is hyphenated. Generic names (`setup`, `page`)
  are prose elsewhere.

## Integrations

An integration is a file in `hmModules/ai/integrations/` returning any of
`skills`, `commands`, `agents`, `mcps`, `hooks`, `options`, `config`, `warnings`.
Its options live at `modules.programs.ai.integrations.<name>`, read as
`cfg.integrations.<name>`; the old `modules.programs.ai.<name>` path is a
renamed alias that warns.

- **It installs its own CLI**: a `package` option (default from `aiInputs`)
  and `home.packages = [package]` under `enable && installPackage`.
  `installPackage` is generated for every integration that declares `package`;
  it only gates `PATH`, so MCP commands, services and wrappers keep using the
  package by store path. Consumers never install it separately.
- **Every integration is opt-in**, GUI apps (`orca`) included: the consumer's
  preset or host enables it. A GUI *piece* of an enabled integration
  (browser-harness's profile launcher) defaults to
  `osConfig.services.graphical-desktop.enable`. `default.nix` reads `osConfig`
  as `args.osConfig or {}` and passes it on: standalone `nix run` evals have none.
- **Wire a new one** into `hmModules/ai/default.nix`: the `import`, and each of
  `skillIntegrations` (if it has skills, else `allIntegrations`), the `config`
  list, and the `warnings` list that applies.
- **Vendor its skills** into `content/integrations/skills/<name>` with
  `just vendor-integration-skills <name> <owner/repo> …`, pinned to the release
  that matches its package (Superset: `--pin cli-v<version>`), and warn when the
  pin and the package drift apart, as `integrations/superset.nix` does. Take
  skills from a built package only by a known file path; listing its directory
  is IFD.
- **Credentials** stay with the consumer; this flake ships only backends that
  authenticate with OAuth or not at all.

## Verifying

Evaluate the narrow option, never a whole system:

- skill names per view: `programs.opencode2.skills` (flat),
  `programs.claude-code.skills` (plain) and
  `programs.claude-code.settings.env.CLAUDE_CODE_PLUGIN_DIRS` (plugins);
- build the derivations you changed and read the rewritten `SKILL.md`s;
- for plugins, `claude --settings <file with that env> plugin list --json`
  shows each as `<ns>@inline`;
- after touching the fan-out, `nix run .#<harness>` for each harness: a host
  imports every module and hides what a single-harness package exposes.

New files are invisible to the flake until `git add`ed.
