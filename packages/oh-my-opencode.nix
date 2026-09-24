{
  pkgs,
  inputs,
  ...
}: let
  inherit (pkgs) lib;
  opencodePackage = inputs.opencode.packages.${pkgs.stdenv.hostPlatform.system}.default;
  hmConfigOhMy = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      aiInputs = inputs;
    };
    modules = [
      ../hmModules/opencode/v1.nix
      {
        home.stateVersion = "25.11";
        home.username = "runner";
        home.homeDirectory = "/tmp/runner";
        modules.programs.opencode.enable = true;
        programs.opencode.settings.plugin = [
          "oh-my-opencode@latest"
        ];

        # Pre-configure oh-my-opencode agents
        xdg.configFile."opencode/oh-my-opencode.json".text = builtins.toJSON {
          agents = {
            sisyphus = {model = "google/gemini-claude-opus-4-5-thinking";};
            oracle = {model = "google/gemini-3-pro-preview";};
            "multimodal-looker" = {model = "google/gemini-3-flash";};
            explore = {model = "google/gemini-3-flash";};
            librarian = {model = "google/gemini-3-pro-preview";};
          };
        };
      }
    ];
  };

  # Helper to find all opencode configuration files
  opencodeConfigFiles = lib.filterAttrs (name: _: lib.hasPrefix "opencode/" name) hmConfigOhMy.config.xdg.configFile;

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
  pkgs.writeShellScriptBin "oh-my-opencode" ''
    CONFIG_DIR="$HOME/.config/oh-my-opencode"

    # Ensure the directory exists
    mkdir -p "$CONFIG_DIR"

    ${installCommands}

    export OPENCODE_CONFIG_DIR="$CONFIG_DIR"
    exec ${opencodePackage}/bin/opencode "$@"
  ''
