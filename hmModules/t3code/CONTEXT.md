# CONTEXT

Why `modules.programs.t3code` rebuilds the stock package before installing it,
and why the server is declared by hand.

## Why it lives here, and what it assumes of the consumer

It is opt-in like the integrations, and both default packages come from this
flake's own inputs: stable from `llm-agents`, the nightly from `packages`.
Three of the things it configures belong to the consumer's config, not to
home-manager: the `webapps` entry, the impermanence directories and the niri
bind. Each is a separate `mkMerge` element under `optionalAttrs` on the
option's existence, because an undeclared option fails the eval even under a
false `mkIf`. `osConfig` is read as `args.osConfig or {}`, and the desktop app
defaults to `services.graphical-desktop.enable`, so a standalone eval needs
neither.

The impermanence entry is written inline rather than through
`viicslen-lib`'s `mkPersistence`: reaching that helper goes through `aiInputs`,
which comes from `_module.args`, and anything that decides *which* config
attributes exist cannot read `_module.args` without infinite recursion.

## `withConnect` — the gaps in every packaging of t3code

`cfg.package` is the *stock* t3code; all three fixes are applied in the module,
so pointing the option at another packaging of it (nixpkgs, or
numtide/llm-agents.nix, which has the same gaps) still gets them.

1. **A source build bakes in no cloud config.** `scripts/lib/public-config.ts`
   feeds the repo's `.env` into both vite builds, so without it the server and
   the web client carry empty Clerk/relay literals and the client's
   `hasCloudPublicConfig()` goes false, which is what strips the T3 Connect
   block from Settings › Connections. (The `connect` subcommand still registers
   either way — it just has no relay to reach.) Upstream's documented fix for
   source builds is to copy `.env.example` — public identifiers, not secrets —
   into place, so take that verbatim rather than restating the values here.
   Costs a full rebuild of the pnpm/electron tree.
2. **The relay client T3 Connect tunnels through** is the one piece not covered
   by `.env`: upstream downloads its own cloudflared on first `t3 connect
   link`. `cloudflaredPackage` points it at the Nix one instead.
3. **SnapShots refuse git builds of niri.** The desktop app gates the feature
   on the compositor's IPC `Version` matching `^(niri )?<major>.<minor>` and
   being at least 25.11. niri-flake sets `NIRI_BUILD_VERSION_STRING` to
   `unstable <date> (commit <rev>)`, which does not match, so a niri a year
   past 25.11 gets "SnapShots require Niri 25.11 or newer". The patch widens
   the regex to also read `unstable YYYY-MM` — the year clears the gate, while
   a real release is still compared as before. It is skipped when the file is
   absent (versions before 0.0.42 have no SnapShots), but fails the build if
   the file is there and the regex has moved, instead of silently no-opping.

All three land on the unwrapped derivation — the only layer whose shape is the
same across packagings — and the outer wrapper just execs it, so the env var
survives.

## `finalPackage`, and why the desktop app comes from it

The desktop app has to come from this same derivation. Installing a stock
`t3code-desktop` alongside it silently splits the two: the CLI gets T3 Connect
and the app — which spawns its own backend out of its own output, not the
`serve` unit — does not. `out` is the CLI; the Electron app is the `desktop`
output, and it is only useful on a graphical host.

## The desktop app and the `serve` unit cannot coexist (`desktopApp`)

The Electron app has no attach mode (upstream #6097, thin-client PR #9376
unmerged as of 0.0.42): it always spawns its own backend, finds 3773 busy,
takes 3774 and opens the same `~/.t3/userdata/state.sqlite`. Both servers then
reconcile "orphaned" threads, so one thread gets a `claude --resume` under
each — duplicate work on the same thread, plus `database is locked`, plus the
T3 Connect relay re-pointed at whichever server started last. Env switches
were checked and none exist: `T3CODE_DESKTOP_WS_URL` is only in a passthrough
list, and the primary-backend start is unconditional. The only attach path is
the app's *SSH environment*, which is not worth an sshd-to-localhost hack.

So `desktopApp` defaults off whenever `serve` is on, and the local UI is a
`webapps` entry this module appends — a chromeless chromium window on the
served port, tiled rather than floating. It is declared here, not in
`webapps`, because it exists only while `serve` does. `webapps` is not
imported everywhere `t3code` is, so the definition is wrapped in
`optionalAttrs (options.modules.programs ? webapps)`: an undeclared option is
an error even under `mkIf`, and gating the attribute *name* on
`config.…webapps.enable` instead is infinite recursion. Revisit when #9376
lands.

## The systemd unit is written here, not by `t3 service install`

Upstream's own `t3 service install` writes a unit that runs a self-updating
launcher, which npm-installs new versions over itself — the server is declared
directly instead. Starting it is also what provisions a `t3 connect link` that
is still pending.

`t3 connect login`/`link` persist their authorization in `~/.t3`, alongside the
project database — losing it means re-authorizing every boot, hence the
persistence entry.

## t3code cannot join the shared worktree tree

worktrunk and workmux are both pointed at `../.worktrees/<repo>/<branch>`
(see the consumer's `modules/home-manager/programs/workmux/CONTEXT.md`). t3code is deliberately left out of that, because
its worktree location is hardcoded:

```ts
// apps/server/src/vcs/GitVcsDriverCore.ts
const worktreePath = input.path ?? path.join(worktreesDir, repoName, sanitizedBranch);
// worktreesDir = join(baseDir, "worktrees"), baseDir = T3CODE_HOME ?? ~/.t3
```

There is no setting, no `t3.json` key and no per-project override for it — the
worktree-adjacent settings that do exist (`newWorktreesStartFromOrigin`,
`defaultThreadEnvMode`, `runOnWorktreeCreate`) are behavioural. The RPC input
carries an optional explicit `path`, but every first-party caller passes `null`
and no UI surfaces it.

The only lever is `--base-dir` / `T3CODE_HOME`, and it is the wrong one: it
relocates the whole data directory — `userdata`, `caches`, the auth tokens and
project database this module persists as `.t3` — and it names the *parent* of
`worktrees`, so aiming it at the checkout directory would both collide with the
`worktrees` repo living there and scatter `userdata` beside the clones.

The shape already agrees (`<root>/worktrees/<repo>/<branch>`, slashes in the
branch turned to dashes); only the root differs. Leave it at `~/.t3`.

## `nightly` — a second instance, not a second module

`modules.programs.t3code.nightly` takes the same per-instance options as the
top level (`package`, `finalPackage`, `stateDir`, `desktopApp`, `serve.*`) from
one `instanceOptions` function, and the config loops over both. Its default
package, `t3code.nightly` from the packages subflake, already renames
everything that would collide in the profile (see that package's
`CONTEXT.md`); the module only reads the new names back from passthru, falling
back to upstream's for any other packaging.

Two things stay top-level on purpose. `cloudflaredPackage` is the same binary
for both. `snapShotShortcut` binds a fixed D-Bus name that whichever app
starts first owns, so a second bind could only ever reach the same app.

**Separate state.** The nightly's `stateDir` is `$XDG_DATA_HOME/t3code-nightly`,
set as `T3CODE_HOME` on both its binaries, so a nightly database migration can
never touch stable's `~/.t3`. The cost is a separate T3 Connect login and
project list. Stable's `stateDir` is `null` so its wrapper text — and therefore
its already-built derivation — stays exactly what it was. Persistence is
derived from `stateDir`, so it follows an override as long as it stays under
`$HOME`.

**Ports.** The nightly serves on 3783 by default: a stable desktop app that
finds 3773 taken already falls back to 3774.
