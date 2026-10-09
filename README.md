<div align="center">

# ai

**One set of skills, commands, agents and MCP servers, fanned out to every AI coding harness.**

[![flake-parts](https://img.shields.io/badge/built_with-flake--parts-7EBAE4?style=flat-square&logo=nixos&logoColor=white)](https://flake.parts)
[![Home Manager](https://img.shields.io/badge/Home_Manager-modules-41439A?style=flat-square)](https://github.com/nix-community/home-manager)
[![Harnesses](https://img.shields.io/badge/harnesses-Claude_Code_·_opencode_·_Codex_·_Copilot_·_Antigravity_·_pi-555?style=flat-square)](#try-it)

</div>

Declare your context once as `modules.programs.ai`, and it reaches Claude Code,
opencode (v2, with v1 alongside), Codex, GitHub Copilot CLI, Antigravity and pi in
whatever shape each one expects — Markdown commands here, a TOML block there, a
plugin directory somewhere else.

## Contents

- [Try it](#try-it)
- [What's in it](#whats-in-it)
- [Outputs](#outputs)
- [Use it as a flake input](#use-it-as-a-flake-input)
- [Options](#options)
- [Credentials](#credentials)
- [Working on it](#working-on-it)

## Try it

```bash
nix run github:viicslen-nix/ai#claude
nix run github:viicslen-nix/ai#opencode
nix run github:viicslen-nix/ai#codex
nix run github:viicslen-nix/ai#copilot
nix run github:viicslen-nix/ai#antigravity
nix run github:viicslen-nix/ai#pi
```

Each is the real harness wrapped in its configuration: the wrapper syncs the
files the harness's home-manager module would write (~50–70) into its config
directory, points the harness at them, and execs the binary. Nothing else is
installed.

The files are symlinks into the Nix store, so a later run updates them in
place. A file you edited by hand gets a coloured diff and a prompt —
`[y]es / [n]o / [a]ll / [q]uit asking`. An `n` is remembered in
`.ai-sync-keep`; non-interactive runs keep your version. `AI_SYNC=force`
replaces without asking, `AI_SYNC=skip` never does.

> [!NOTE]
> On a machine where home-manager already manages that harness, the wrapper
> leaves its files alone and just runs the harness — home-manager owns them.

> [!NOTE]
> Antigravity has no config-directory variable: `agy` reads `~/.gemini`
> wherever it runs, so that is what `#antigravity` writes. Every other harness
> is pointed at a directory of its own.

## What's in it

What `modules.programs.aiProfile` turns on:

| | |
| --- | --- |
| **Skills** | 20 curated from [mattpocock/skills](https://github.com/mattpocock/skills) (three patched in place, so upstream keeps flowing), plus `content/skills` — local skills and vendored collections (stitch, effective-html, plan-it, …) |
| **Commands** | `commit`, `investigate`, `pr-loop`, `verify` |
| **Agents** | `ask`, `debug`, `documentation`, `pr-review-fixer`, `review`, `security` from `content/agents` |
| **Context** | `content/AGENTS.md`, the global prompt every harness receives |
| **MCP servers** | context7, gh_grep, linear, playwright — OAuth or no auth at all |
| **Integrations** | gateway (mcp-gateway), mempalace, coderabbit, openwiki |
| **Claude Code** | marketplaces and plugins (mempalace, ponytail, worktrunk, document-skills, …) |

Further integrations ship off by default: `orca`, `superset`,
`browser-harness`, `jev`. Each integration installs its own CLI, so a host
never adds it separately.

## Outputs

| Output | What |
| --- | --- |
| `packages.<system>.claude` / `codex` / `copilot` / `antigravity` / `pi` | A harness wrapped with its config |
| `packages.<system>.opencode` (= `default`, `opencode2`) | opencode v2, launcher `opencode2` |
| `packages.<system>.opencode1` | opencode v1, with an `op1` alias |
| `packages.<system>.oh-my-opencode` | opencode v1 with oh-my-opencode, in `~/.config/oh-my-opencode` |
| `homeManagerModules.default` | Everything below, with `aiProfile` on |
| `homeManagerModules.ai` | The fan-out mechanism, `modules.programs.ai` |
| `homeManagerModules.profile` | The opinions, `modules.programs.aiProfile` |
| `homeManagerModules.claude-code` | Global Claude Code settings, marketplaces and plugins |
| `homeManagerModules.opencode` (= `opencode2`) / `opencode1` | opencode v2 / v1 |
| `homeManagerModules.opencode-service` | The per-user opencode web service |
| `homeManagerModules.pi` | [pi.nix](https://github.com/lukasl-dev/pi.nix)'s module (`programs.pi.coding-agent`), agent dir in `~/.config/pi` |
| `homeManagerModules.t3code` | T3 Code (`modules.programs.t3code`), rebuilt with T3 Connect; optional nightly beside it, served or as the desktop app |
| `nixosModules.opencode-web` | opencode as a web server for every home-manager user |
| `devShells.<system>.default` | `gh`, `git`, `just`, `alejandra`, `column` for the recipes |
| `formatter.<system>`, `checks.<system>` | treefmt, its `treefmt` check, and a `statix` check |

Systems: `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`.

## Use it as a flake input

```nix
{
  inputs.ai.url = "github:viicslen-nix/ai";

  # In your home-manager configuration:
  imports = [inputs.ai.homeManagerModules.default];
}
```

`default` brings everything, opinions included. Import the pieces instead for
the fan-out without the opinions, or one harness without the rest. Importing
`profile` turns it on; `modules.programs.aiProfile.enable = false` keeps the
module without the opinions.

The flake reaches home-manager through
[omniflake](https://github.com/fzakaria/omniflake)'s index rather than an input
of its own. Point `inputs.ai.inputs.omniflake.follows` at yours so only one copy
is locked.

### NixOS

```nix
imports = [inputs.ai.nixosModules.opencode-web];
modules.services.opencode-web.enable = true;  # host, port (43037), hostname, package
```

Injects the web service into every home-manager user through
`home-manager.sharedModules`. It runs the launcher of
`modules.programs.opencode.default` (`serve` for v2, `web` for v1). Set the
password per user with `services.opencode-web.environmentFile`, a file holding
`OPENCODE_SERVER_PASSWORD` outside the Nix store.

## Options

**`modules.programs.ai`** is the mechanism: it takes your content and
distributes it, with no opinions about what that content is.

```nix
modules.programs.ai = {
  context = ./AGENTS.md;
  skills.my-skill = ./skill.md;            # a file, a directory, or text
  commands.deploy = ./deploy.md;
  agents.reviewer = ./reviewer.md;
  mcps.context7.url = "https://mcp.context7.com/mcp";

  targets.codex = false;                   # every harness is on by default

  # Point every skill that calls `code-review` at your fork instead.
  skillRenames.code-review = "review-code";
  # A plugin in Claude Code (`/stitch:loop`), a flat prefix elsewhere (`stitch-loop`).
  skillNamespaces.stitch = ["code-to-design" "stitch-loop"];

  integrations.mempalace = {
    enable = true;
    installPackage = false;                # keep the CLI off PATH; MCP still runs it
  };
};
```

A target writes only what its harness accepts, and drops out when that
harness's module is not imported:

| Target | context | agents | commands | skills | MCP |
| --- | :-: | :-: | :-: | :-: | :-: |
| `claude-code` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `opencode` (v2) / `opencode1` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `github-copilot-cli` | ✓ | ✓ | — | ✓ | ✓ |
| `antigravity-cli` | ✓ | — | ✓ | ✓ | ✓ |
| `codex` | ✓ | — | — | ✓ | ✓ |
| `pi` | ✓ | — | ✓ | ✓ | ✓ |

Agents are written in opencode's frontmatter and translated for the rest:
Claude Code gets a `name` and `disallowedTools`, Copilot a `name` and a `tools`
allowlist (`builders/agentFor.nix`).

<details>
<summary><b>Other modules</b></summary>

| Option | Does |
| --- | --- |
| `modules.programs.aiProfile.enable` | The opinionated set above; defaults to `true` once imported |
| `modules.programs.ai.integrations.<name>` | `enable`, `package` + `installPackage`, `skillNamespace` (multi-skill integrations), plus each one's own knobs. Integrations: `gateway`, `mempalace`, `coderabbit`, `openwiki`, `orca`, `superset`, `browser-harness`, `jev` |
| `modules.programs.claude-code` | `marketplaces`, `plugins`, `settings` (merged over the pinned defaults); moves the config dir to `$XDG_CONFIG_HOME/claude` |
| `modules.programs.opencode` | v2: `enable`, `model`, `small_model`, `phpantom.enable`; options on `programs.opencode2` |
| `modules.programs.opencode1` | v1, the same shape; options on `programs.opencode1` |
| `modules.programs.opencode.default` | `"v2"` or `"v1"`: which version gets the `opencode` command, the `~/.config/opencode` symlink and `opencode-web` |

</details>

<details>
<summary><b>opencode v1 and v2</b></summary>

Both are isolated, and the default only points:

| | v1 | v2 |
| --- | --- | --- |
| launcher | `opencode1` (`op1`) | `opencode2` |
| config | `~/.config/opencode1` | `~/.config/opencode2` |
| data | `~/.local/share/opencode1/opencode` | `~/.local/share/opencode2/opencode` |

v2 renamed the config keys (`plugin`→`plugins`, `agent`→`agents`, an agent's
`prompt`→`system`), so each major keeps its own module, and v1 plugins do not
load on v2. v1 no longer goes through home-manager's `programs.opencode` (which
hardcodes `~/.config/opencode`), so it has no `tui`, `themes` or `tools`
options and no stylix theming.

</details>

<details>
<summary><b>An LLM proxy for every harness</b></summary>

`modules.programs.ai.proxy` is unset here; a host points it at a proxy that
speaks the Anthropic, OpenAI Responses and Gemini APIs, such as CLIProxyAPI:

```nix
modules.programs.ai.proxy = {
  baseUrl = "https://cliproxy.tail1234.ts.net";   # root, no /v1
  apiKeyFile = config.age.secrets.cliproxyapi-api-key.path;
  models = {
    claude-opus-5-5 = { api = "anthropic"; reasoning = true; };
    gpt-6-sol = { api = "openai"; reasoning = true; };
    gemini-3-flash.api = "gemini";
  };
  launchers.codex.model = "gpt-6-sol";
};
```

Nothing replaces a harness's own login. opencode (v1 and v2) and pi get one
provider per API, `proxy-anthropic`, `proxy-openai` and `proxy-gemini`, with
the listed models, shown as `Proxy (Anthropic)` and so on (`label` renames
them). The single-provider harnesses get a second command instead:
`claude-proxy`, `codex-proxy`, `copilot-proxy` and `agy-proxy` (`name` sets the
suffix). With `default = true` the proxy replaces their logins instead: Claude
Code and Codex get it in their own config, Copilot and agy under their plain
names, and `<bin>-direct` keeps each one's own login. The key is read from the
file at launch, never written to the store.

</details>

## Credentials

None live here, deliberately: every MCP server this flake ships authenticates
with OAuth or not at all, so it runs anywhere. To add one that needs a token,
pass it from your own configuration. For a remote backend, put the credential
in a header and let mcp-gateway expand it from the environment, rather than
writing it into a config file that lands world-readable in the store:

```nix
modules.programs.ai.mcps.my_service = {
  url = "https://example.com/mcp";
  headers."X-Api-Key" = "\${MY_SERVICE_KEY}";
};

systemd.user.services.mcp-gateway.Service.EnvironmentFile = "%t/agenix/my-service";
```

## Working on it

```bash
nix develop        # gh, git, just, alejandra, column
nix fmt            # treefmt: deadnix, statix, alejandra, shfmt
nix flake check    # formatting, statix (repeated keys `statix fix` skips)
```

| Recipe | Does |
| --- | --- |
| `just vendor-skills <owner/repo> [skill\|--all]` | Vendor an upstream collection into `content/skills` |
| `just vendor-integration-skills <name> <owner/repo> …` | Vendor one integration's collection into `content/integrations/skills/<name>` |
| `just update-skills [--dry-run]` | Re-pull every vendored skill |
| `just skills` | List vendored skills with their repo and ref |

`gh skill` is a preview command, so an older `gh` on your `PATH` fails every
recipe; the dev shell pins a new enough one. `gh` records each skill's origin in
its own `SKILL.md` frontmatter, so there is no manifest — and a hand-written
skill has none, so `update-skills` warns and skips it. Vendored skills are
excluded from `nix fmt`.

> [!TIP]
> Vendoring is for upstreams carrying a lot of non-skill weight: a non-flake
> input has no sparse fetch. A small, skill-only repo rides as a
> `flake = false` input instead, like `mattpocock-skills`.

```text
builders/      mkHarness.nix + sync.sh — every package is built from these
hmModules/     home-manager modules; opencode/ holds v1, v2, oh-my and the service
nixosModules/  opencode-web
content/       every markdown payload
```

[`AGENTS.md`](AGENTS.md) holds the rules for changing this repo;
[`CONTEXT.md`](CONTEXT.md) the reasoning behind them — what was tried, what
broke, and why the obvious shape is sometimes wrong.
