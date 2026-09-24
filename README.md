# ai

A portable AI coding-harness configuration: one set of skills, commands, agents
and MCP servers, fanned out to every harness that can read them.

Declare your context once as `modules.programs.ai`, and it reaches Claude Code,
opencode (v1 and v2), Codex, GitHub Copilot CLI and Antigravity in whatever
shape each one expects — Markdown commands here, a TOML block there, a
per-harness skills directory somewhere else.

## Try it without installing anything

```bash
nix run github:viicslen-nix/ai#claude
nix run github:viicslen-nix/ai#opencode2
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

  modules.programs.aiProfile.enable = true;
}
```

`homeManagerModules.default` brings everything. The pieces are also exported
separately — `ai`, `profile`, `claude-code`, `opencode`, `opencode2`,
`opencode-service` — if you want the fan-out without the opinions, or one
harness without the rest.

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

**`modules.programs.aiProfile`** is the opinion: enable it and you get
everything under [What's in it](#whats-in-it), plus the integrations. It is one
option, and it is what the `nix run` packages turn on.

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

## Layout

```
builders/      mkHarness.nix + sync.sh — functions that produce packages
packages/      the two derivations the flake exports
hmModules/     home-manager modules; opencode/ holds v1, v2 and the service
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
- **opencode v1 and v2 are separate modules.** v2 renamed the config keys
  (`plugin`→`plugins`, `agent`→`agents`, an agent's `prompt`→`system`). The
  *option* names match v1 on purpose, so retiring v1 is a rename.
