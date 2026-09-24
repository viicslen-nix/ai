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

## Still tied to the nixos repo

`hmModules/claude-code` reads `pkgs.local.ccstatusline`, which comes from that
repo's overlay. It resolves today because `useGlobalPkgs` hands the host's
`pkgs` in, and it will break the moment this flake is consumed anywhere else.
It needs to become an option before the `nix run` packages are real.
