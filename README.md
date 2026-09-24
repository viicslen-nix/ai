# ai

A portable AI coding-harness configuration: one set of skills, commands, agents
and MCP servers, fanned out to every harness that can read them.

Declare your context once as `modules.programs.ai`, and it reaches Claude Code,
opencode (v2, with v1 alongside), Codex, GitHub Copilot CLI and Antigravity in
whatever shape each one expects — Markdown commands here, a TOML block there, a
per-harness skills directory somewhere else.

## Try it without installing anything

```bash
nix run github:viicslen-nix/ai#claude
nix run github:viicslen-nix/ai#opencode
nix run github:viicslen-nix/ai#opencode1
nix run github:viicslen-nix/ai#codex
nix run github:viicslen-nix/ai#copilot
nix run github:viicslen-nix/ai#antigravity
```

Each of these is the real harness wrapped in its configuration. On first run it
syncs ~50-70 files into that harness's config directory and points the harness
at them, then execs the binary. Nothing is installed and nothing is left behind
but the config.

The files are symlinks into the Nix store, so a later run updates them in
place. If you have edited one by hand, the wrapper shows you a coloured diff
and asks before replacing it:

```
skills/tdd/SKILL.md differs from the version this build carries:
...
Replace it? [y]es / [n]o / [a]ll / [q]uit asking:
```

Answering `n` records the file and stops asking about it. Non-interactive runs
keep your version and say so. `AI_SYNC=force` replaces without asking,
`AI_SYNC=skip` never does.

## What's in it

- **26 skills** locally, plus 19 curated from
  [mattpocock/skills](https://github.com/mattpocock/skills), patched in place
  rather than forked so upstream changes keep flowing in.
- **4 commands** — `commit`, `investigate`, `pr-loop`, `verify`.
- **Agents** for opencode: ask, debug, review, security, documentation,
  pr-review-fixer.
- **MCP servers** that need no credentials: context7, gh_grep, linear,
  playwright. Anything needing a secret is yours to add — see
  [Credentials](#credentials).
- **Integrations** that wire themselves up when enabled: mcp-gateway,
  mempalace, coderabbit, openwiki, superset.

## Use it as a flake input

```nix
{
  inputs.ai.url = "github:viicslen-nix/ai";

  # In your home-manager configuration:
  imports = [inputs.ai.homeManagerModules.default];
}
```

`homeManagerModules.default` brings everything, opinions included — it turns
`modules.programs.aiProfile` on for you, and `enable = false` turns it back off.
The pieces are also exported separately — `ai`, `profile`, `claude-code`,
`opencode`, `opencode1`, `opencode-service` — if you want the fan-out without
the opinions, or one harness without the rest.

### The two layers

**`modules.programs.ai`** is the mechanism: it takes your content and
distributes it. It has no opinions about what that content is.

```nix
modules.programs.ai = {
  context = ./AGENTS.md;              # the global system prompt
  skills = { my-skill = ./skill.md; };
  commands = { deploy = ./deploy.md; };
  agents = { reviewer = ./reviewer.md; };
  mcps = { context7.url = "https://mcp.context7.com/mcp"; };

  targets.codex = false;              # every harness is on by default
};
```

Each target writes only what that harness supports, and warns rather than fails
when a harness's module isn't present. Commands are translated per harness;
Codex and Copilot take context and skills but have no command concept.

**`modules.programs.aiProfile`** is the opinion: it gives you everything under
[What's in it](#whats-in-it), plus the integrations. `homeManagerModules.default`
and every `nix run` package turn it on; importing `profile` on its own does not.

### NixOS

```nix
imports = [inputs.ai.nixosModules.opencode-web];
modules.services.opencode-web.enable = true;
```

Runs opencode as a web server, pulling in the matching home-manager service
through `home-manager.sharedModules`. The credential is set on the
home-manager side: point `services.opencode-web.environmentFile` at a file
holding `OPENCODE_SERVER_PASSWORD`, outside the Nix store.

## Credentials

There are none in this repo, deliberately. Every MCP server here is
credential-free, so the flake runs anywhere without carrying somebody's
secrets.

To add one that needs a token, pass it from your own configuration. For a
remote backend, put the credential in a header and let mcp-gateway expand it
from the environment rather than writing it into a config file that lands
world-readable in the Nix store:

```nix
modules.programs.ai.mcps.my_service = {
  url = "https://example.com/mcp";
  headers."X-Api-Key" = "\${MY_SERVICE_KEY}";
};

systemd.user.services.mcp-gateway.Service.EnvironmentFile = "%t/agenix/my-service";
```

## Working on it

```bash
nix develop
```

Brings `gh`, `just`, `git`, `alejandra` and `column` — everything the recipes
need. `gh skill` is a preview command, so an older `gh` on your `PATH` will fail
every one of them; the shell pins a new enough one.

```bash
just vendor-skills <owner/repo> [skill|--all]   # add an upstream collection
just update-skills [--dry-run]                  # re-pull every vendored skill
just skills                                     # list them with their origin
```

Vendoring is for upstreams carrying a lot of non-skill weight — a non-flake
input has no sparse fetch, so it would copy the whole repository into the store.
A small, skill-only repo rides as a `flake = false` input instead; see
`mattpocock-skills` in `flake.nix`. `gh` records each skill's origin in its own
`SKILL.md` frontmatter, so there is no manifest to keep in step — and a skill
written here by hand has none, so `update` warns and skips it.

## Layout

```
builders/      mkHarness.nix + sync.sh — every package is built from these
hmModules/     home-manager modules; opencode/ holds v1, v2, oh-my and the service
nixosModules/  opencode-web
content/       every markdown payload
```

`CONTEXT.md` carries the reasoning behind all of it — what was tried, what
broke, and why the obvious shape is sometimes wrong.

## Notes

- **Modules take `aiInputs`, not `inputs`.** Home-manager's `extraSpecialArgs`
  outranks `_module.args`, so a module asking for `inputs` would silently get
  the *consumer's* set instead of this flake's.
- **Antigravity is not self-contained.** `agy` has no config-directory
  variable and reads `~/.gemini` wherever it runs, so that is what
  `nix run .#antigravity` writes to. Every other harness is pointed at its own
  directory and touches nothing else.
- **`opencode` is v2; v1 is `opencode1`.** v2 renamed the config keys
  (`plugin`→`plugins`, `agent`→`agents`, an agent's `prompt`→`system`), so they
  stay separate modules. v2 owns `~/.config/opencode` and the plain XDG paths;
  v1 is isolated under `opencode1` and ships a short `op1` alias. Note v1 no
  longer uses home-manager's own `programs.opencode` module — that module
  hardcodes `~/.config/opencode`, which v2 now needs — so v1 loses its `tui`,
  `themes`, `tools` and `commands` options, stylix theming among them.
