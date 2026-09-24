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
