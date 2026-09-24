# Turn a harness's home-manager module into a runnable package, so
# `nix run <this-flake>#<name>` gives a fully configured harness on a machine
# that has never seen this config.
#
# The module is the single source of truth: the same file a host imports
# through home-manager is evaluated here against a throwaway user, and the
# files it would have written become the payload.
{
  pkgs,
  inputs,
}: {
  # `nix run .#<name>`, and the name of the binary the wrapper installs.
  name,
  # Modules this harness needs beyond the shared `ai` module and the profile,
  # which every harness gets. Empty for a harness whose module ships with
  # home-manager itself.
  modules ? [],
  # Config fragment that turns the module on.
  enable ? {},
  # The binary the wrapper ultimately execs.
  package,
  mainProgram ? name,
  # Env var that points the harness at its config dir. `null` means the harness
  # has no such knob and owns a fixed path under $HOME — see antigravity.
  configDirVar ? null,
  # This harness's attribute under `modules.programs.ai.targets`. Every other
  # target is turned off: a harness package carries one harness, so the rest
  # would only warn about a module that is not there.
  target,
  # Where the harness's module writes, relative to $HOME. Not every harness is
  # XDG-aware — antigravity owns ~/.gemini outright.
  relDir ? ".config/${name}",
}: let
  inherit (pkgs) lib;

  # Keep in sync with `options.modules.programs.ai.targets`.
  allTargets = [
    "opencode"
    "opencode2"
    "claude-code"
    "antigravity-cli"
    "github-copilot-cli"
    "codex"
  ];

  hmConfig = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs.aiInputs = inputs;
    modules =
      [
        ../hmModules/ai
        ../hmModules/profile.nix
      ]
      ++ modules
      ++ [
        enable
        {modules.programs.ai.targets = lib.genAttrs allTargets (t: t == target);}
        {
          home.stateVersion = "25.11";
          home.username = "runner";
          home.homeDirectory = "/tmp/runner";
          # So the modules write under .config, not ~/.<name>.
          home.preferXdgDirectories = true;
        }
      ];
  };

  # `home.file`, not `xdg.configFile`: a module that writes an explicit
  # `${config.xdg.configHome}/<x>` path never appears in the latter. Upstream
  # codex leaves a leading slash on its targets, so strip one before matching.
  targetOf = f: lib.removePrefix "/" f.target;
  owned =
    lib.filter (f: lib.hasPrefix "${relDir}/" (targetOf f))
    (lib.attrValues hmConfig.config.home.file);

  # One line per file: relative path, tab, store path. Built at eval time so
  # the wrapper does no work beyond reading it.
  manifest = pkgs.writeText "${name}-manifest" (
    lib.concatMapStrings (
      f: "${lib.removePrefix "${relDir}/" (targetOf f)}\t${f.source}\n"
    )
    owned
  );

  syncScript = pkgs.runCommand "ai-sync" {} ''
    install -Dm755 ${./sync.sh} $out/bin/ai-sync
    patchShebangs $out/bin/ai-sync
  '';
in
  pkgs.writeShellScriptBin name ''
    config_dir="$HOME/${relDir}"
    ${syncScript}/bin/ai-sync ${manifest} "$config_dir"
    ${lib.optionalString (configDirVar != null) ''export ${configDirVar}="$config_dir"''}
    exec ${lib.getExe' package mainProgram} "$@"
  ''
