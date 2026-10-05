{
  lib,
  pkgs,
  config,
  aiInputs,
  ...
}:
with lib; let
  cfg = config.programs.opencode1;

  jsonFormat = pkgs.formats.json {};

  pkgsFor = aiInputs.packages.packages.${pkgs.stdenv.hostPlatform.system};

  toOpencodeShape = s: let
    isRemote = s ? url && s.url != null;
    renderedEnv = hm.mcp.renderEnv (p: "{file:${p}}") (s.env or {});
  in
    optionalAttrs (s.enabled or null != null) {inherit (s) enabled;}
    // {
      type =
        if isRemote
        then "remote"
        else "local";
    }
    // (
      if isRemote
      then {inherit (s) url;} // optionalAttrs (s.headers or {} != {}) {inherit (s) headers;}
      else
        {command = [s.command] ++ (s.args or []);}
        // optionalAttrs (renderedEnv != {}) {environment = renderedEnv;}
    );

  transformedMcpServers =
    if cfg.enableMcpIntegration && config.programs.mcp.enable && config.programs.mcp.servers != {}
    then
      mapAttrs (_: server:
        hm.mcp.transformMcpServer {
          inherit server;
          extraTransforms = [toOpencodeShape];
          exclude = ["args" "env"];
        })
      config.programs.mcp.servers
    else {};

  mergedMcpServers = transformedMcpServers // (cfg.settings.mcp or {});

  # `plugin`, singular — v2 renamed this key to `plugins`.
  settings =
    cfg.settings
    // optionalAttrs (cfg.plugin != []) {inherit (cfg) plugin;}
    // optionalAttrs (mergedMcpServers != {}) {mcp = mergedMcpServers;};

  mkEntry = content:
    if hm.strings.isPathLike content
    then {source = content;}
    else {text = content;};

  mkDir = subdir: attrs:
    mapAttrs' (name: content: nameValuePair "opencode1/${subdir}/${name}.md" (mkEntry content)) attrs;

  skillDir = import ../../builders/skillDir.nix {inherit lib pkgs;};
  mkSkills = mapAttrs' (name: content:
    nameValuePair "opencode1/skills/${name}" {
      source = skillDir name content;
      recursive = true;
    });

  opinionated = config.modules.programs.opencode1;
  isDefault = config.modules.programs.opencode.default == "v1";

  # opencode appends its own `opencode` to each XDG root, so the data lands in
  # ~/.local/share/opencode1/opencode. XDG_CONFIG_HOME stays untouched: moving
  # it would send every child process (gh, git, nu) to an empty config dir.
  wrapper = pkgs.writeShellScriptBin "opencode1" ''
    export OPENCODE_CONFIG_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/opencode1"
    export XDG_DATA_HOME="''${XDG_DATA_HOME:-$HOME/.local/share}/opencode1"
    export XDG_STATE_HOME="''${XDG_STATE_HOME:-$HOME/.local/state}/opencode1"
    export XDG_CACHE_HOME="''${XDG_CACHE_HOME:-$HOME/.cache}/opencode1"
    exec ${getExe' cfg.package "opencode"} "$@"
  '';
in {
  imports = [./default-version.nix];

  options.modules.programs.opencode1 = {
    enable = mkEnableOption (mdDoc "opencode 1");

    phpantom.enable = mkEnableOption (mdDoc "the phpantom PHP language server");

    model = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = mdDoc "The model to use for opencode 1.";
    };

    small_model = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = mdDoc "The small model to use for opencode 1.";
    };
  };

  options.programs.opencode1 = {
    enable = mkEnableOption (mdDoc "opencode 1");

    package = mkOption {
      type = types.package;
      default = aiInputs.opencode.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = literalExpression "aiInputs.opencode.packages.\${system}.default";
      description = mdDoc "The opencode 1 package, before the XDG-isolation wrapper is applied.";
    };

    finalPackage = mkOption {
      type = types.package;
      readOnly = true;
      default = wrapper;
      description = mdDoc "The `opencode1` launcher: {option}`package` pointed at its isolated config and data.";
    };

    enableMcpIntegration = mkEnableOption (mdDoc "forwarding `programs.mcp.servers` into the generated config");

    settings = mkOption {
      inherit (jsonFormat) type;
      default = {};
      description = mdDoc "Written to {file}`$XDG_CONFIG_HOME/opencode1/opencode.json`.";
    };

    plugin = mkOption {
      type = types.listOf types.str;
      default = [];
      example = literalExpression ''["opencode-pty@latest"]'';
      description = mdDoc "Plugin references, written to the `plugin` key.";
    };

    context = mkOption {
      type = types.either types.lines types.path;
      default = "";
      description = mdDoc "Global instructions, written to {file}`$XDG_CONFIG_HOME/opencode1/AGENTS.md`.";
    };

    agents = mkOption {
      type = types.attrsOf (types.either types.lines types.path);
      default = {};
      description = mdDoc "Agents, written to {file}`opencode1/agents/<name>.md`.";
    };

    commands = mkOption {
      type = types.attrsOf (types.either types.lines types.path);
      default = {};
      description = mdDoc "Commands, written to {file}`opencode1/commands/<name>.md`.";
    };

    skills = mkOption {
      type = types.attrsOf (types.either types.lines types.path);
      default = {};
      description = mdDoc ''
        Skills. A directory is linked to {file}`opencode1/skills/<name>/`;
        anything else is written as {file}`opencode1/skills/<name>/SKILL.md`.
      '';
    };
  };

  config = mkMerge [
    {
      modules.programs.opencode1.enable = mkIf (isDefault && config.programs.opencode2.enable or false) (mkDefault true);
    }

    (mkIf opinionated.enable {
      programs.opencode1 = {
        enable = true;
        enableMcpIntegration = true;

        settings = {
          autoshare = false;
          model = mkIf (opinionated.model != null) opinionated.model;
          small_model = mkIf (opinionated.small_model != null) opinionated.small_model;

          plugin = [
            # Auth
            "opencode-antigravity-auth@latest"
            "opencode-claude-auth@latest"

            # Utils
            "opencode-pty@latest"
            "@tarquinen/opencode-dcp@latest"
            "opencode-websearch-cited@latest"
            "@mohak34/opencode-notifier@latest"
            "@zenobius/opencode-skillful@latest"
            "@nick-vi/opencode-type-inject@latest"
            "@different-ai/opencode-browser@latest"
            "@dietrichgebert/ponytail@latest"
          ];

          watcher.ignore = [
            "**/node_modules/**"
            "**/.git/**"
            "**/.hg/**"
            "**/.svn/**"
            "**/.DS_Store"
            "**/dist/**"
            "**/build/**"
            "**/.next/**"
            "**/out/**"
            "**/vendor/**"
          ];

          lsp =
            {
              laravel = {
                command = ["${getExe pkgsFor.php.laravel-lsp}"];
                extensions = [".php" ".blade.php"];
              };
            }
            // optionalAttrs opinionated.phpantom.enable {
              "php intelephense".disabled = true;
              phpantom = {
                command = ["${getExe pkgsFor.php.phpantom-lsp}"];
                extensions = [".php"];
              };
            };
        };
      };
    })

    (mkIf cfg.enable {
      home.packages = [
        wrapper
        (pkgs.runCommand "op1" {} ''
          mkdir -p $out/bin
          ln -s ${wrapper}/bin/opencode1 $out/bin/op1
          ${optionalString isDefault "ln -s ${wrapper}/bin/opencode1 $out/bin/opencode"}
        '')
      ];

      home.activation.opencode1StaleSkillLinks =
        import ../../builders/staleSkillLinks.nix {inherit lib;} "${config.xdg.configHome}/opencode1/skills";

      # Per file, never the directory: opencode writes service.json in here at
      # runtime and a symlinked directory would block it.
      xdg.configFile =
        {
          "opencode1/opencode.json" = mkIf (settings != {}) {
            source = jsonFormat.generate "opencode.json" ({"$schema" = "https://opencode.ai/config.json";} // settings);
          };

          "opencode1/AGENTS.md" =
            if isPath cfg.context
            then {source = cfg.context;}
            else mkIf (cfg.context != "") {text = cfg.context;};

          "opencode1/dcp.jsonc".source = ../../content/opencode/dcp.jsonc;

          "opencode" = mkIf isDefault {
            source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/opencode1";
          };
        }
        // mkDir "agents" cfg.agents
        // mkDir "commands" cfg.commands
        // mkSkills cfg.skills;
    })
  ];
}
