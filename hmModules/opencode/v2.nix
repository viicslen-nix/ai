{
  lib,
  pkgs,
  config,
  aiInputs,
  ...
}:
with lib; let
  cfg = config.programs.opencode2;

  jsonFormat = pkgs.formats.json {};

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

  settings =
    cfg.settings
    // optionalAttrs (cfg.plugins != []) {plugins = cfg.plugins;}
    // optionalAttrs (mergedMcpServers != {}) {mcp = mergedMcpServers;};

  # v2 scans both the singular and plural name for each of these, so the plural
  # keeps the v1 module's layout and a later rename is a no-op.
  mkEntry = content:
    if hm.strings.isPathLike content
    then {source = content;}
    else {text = content;};

  mkDir = subdir: attrs:
    mapAttrs' (name: content: nameValuePair "opencode2/${subdir}/${name}.md" (mkEntry content)) attrs;

  mkSkills = attrs:
    mapAttrs' (name: content:
      if hm.strings.isPathLike content && (!isPath content || pathIsDirectory content)
      then
        nameValuePair "opencode2/skills/${name}" {
          source = content;
          recursive = true;
        }
      else nameValuePair "opencode2/skills/${name}/SKILL.md" (mkEntry content))
    attrs;
  mkDefaultAttrs = mapAttrs (_: mkDefault);

  opinionated = config.modules.programs.opencode2;
in {
  options.modules.programs.opencode2 = {
    enable = mkEnableOption (mdDoc "opencode 2");

    phpantom.enable = mkEnableOption (mdDoc "the phpantom PHP language server");

    model = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = mdDoc "The model to use for opencode 2.";
    };

    small_model = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = mdDoc "The small model to use for opencode 2.";
    };
  };

  options.programs.opencode2 = {
    enable = mkEnableOption (mdDoc "opencode 2");

    package = mkOption {
      type = types.package;
      default = aiInputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode2;
      defaultText = literalExpression "aiInputs.llm-agents.packages.\${system}.opencode2";
      description = mdDoc "The opencode 2 package, before the XDG-isolation wrapper is applied.";
    };

    enableMcpIntegration = mkEnableOption (mdDoc "forwarding `programs.mcp.servers` into the generated config");

    settings = mkOption {
      inherit (jsonFormat) type;
      default = {};
      description = mdDoc ''
        Written to {file}`$XDG_CONFIG_HOME/opencode2/opencode.json`. Merged last,
        so it overrides everything the options below generate.

        Note the v2 key names differ from v1's: `plugins`, `agents`, and an
        agent's prompt is `system`.
      '';
    };

    plugins = mkOption {
      type = types.listOf types.str;
      default = [];
      example = literalExpression ''["opencode-pty@latest"]'';
      description = mdDoc "Plugin references, written to the `plugins` key.";
    };

    context = mkOption {
      type = types.either types.lines types.path;
      default = "";
      description = mdDoc "Global instructions, written to {file}`$XDG_CONFIG_HOME/opencode2/AGENTS.md`.";
    };

    agents = mkOption {
      type = types.attrsOf (types.either types.lines types.path);
      default = {};
      description = mdDoc "Agents, written to {file}`opencode2/agents/<name>.md`.";
    };

    commands = mkOption {
      type = types.attrsOf (types.either types.lines types.path);
      default = {};
      description = mdDoc "Commands, written to {file}`opencode2/commands/<name>.md`.";
    };

    skills = mkOption {
      type = types.attrsOf (types.oneOf [types.lines types.path types.str]);
      default = {};
      description = mdDoc ''
        Skills. A directory is linked to {file}`opencode2/skills/<name>/`;
        anything else is written as {file}`opencode2/skills/<name>/SKILL.md`.
      '';
    };
  };

  config = mkMerge [
    (mkIf opinionated.enable {
      programs.opencode2 = {
        enable = true;
        enableMcpIntegration = true;

        agents = mkDefaultAttrs {
          ask = ../../content/opencode/agents/ask.md;
          debug = ../../content/opencode/agents/debug.md;
          review = ../../content/opencode/agents/review.md;
          security = ../../content/opencode/agents/security.md;
          documentation = ../../content/opencode/agents/documentation.md;
          pr-review-fixer = ../../content/opencode/agents/pr-review-fixer.md;
        };

        skills = mkDefaultAttrs {
          browser-automation = ../../content/opencode/skills/browser-automation.md;
        };

        settings = {
          model = mkIf (opinionated.model != null) opinionated.model;
          small_model = mkIf (opinionated.small_model != null) opinionated.small_model;

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
                command = ["${getExe aiInputs.packages.packages.${pkgs.stdenv.hostPlatform.system}.php.laravel-lsp}"];
                extensions = [".php" ".blade.php"];
              };
            }
            // optionalAttrs opinionated.phpantom.enable {
              "php intelephense".disabled = true;
              phpantom = {
                command = ["${getExe aiInputs.packages.packages.${pkgs.stdenv.hostPlatform.system}.php.phpantom-lsp}"];
                extensions = [".php"];
              };
            };
        };
      };
    })

    (mkIf cfg.enable {
    # v1 and v2 both derive their dirs from the XDG roots plus a literal
    # "opencode", so v2 needs its own roots or the two collide. XDG_CONFIG_HOME
    # stays untouched: moving it would send every child process opencode spawns
    # (gh, git, nu) to an empty config dir.
    home.packages = [
      (pkgs.writeShellScriptBin "opencode2" ''
        export OPENCODE_CONFIG_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/opencode2"
        export XDG_DATA_HOME="''${XDG_DATA_HOME:-$HOME/.local/share}/opencode2"
        export XDG_STATE_HOME="''${XDG_STATE_HOME:-$HOME/.local/state}/opencode2"
        export XDG_CACHE_HOME="''${XDG_CACHE_HOME:-$HOME/.cache}/opencode2"
        exec ${getExe' cfg.package "opencode2"} "$@"
      '')
    ];

    # Per file, never the directory: opencode writes service.json in here at
    # runtime and a symlinked directory would block it.
    xdg.configFile =
      {
        "opencode2/opencode.json" = mkIf (settings != {}) {
          source = jsonFormat.generate "opencode.json" ({"$schema" = "https://opencode.ai/config.json";} // settings);
        };

        "opencode2/AGENTS.md" =
          if isPath cfg.context
          then {source = cfg.context;}
          else mkIf (cfg.context != "") {text = cfg.context;};
      }
      // mkDir "agents" cfg.agents
      // mkDir "commands" cfg.commands
      // mkSkills cfg.skills;
    })
  ];
}
