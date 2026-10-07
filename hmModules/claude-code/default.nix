{
  lib,
  pkgs,
  config,
  aiInputs,
  ...
}:
with lib; let
  name = "claude-code";
  namespace = "programs";

  cfg = config.modules.${namespace}.${name};

  mkMarketplace = repo: {
    source = {
      source = "github";
      inherit repo;
    };
  };

  modsDir = ../../content/claude-mods;
  modNames = attrNames (filterAttrs (_: type: type == "directory") (builtins.readDir modsDir));
  # A `path:` flake copies gitignored files too, so the generated types are dropped here.
  modSource = name:
    builtins.path {
      name = "claude-mod-${name}";
      path = modsDir + "/${name}";
      filter = path: _:
        !(elem (baseNameOf path) ["tests" "tsconfig.json" ".gitignore"])
        && !(hasSuffix "/.claude-plugin/types" (toString path));
    };
in {
  options.modules.${namespace}.${name} = {
    enable = mkEnableOption (mdDoc "global Claude Code settings") // {default = true;};

    marketplaces = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = mdDoc "Plugin marketplaces to register, as `<name> = \"<owner>/<repo>\"`.";
      example = literalExpression ''{ponytail = "DietrichGebert/ponytail";}'';
    };

    plugins = mkOption {
      type = types.attrsOf types.bool;
      default = {};
      description = mdDoc "Plugins to enable or disable, keyed by `<plugin>@<marketplace>`.";
      example = literalExpression ''{"ponytail@ponytail" = true;}'';
    };

    settings = mkOption {
      type = types.attrs;
      default = {};
      description = mdDoc "Extra `settings.json` entries, merged over the defaults below.";
    };

    pluginDirs = mkOption {
      type = types.listOf types.path;
      default = [];
      description = mdDoc "Plugin directories loaded through `CLAUDE_CODE_PLUGIN_DIRS`, the one writer of that variable.";
    };

    mods = genAttrs modNames (mod: {
      enable = mkEnableOption (mdDoc "the `${mod}` mod from `content/claude-mods`");
    });
  };

  config = mkMerge [
    {
      modules.${namespace}.${name}.pluginDirs = map modSource (filter (mod: cfg.mods.${mod}.enable) modNames);

      programs.claude-code.settings = mkIf (cfg.pluginDirs != []) {
        env.CLAUDE_CODE_PLUGIN_DIRS = concatStringsSep ":" (map toString cfg.pluginDirs);
      };
    }
    (mkIf cfg.enable {
      # Don't drop `force`: the next activation then aborts on a stale settings.json.backup.
      home.file."${config.programs.claude-code.configDir}/settings.json".force = true;

      # Carries ~/.claude.json with it, and herdr resolves its hook directory
      # through the CLAUDE_CONFIG_DIR this exports.
      programs.claude-code.configDir = "${config.xdg.configHome}/claude";

      programs.claude-code.settings =
        recursiveUpdate {
          model = "opus[1m]";
          effortLevel = "high";

          autoCompactWindow = 500000;

          permissions.defaultMode = "auto";

          statusLine = {
            type = "command";
            # Keep this a store path; `npx -y ccstatusline@latest` re-resolves every render.
            command = getExe aiInputs.packages.packages.${pkgs.stdenv.hostPlatform.system}.ccstatusline;
            padding = 0;
            refreshInterval = 10;
          };

          # `programs.claude-code.marketplaces` only emits `source = "directory"`
          # entries, so github ones are written straight through.
          extraKnownMarketplaces = mapAttrs (_: mkMarketplace) cfg.marketplaces;
          enabledPlugins = cfg.plugins;

          workflowKeywordTriggerEnabled = true;
          syntaxHighlightingDisabled = false;
          alwaysThinkingEnabled = true;
          autoMemoryEnabled = false;
          tui = "fullscreen";
          skipDangerousModePermissionPrompt = true;
          theme = "auto";
          editorMode = "vim";
          verbose = false;
          remoteControlAtStartup = false;
          inputNeededNotifEnabled = true;
          agentPushNotifEnabled = true;
        }
        cfg.settings;
    })
  ];
}
