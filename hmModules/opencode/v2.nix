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
    mapAttrs' (name: content: nameValuePair "opencode/${subdir}/${name}.md" (mkEntry content)) attrs;

  skillDir = import ../../builders/skillDir.nix {inherit lib pkgs;};
  mkSkills = mapAttrs' (name: content:
    nameValuePair "opencode/skills/${name}" {
      source = skillDir name content;
      recursive = true;
    });
  mkDefaultAttrs = mapAttrs (_: mkDefault);

  opinionated = config.modules.programs.opencode;
in {
  options.modules.programs.opencode = {
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
        Written to {file}`$XDG_CONFIG_HOME/opencode/opencode.json`. Merged last,
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
      description = mdDoc "Global instructions, written to {file}`$XDG_CONFIG_HOME/opencode/AGENTS.md`.";
    };

    agents = mkOption {
      type = types.attrsOf (types.either types.lines types.path);
      default = {};
      description = mdDoc "Agents, written to {file}`opencode/agents/<name>.md`.";
    };

    commands = mkOption {
      type = types.attrsOf (types.either types.lines types.path);
      default = {};
      description = mdDoc "Commands, written to {file}`opencode/commands/<name>.md`.";
    };

    skills = mkOption {
      type = types.attrsOf (types.oneOf [types.lines types.path types.str]);
      default = {};
      description = mdDoc ''
        Skills. A directory is linked to {file}`opencode/skills/<name>/`;
        anything else is written as {file}`opencode/skills/<name>/SKILL.md`.
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

          plugins = [
            "opencode-claude-auth-v2@latest"
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
      # v2 is the default, so it takes the plain XDG paths and v1 is the one
      # isolated under `opencode1`. Do not reintroduce the XDG_DATA/STATE/CACHE
      # exports: opencode appends its own `opencode` to each, so they nested the
      # data a level deeper (~/.local/share/opencode2/opencode).
      #
      # The wrapper stays for the rename — the binary this package ships is
      # still called `opencode2`.
      home.packages = [
        (pkgs.writeShellScriptBin "opencode" ''
          export OPENCODE_CONFIG_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
          exec ${getExe' cfg.package "opencode2"} "$@"
        '')
      ];

    # Per file, never the directory: opencode writes service.json in here at
    # runtime and a symlinked directory would block it.
    xdg.configFile =
      {
        "opencode/opencode.json" = mkIf (settings != {}) {
          source = jsonFormat.generate "opencode.json" ({"$schema" = "https://opencode.ai/config.json";} // settings);
        };

        "opencode/AGENTS.md" =
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
