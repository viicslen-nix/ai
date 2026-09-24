# CONTEXT

AI harness configuration, extracted from the nixos repo so it can run on a
machine that does not have that config. It absorbed the old `opencode`
subflake wholesale — the v1 and v2 home-manager modules, the `opencode-web`
NixOS service, the two package builders, and the shared agent/skill markdown.

## Why `aiInputs`, not `inputs`

home-manager's `extraSpecialArgs` **wins over** `_module.args`. The nixos repo
passes its own `inputs` there, so a module here that asked for `inputs` would
silently receive the consumer's input set instead of this flake's. It only
surfaced at all because the rename removed the root's `opencode` input and the
lookup started failing; with a name the consumer happens to share, it would
have resolved to the wrong flake in silence.

Every module in this flake therefore takes `aiInputs`, and both
`homeManagerModules` and `nixosModules` set `_module.args.aiInputs`. The NixOS
side needs it just as much — `nixos.nix` builds its default package with it.

`_module.args.aiInputs` lives in one keyed module (`viicslen-ai:args`) that the
others import, because the option is unique: defining it in each of the four
wrappers is four conflicting definitions, not one.

The wrappers carry a `key` for the same reason the nixos repo's discovery does:
two presets import the same module, and the module system dedupes only by key.

## What the extraction cost

Two `mkEnabledOption` calls became `mkEnableOption … // {default = true;}`.
That helper comes from the nixos repo's extended `lib`, and nixpkgs advises
against extending `lib` in modules meant to be shared — a consumer that did not
extend the same way would fail on an undefined variable. `mkDefaultAttrs` was
already shadowed locally in the ai module; `opencode2.nix` now defines it too.
Nothing else here reaches for the extended lib, so consumers need no
`lib.extend`.

## `programs.opencode.package` changed, deliberately

It used to resolve to the seeding wrapper, not the opencode binary — but only
by accident. Inside the old subflake `inputs.opencode` meant upstream
`anomalyco/opencode`; evaluated as a host module it meant the *root's* input of
that name, which was the subflake itself, whose `packages.default` is the
wrapper. Two different bindings of the same name, and which one you got
depended on who was evaluating.

It is now unambiguously the upstream binary. On a home-manager host that is
equivalent: the wrapper only copied config files that were absent, and
home-manager has already symlinked all 77 of them, so it was a no-op. Restoring
the old shape is not possible cleanly either — `packages/opencode.nix`
evaluates this module to harvest its config, so defaulting the option to that
package is an infinite recursion.

The seeding behaviour is what `mkHarness` is meant to replace, with a sync step
that diffs and confirms rather than skipping silently.

## `pkgs.local` is not available here

`hmModules/claude-code` used to read `pkgs.local.ccstatusline`, which resolved
only because `useGlobalPkgs` hands the consuming host's `pkgs` in. Anything
reached that way breaks the moment another consumer imports this flake.
It is now `aiInputs.packages.packages.${system}.ccstatusline` — the packages
flake is a real input here, so nothing depends on the consumer's overlay.

## Where skills come from, and in what order

`modules.programs.ai.skills` is three layers, last wins:

1. `upstreamSkills` — taken verbatim from `github:mattpocock/skills` via
   `selectFromInput`, curated by name because that repo carries more than we
   want (`in-progress/`, `misc/`, `deprecated/`).
2. `patchedSkills` — the same upstream skills with the local edits in
   `content/skill-patches` rewritten in, so a bump of `mattpocock-skills` keeps
   flowing and a reword that moves an anchor fails the build instead of
   silently reverting.
3. `mkSkillAttrSet ../content/skills` — a local directory, which shadows either
   of the layers above outright. It also holds the vendored collections
   (`just vendor-skills` in the consuming repo), which are plain checked-in
   skills as far as this is concerned.

One upstream path is worth remembering: `writing-for-agents` was renamed from
`writing-great-skills` and had its `GLOSSARY.md` split into `SKILL-MECHANICS.md`
(mattpocock/skills 1fc6573e), so the key here changed with it.

The option merges across definitions, so a consumer adds its own skills rather
than replacing these — which is how the nixos repo layers in the skills that
describe infrastructure not worth publishing.

## `profile` is opt-in, and holds no credentials

`modules.programs.aiProfile.enable` turns on the opinionated set: the skills
and commands above, the claude-code marketplaces and plugins, and the four MCP
backends that authenticate with OAuth or not at all. Anything needing a secret
is the consumer's — `google_stitch` stays in the nixos repo with the agenix
secret that feeds its header.

## What each target can actually take

The fan-out is not uniform — the harnesses expose different option surfaces,
and a target only forwards what its module accepts:

| | context | agents | commands | skills | mcp |
| --- | --- | --- | --- | --- | --- |
| claude-code | ✓ | ✓ | ✓ | ✓ | ✓ |
| opencode | ✓ | ✓ | ✓ | ✓ | ✓ |
| opencode2 | ✓ | ✓ | ✓ | ✓ | ✓ |
| github-copilot-cli | ✓ | ✓ | — | ✓ | ✓ |
| antigravity-cli | ✓ | — | ✓ | ✓ | ✓ |
| codex | ✓ | — | — | ✓ | ✓ |

Each target is gated on an option *existing* (`hasAttrByPath`), never on a
module being imported, which is what lets a consumer take this flake with only
one harness installed and have the rest drop out silently. The probe attribute
differs per harness for the same reason the table does — codex has neither
`commands` nor `agents`, so `context` is what proves its module is loaded.

## `nix run <flake>#<harness>`

`mkHarness` evaluates a harness's home-manager modules against a throwaway user
(`runner`, `/tmp/runner`), harvests the `xdg.configFile` entries under that
harness's subdirectory, and emits a wrapper that reconciles them into the real
config dir before exec'ing the binary. The module is the single source of
truth: a host imports it through home-manager, and the package evaluates the
same file. `packages/opencode.nix` and `oh-my-opencode.nix` are the two
hand-rolled ancestors of this and still exist; they seed with
`if [ ! -f "$target" ]`, which is the behaviour `ai-sync` replaces.

Each harness gets `hmModules/ai` and `hmModules/profile.nix` plus whatever else
it needs. `profile.nix` therefore has to gate its claude-code block on
`options.modules.programs ? claude-code` — a `mkIf` is not enough, because the
module system rejects an unknown option *path* before it looks at the
condition, and the opencode2 package imports no claude-code module.

Config travels; credentials do not. Every harness stores its auth in its data
directory, so a fresh machine gets the skills, agents and MCP wiring and then
asks you to log in.

## How `ai-sync` decides what it owns

No manifest of past state: the target answers the question itself.

- absent → symlink it
- symlink into `/nix/store` → ours, retarget silently
- identical content → nothing to do
- a regular file that differs → diff and confirm

That keeps the prompts to the few files someone actually changed out of the
~70 a harness generates. `y`/`n`/`a`/`q`, and an `n` is remembered in
`.ai-sync-keep` so a file the harness rewrites itself — Claude Code's
`settings.json` is the standing example — is asked about once, not every launch.

Two things it must never do, both covered: block when there is no TTY (it keeps
what is there and prints one line), and consume the manifest it is reading —
hence `read -r reply </dev/tty`, since stdin is the manifest for the whole loop.
`AI_SYNC=force` or `=skip` bypasses the prompt entirely.

## Everything that is markdown lives under `content/`

It did not, at first — the opencode subflake's `agents/`, `skills/` and
`dcp.jsonc` came across at the flake root, and the ai module kept its own
`agents/`, `commands/` and `skills/` beside `default.nix`. Two directories
named `agents`, and both were written `../agents/…`: from `hmModules/*.nix`
that meant the opencode set, from `hmModules/ai/integrations/*.nix` it meant
the integration set. The same path string, two destinations, depending only on
which file you were reading.

They are now split by owner, and no module keeps content next to it:

- `content/skills`, `content/commands`, `content/skill-patches`,
  `content/AGENTS.md` — the profile's payload, the portable half.
- `content/opencode/` — the agents, skill and `dcp.jsonc` both opencode
  modules share.
- `content/integrations/` — what `hmModules/ai/integrations/*` reference.

The integration paths are `../../../content/…`, which is deep but says exactly
where it lands.

## The harness packages shipped empty for a while

`nix run .#claude` gave you a bare claude: no skills, no commands, no MCP. It
exited 0, printed nothing unusual, and the wrapper was there. Two separate
faults, both silent.

**`mkHarness` filtered the wrong option.** It collected
`hmConfig.config.xdg.configFile`, but a module that writes an explicit
`"${config.xdg.configHome}/claude/…"` path does so through `home.file` and
never appears in `xdg.configFile` at all — the latter is an input that feeds
the former, not a view of it. Only opencode2, whose module happens to use
`xdg.configFile`, produced a non-empty manifest; claude, codex, copilot and
antigravity all shipped zero files. Nothing failed, because an empty manifest
is a valid manifest. It now filters `home.file` by `target`, and strips a
leading `/` first — upstream codex emits `/.config/codex/…`.

**Every target gate was `mkIf (hasXOption && …)`.** `mkIf false` is still a
definition of the path, so a harness package that did not import
`hmModules/opencode2.nix` — four of the five — failed to evaluate outright with
`The option 'programs.opencode2' does not exist`. Every other target's module
ships with home-manager, so only ours exposed it. The gates are
`optionalAttrs hasXOption (mkIf cfg.targets.<t> …)` now, `programs.mcp`
included; that block moved out of the always-on attrset to get the same
treatment.

The lesson for both: a harness package evaluates the module against a
throwaway user with *one* harness present, which is a much harsher environment
than any host here. Check `nix run` for each harness after touching the fan-out,
not just a host eval — a host has every module imported and hides all of this.

Two things stay as they are. The manifest destination is `$HOME/<relDir>`
rather than an `XDG_CONFIG_HOME`-derived path, because the evaluation resolves
`xdg.configHome` against the throwaway home anyway and `configDirVar` points
the harness at whatever we synced — for antigravity, `~/.gemini`, which is the
only path `agy` reads. And `nix run` on a non-opencode2 harness prints two
warnings about `programs.opencode2` being unavailable: that is the fan-out
correctly reporting a target with no module behind it, and it is worth more on
a host than it costs here.

## Where things live

```
builders/      mkHarness.nix + sync.sh — functions that produce packages
packages/      the two derivations the flake exports
hmModules/     home-manager modules; opencode/ holds v1, v2 and the service
nixosModules/  opencode-web
content/       every markdown payload
```

Three of those were somewhere else first, for no reason beyond how the opencode
subflake happened to be shaped when it was absorbed.

`mkHarness` sat in `packages/`, which reads as "the things exported as
packages" — and it is not one. It is a builder: it takes `pkgs`, calls
`homeManagerConfiguration` and `writeShellScriptBin`, and hands back a
derivation. That is what `flakes/packages/builders/` is for in this repo, and
what `build-support` is for in nixpkgs. It is not `lib/` material either —
everything in `flakes/lib` is a pure function that never sees `pkgs`. `sync.sh`
moved with it because `mkHarness` embeds it by relative path; they are one unit.

The three opencode modules were loose files at the top of `hmModules/`, mixed
in with `profile.nix` and the `ai`/`claude-code` directories, which made a
four-file harness look like three unrelated ones. They are `v1.nix`, `v2.nix`
and `service.nix` under `hmModules/opencode/` now; the exported attribute names
(`opencode`, `opencode2`, `opencode-service`) stay as they were, so nothing
downstream moved. v2 exists as a separate module because opencode 2.x renamed
the config keys, and its *option* names deliberately match v1 — so retiring v1
is deleting `v1.nix` and renaming the other.

`nixos.nix` was a single NixOS module at the flake root, next to `flake.nix`,
with nothing to say it was the opencode web server. It cannot live under
`hmModules/` — wrong class — so it is `nixosModules/opencode-web.nix`, named
after the attribute it exports and mirroring `hmModules/`.

The two opencode *packages* stayed in `packages/`. They really are exported
derivations, and the flake's own `packages.opencode` is what `opencode-web`
defaults to.
