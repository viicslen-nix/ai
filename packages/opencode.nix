{
  pkgs,
  inputs,
  ...
}: let
  inherit (pkgs) lib;
  opencodePackage = inputs.opencode.packages.${pkgs.stdenv.hostPlatform.system}.default;
  hmConfig = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      aiInputs = inputs;
    };
    modules = [
      ../hmModules/opencode.nix
      {
        home.stateVersion = "25.11";
        home.username = "runner";
        home.homeDirectory = "/tmp/runner";
        modules.programs.opencode.enable = true;
      }
    ];
  };

  # Helper to find all opencode configuration files
  opencodeConfigFiles = lib.filterAttrs (name: _: lib.hasPrefix "opencode/" name) hmConfig.config.xdg.configFile;

  # Create installation commands for each file
  installCommands = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: file: ''
      rel_path="${lib.removePrefix "opencode/" name}"
      target="$CONFIG_DIR/$rel_path"
      mkdir -p "$(dirname "$target")"

      # Only install if not present, to respect user modifications
      if [ ! -f "$target" ]; then
        cp "${file.source}" "$target"
        chmod 644 "$target"
        echo "Installed $rel_path"
      fi
    '')
    opencodeConfigFiles);
in
  pkgs.writeShellScriptBin "opencode" ''
    CONFIG_DIR="$HOME/.config/opencode"

    # Ensure the directory exists
    mkdir -p "$CONFIG_DIR"

    ${installCommands}

    export OPENCODE_CONFIG_DIR="$CONFIG_DIR"
    exec ${opencodePackage}/bin/opencode "$@"
  ''
