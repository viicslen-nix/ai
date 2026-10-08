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

  jsonFormat = pkgs.formats.json {};
  jq = getExe pkgs.jq;
  settingsPath = "${config.programs.claude-code.configDir}/settings.json";
  stateDir = "${config.xdg.stateHome}/claude-code";
  defaultsFile = jsonFormat.generate "claude-code-settings-defaults.json" cfg.defaults;
  # home-manager's own rendering, so marketplaces and disabled MCP servers stay included.
  enforcedFile = config.home.file.${settingsPath}.source;

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
      description = mdDoc "Extra `settings.json` entries, merged over the defaults below. Rewritten on every activation.";
    };

    defaults = mkOption {
      inherit (jsonFormat) type;
      default = {};
      description = mdDoc ''
        `settings.json` entries Claude Code may change at runtime (`/effort`, `/model`, `/config`).
        A Nix change applies unless the value was changed at runtime.
      '';
      example = literalExpression ''{effortLevel = "max";}'';
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
      # Claude Code writes through a store symlink and fails on EROFS; the activation below writes a real file.
      home.file.${settingsPath}.enable = mkForce false;

      home.activation.claudeCodeSettings = hm.dag.entryAfter ["linkGeneration"] ''
        settings=${escapeShellArg settingsPath}
        state=${escapeShellArg stateDir}

        current='{}'
        if [[ -s $settings ]]; then
          current=$(${jq} -c 'if type == "object" then . else error("not an object") end' "$settings") || {
            warnEcho "$settings is not a JSON object; rewriting it from Nix"
            current='{}'
          }
        fi

        oldDefaults=$state/defaults.json
        [[ -s $oldDefaults ]] || oldDefaults=/dev/null
        oldEnforced=$state/enforced.json
        [[ -s $oldEnforced ]] || oldEnforced=/dev/null

        merged=$(${jq} -n --argjson current "$current" \
          --slurpfile oldDefaults "$oldDefaults" --slurpfile newDefaults ${defaultsFile} \
          --slurpfile oldEnforced "$oldEnforced" --slurpfile newEnforced ${enforcedFile} \
          -f ${./merge-settings.jq})

        if [[ ! -v DRY_RUN ]]; then
          if [[ -L $settings ]]; then rm "$settings"; fi
          mkdir -p "$(dirname "$settings")" "$state"
          printf '%s\n' "$merged" > "$settings.hm-tmp"
          mv "$settings.hm-tmp" "$settings"
          install -m644 ${defaultsFile} "$state/defaults.json"
          install -m644 ${enforcedFile} "$state/enforced.json"
        fi
      '';

      # Carries ~/.claude.json with it, and herdr resolves its hook directory
      # through the CLAUDE_CONFIG_DIR this exports.
      programs.claude-code.configDir = "${config.xdg.configHome}/claude";

      modules.${namespace}.${name}.defaults = mapAttrsRecursive (_: mkDefault) {
        model = "opus[1m]";
        effortLevel = "high";

        autoCompactWindow = 500000;

        permissions.defaultMode = "auto";

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
      };

      programs.claude-code.settings =
        recursiveUpdate {
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
        }
        cfg.settings;
    })
  ];
}
