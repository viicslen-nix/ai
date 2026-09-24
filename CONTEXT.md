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
the old shape is not possible cleanly either — the `opencode` *package*
evaluates this module to harvest its config, so defaulting the option to that
package is an infinite recursion.

The seeding behaviour is what `mkHarness` replaces, with a sync step that diffs
and confirms rather than skipping silently.

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
same file.

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
builders/      mkHarness.nix + sync.sh — every package is built from these
hmModules/     home-manager modules; opencode/ holds v1, v2, oh-my and the service
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

`packages/` is gone. It held two hand-rolled ancestors of `mkHarness`, and
they are the subject of the next section.

## `nix run` was loud, and the noise was hiding a bug

The wall of `cmp: …: Is a directory` was not cosmetic. A multi-file skill is a
directory in the store, `cmp` cannot compare one, and its non-zero exit put all
38 of them down the "this file differs" path — so a non-interactive run
"kept your version" of skills that were never installed in the first place, and
an interactive one would have asked 38 questions it had no diff to show. The
comparison is `diff -rq` now, which handles a file and a tree alike, and the
prompt's diff adds `-r` when the source is a directory.

The report that followed listed all 38 paths on one line. It prints a count and
points at `AI_SYNC=force`; the names were never the useful part.

The two `trace: warning` lines above it came from the profile enabling all six
targets while the package carries one harness's module. `mkHarness` takes a
`target` now and turns the other five off — they had nothing to write anyway.
Watch the shadowing: `mkHarness` already had a local `target` helper for
`home.file` entries, and `t == target` against a *function* is quietly false
for every target, which strips a harness down to its `settings.json` without
failing. It is `targetOf` now.

`allTargets` is a literal list that has to track the module's `targets` option.
If it goes stale the missing target stays on and warns — the old noise, not a
breakage.

## The two opencode packages were `mkHarness` written out by hand

`packages/opencode.nix` and `oh-my-opencode.nix` predated `mkHarness` and were
near-identical copies of each other. They carried every fault it has since had
fixed, and one of its own:

- they filtered `xdg.configFile`, so they shipped **9 and 10 files** where the
  same module through `mkHarness` yields 70 and 71;
- they never imported `hmModules/ai` or `profile.nix`, so `nix run .#opencode`
  had no skills, no commands and no MCP servers — the one harness that did not;
- they `cp`'d under `if [ ! -f "$target" ]`, so a file installed once was never
  updated again, silently, no matter how far the flake moved on;
- and they printed `Installed <path>` per file.

Both are `mkHarness` calls now. `packages/` is gone with them.

oh-my-opencode is why `mkHarness` has `destDir`: it is the same opencode module,
which writes `opencode/`, pointed at `~/.config/oh-my-opencode` so it can run
beside a plain opencode without either touching the other's config. Every other
harness reads and writes one directory, so `destDir` defaults to `relDir`.

`nixosModules/opencode-web` can no longer `callPackage` a file for its default
and takes `aiInputs.self.packages.${system}.opencode` instead. This is fine —
the recursion warned about above is between the *option default* and the module
the package evaluates, and `self.packages` is not that edge.

## `nix run` on a machine that home-manager already manages

`ai-sync` retargets any symlink it finds pointing into `/nix/store`, on the
assumption that such a link is one of its own. On a host where home-manager
manages the same harness, it is not: home-manager's links point into a
`…-home-manager-files/…` path, and replacing one leaves a file home-manager did
not write. The next activation refuses to touch it and the whole
`home-manager-<user>.service` fails:

```
Existing file '/home/user/.config/claude/skills/claude-code-home-manager' would be clobbered
```

Twenty-five files, one `nix run`, and a broken rebuild.

Per-file skipping is not enough. A path home-manager does not manage *today*
but starts managing after a config change fails the same way, so the check is
whole-directory and happens before anything is written: if any file in the
manifest is already a `…-home-manager-files/…` symlink, `ai-sync` says so in one
line and exits. That is the right answer anyway — home-manager has the config
there already, and keeps it current.

Recovery, if it has already happened: delete the links under the harness's
config dir whose target is in the store but *not* under `-home-manager-files`,
drop `.ai-sync-keep`, and activate again.

### Checking the directory was not enough

The first version of that check read the config directory: if any file in the
manifest was already a `…-home-manager-files/…` symlink, stand down. It broke the
same machine a second time, and the reason is worth keeping.

Recovering from the first breakage means *deleting* the links `ai-sync` took
over, so home-manager can put its own back. That leaves those paths empty — and
an empty path is not a home-manager symlink, so the check saw a machine nobody
managed and reinstalled all 63 files. The check was blind in exactly the state
it existed to handle, because the evidence it read is the evidence a failed
activation destroys.

It now reads what home-manager *declares*:
`$XDG_STATE_HOME/home-manager/gcroots/current-home` → `home-files/<destDir>`.
That is the generation's own statement of what it owns, so it is true whether or
not the files are on disk, and it covers a path home-manager only starts
managing later. The directory scan stayed as a fallback for a home-manager that
keeps no such gcroot.

`destDir`, not `relDir`: oh-my-opencode writes the opencode module's output into
a directory of its own, and home-manager managing `.config/opencode` says nothing
about `.config/oh-my-opencode`.

One trap when testing this: `XDG_STATE_HOME` is absolute and independent of
`HOME`, so overriding only `HOME` points the check at your *real* generation and
a throwaway home stands down for the wrong reason. Override both.

## `opencode` means v2 now

v1 is retired to `opencode1`, with `op1` as a short alias. The swap is wider
than a rename because of one fact: **`programs.opencode` is home-manager's own
module**, not ours, and it hardcodes `xdg.configFile."opencode/…"` with no
config-dir option. v1 went through it, which is what owned `~/.config/opencode`
and put `opencode` in `home.packages`.

So v2 could only take that directory if v1 stopped using that module. v1 is now
a self-contained module of ours, modelled on v2's, writing `opencode1/` and
wrapping the binary itself. The cost is exact and was measured by diffing the
generated file lists: v1 loses two files, `tui.json` and `themes/stylix.json` —
home-manager's `tui`, `themes`, `tools` and `commands` options are gone for v1,
stylix theming among them. Nothing else changed.

Second thing the swap turned up: v2's old wrapper set `XDG_DATA_HOME` and
friends to `…/opencode2`, and opencode appends its own `opencode` to each, so
its data was really in `~/.local/share/opencode2/opencode`. As the default it
takes the plain paths and those three exports are gone; v1's wrapper is now the
one nesting, in `~/.local/share/opencode1/opencode`.

The option names, which are the part that is easy to get wrong:

| what            | user-facing knob             | module namespace      |
|-----------------|------------------------------|-----------------------|
| opencode (v2)   | `modules.programs.opencode`  | `programs.opencode2`  |
| opencode 1      | `modules.programs.opencode1` | `programs.opencode1`  |

`programs.opencode` stays home-manager's and is simply unused — we cannot
declare it a second time, which is why v2's own namespace keeps the `2`.

`opencode-web` follows to v2, and v2 renamed the subcommand: it is `serve`,
where v1 had `web`. Same `--hostname`/`--port` flags.

### Plugins do not come along

opencode v2 requires a plugin's default export to be `{id, effect}` or
`{id, setup}` and has no v1 compatibility path, so a v1 plugin fails to load
rather than degrading. Of the eleven v1 carries, none could be verified as
working on v2 — `opencode-pty` and `@tarquinen/opencode-dcp` publish v2
entrypoints but still declare `@opencode-ai/*` (the v1 scope) as their
dependencies, and both have open issues about installing under v2. v2 therefore
ships one plugin, `opencode-claude-auth-v2`, which does declare `@opencode/plugin`.

`dcp.jsonc` stays with v1 for the same reason. `oh-my-opencode` is v1-only, so
the `oh-my-opencode` package stays on v1 too.
