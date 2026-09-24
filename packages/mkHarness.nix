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
  # Path under $XDG_CONFIG_HOME that the module writes into.
  subdir ? name,
}: let
  inherit (pkgs) lib;

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
        {
          home.stateVersion = "25.11";
          home.username = "runner";
          home.homeDirectory = "/tmp/runner";
          # So the modules write to <subdir>, not ~/.<subdir>.
          home.preferXdgDirectories = true;
        }
      ];
  };

  owned = lib.filterAttrs (n: _: lib.hasPrefix "${subdir}/" n) hmConfig.config.xdg.configFile;

  # One line per file: relative path, tab, store path. Built at eval time so
  # the wrapper does no work beyond reading it.
  manifest = pkgs.writeText "${name}-manifest" (
    lib.concatStrings (lib.mapAttrsToList (
        n: f: "${lib.removePrefix "${subdir}/" n}\t${f.source}\n"
      )
      owned)
  );

  syncScript = pkgs.runCommand "ai-sync" {} ''
    install -Dm755 ${./sync.sh} $out/bin/ai-sync
    patchShebangs $out/bin/ai-sync
  '';
in
  pkgs.writeShellScriptBin name ''
    config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/${subdir}"
    ${syncScript}/bin/ai-sync ${manifest} "$config_dir"
    ${lib.optionalString (configDirVar != null) ''export ${configDirVar}="$config_dir"''}
    exec ${lib.getExe' package mainProgram} "$@"
  ''
