# CONTEXT

Background for the `modules.programs.ai` integrations — the mcp-gateway
backend translation and the settings it leaves alone.

## `mcp-gateway.nix` — `toBackend`

mcp-gateway takes a single shell-ish `command` string (split with shlex), not
command+args, and calls the remote transport `http_url`. Remote endpoints
default to Streamable HTTP unless the URL names the legacy `/sse` transport —
with `streamable_http` off the gateway opens an SSE GET handshake instead, which
every `/mcp` endpoint rejects, and the backend silently never connects. The
computed attrs come first in the merge so anything set on the server itself
still wins.

## `mcp-gateway.nix` — `meta_mcp.warm_start`

Deliberately left unset: an empty list means *every* backend is warm-started,
which is what a browser-OAuth backend needs (its consent handshake runs at
startup instead of stalling the first tool call). Naming backends there would
narrow warm-start to just those.

## `mcp-gateway.nix` — `MCP_GATEWAY_CONFIG`

`list`/`get`/`add`/`remove`/`doctor` each carry their own `-c`, defaulting to a
cwd-relative `gateway.yaml`; only `serve` falls back to
`~/.config/mcp-gateway/gateway.yaml`. This env var is the one knob that points
all of them at the generated config from any directory.

## `openwiki.nix` — why an integration, not its own module

OpenWiki's `integrations install <host>` does exactly two things: add an
`openwiki mcp --host <host>` stdio server to the host's MCP config, and copy
`integrations/openwiki/SKILL.md` into its skills directory. Both of those are
already `modules.programs.ai`'s job, and its writes land in `~/.claude.json` /
`~/.claude/skills`, which this repo owns and overwrites on activation — so the
installer would be undone every rebuild. Declaring the pair here fans it out to
every enabled CLI for free. The CLI itself (`openwiki --init`, `visualize`) is
an ordinary package and carries no configuration, so it needs no module of its
own; the integration puts it on `PATH`.

## `browser-harness.nix` — the skill ships inside the wheel

browser-harness packages its `SKILL.md` as package data, so the skill comes
from the installed package, not from a vendored copy or an input, and moves
with a bump of the package.

The MCP server runs on nixpkgs' `mcp` 1.x. Upstream pins `mcp==2.1.1`, which
needs `httpx2` and `mcp-types` that nixpkgs lacks, but the server uses only
the FastMCP surface 2.x renamed to `MCPServer`, so the package rewrites that
one import.

`headless` exists because browser-harness never launches a browser: it
attaches to one that is already running, found through `BU_CDP_URL` or
a `DevToolsActivePort` file in a known profile. So headless means a separate
Chromium, run as a user service. It uses its own `--user-data-dir`, which is
also what avoids Chrome's "Allow remote debugging?" prompt, shown only on
the default profile. The MCP backend and jev are pointed at it; the shell CLI
keeps your real browser. Each sets its own `BU_NAME`. Otherwise they would
share the `default` daemon, and whichever side started that daemon first would
decide which browser every side drives.

The headless profile starts logged out of everything, so `browser-harness-profile`
(the "Browser Harness Profile" desktop entry) opens that same profile in a
window to log in or manage sessions. Chromium locks a profile to one instance,
so the launcher stops the service, runs the window on the service's own port,
and restarts the service when the window closes. Agents keep working while it
is open — their daemons reconnect to the same port. A second launch only adds a
window, guarded by a `flock`: letting it stop and restart the service would
start a headless Chromium against the locked profile and burn the unit's
restart limit. The launcher's profile path restates the unit's `%D`, so the two
must move together. Verified end to end: a jev run completed through the
window, and closing it brought the headless service back.

Nothing finds your real Vivaldi anyway: browser-harness only probes Chrome,
Chromium and Edge profile directories for `DevToolsActivePort`.

## `jev.nix` — a key-file wrapper, not an `EnvironmentFile`

jev is a CLI you launch, not a unit, so there is no systemd to hand an
`EnvironmentFile` to. The wrapper reads bare-key files at launch, which is
also what lets the text model reuse an existing bare key (CLIProxyAPI's)
instead of a second dotenv secret. `XDG_RUNTIME_DIR` is re-derived because
home-manager's agenix paths are the literal `${XDG_RUNTIME_DIR}/agenix/<n>`.

With browser-harness's `headless` enabled, the wrapper points jev at it
(`BU_CDP_URL`, `BU_NAME=jev`, both overridable from the environment). The real
browser was the default before, and it meant a visible Chrome launch plus an
"Allow" click on every fresh connection; jev's inspector shows its own
screenshots, so it needs no window.

The text helper is any OpenAI-compatible endpoint. jev sends
`response_format: json_object` but rejects anything that is not bare JSON, and
not every provider enforces the former: through CLIProxyAPI, Claude Haiku 4.5
answers inside a ```` ```json ```` fence and every `TYPE_TEXT` fails, while
Sonnet 4.6 and 5.5 answer bare in about a second.

The TypeSafe skill (`typesafe-ai`) rides with the jev integration because it
is only useful where TypeSafe is. It comes from the `typesafe-skills` input, which
is `flake = false`. Upstream ships it as a Claude plugin and through
`npx skills add`, but both install imperatively. The plugin route writes
`settings.json`, and the npx route writes into skill directories home-manager
owns, so the next activation drops either one. The repo is a few KB and holds
only skills, which makes an input the right shape. `just update-subflake ai`
bumps it.

## `orca.nix` — vendored, not an input

Orca's skills are small discovery stubs, one `SKILL.md` each. They pick the
right executable (`orca-ide` on Linux outside an Orca terminal, never bare
`orca`, which is the GNOME screen reader) and fetch the full guide from the
installed app with `skills get <name>`. So all eight together are a few hundred
lines. The repo they live in is ~870 MB of Electron, mobile and cloud code, and
a `flake = false` input would copy all of it into the store. They are vendored
with `just vendor-integration-skills orca stablyai/orca --all` into
`content/integrations/skills/orca`, not into `content/skills`: that directory is
the always-on profile set, and these stubs are dead weight without Orca
installed. `update-skills` and `skills` find the directory from the
`github-repo` metadata `gh` writes, so a later integration's vendored set needs
no recipe edit.

The guides are version-matched to the installed app, and the stubs only
resolve them. A bump of the vendored stubs therefore matters less than keeping
Orca itself current. That is why the integration installs the app too, from
`llm-agents`: it moves with `just update-subflake ai`, and it is built in
numtide's cache. The package also ships a `bin/orca` CLI shim, which collides
with the GNOME screen reader's `orca` if both end up in one profile.
