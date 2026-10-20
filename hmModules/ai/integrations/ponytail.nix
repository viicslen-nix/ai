{
  lib,
  cfg,
  config,
  aiInputs,
  isAttrs,
  options,
}:
with lib; let
  plugin = "@dietrichgebert/ponytail@latest";
  src = aiInputs.ponytail;

  manifest = importJSON "${src}/.codex-plugin/plugin.json";
  hooksFile = removePrefix "./" manifest.hooks;
  snake = name: concatStrings (imap0 (i: c: optionalString (i > 0 && c != toLower c) "_" + toLower c) (stringToCharacters name));

  # Mirrors codex's `hook_hash` (sorted compact JSON of the normalized hook), which is what `/hooks` would record.
  trust = concatMapAttrs (event: groups:
    listToAttrs (concatLists (imap0 (gi: group:
      imap0 (hi: hook:
        nameValuePair "ponytail@ponytail:${hooksFile}:${snake event}:${toString gi}:${toString hi}" {
          trusted_hash = "sha256:${builtins.hashString "sha256" (builtins.toJSON ({
              event_name = snake event;
              hooks = [
                ({
                    inherit (hook) type command;
                    async = hook.async or false;
                    timeout = max 1 (hook.timeout or 600);
                  }
                  // filterAttrs (name: _: elem name ["statusMessage" "commandWindows" "additionalContextLimit"]) hook)
              ];
            }
            // optionalAttrs (group ? matcher) {inherit (group) matcher;}))}";
        })
      group.hooks)
    groups)))
  (importJSON "${src}/${hooksFile}").hooks;

  codexPlugins = "${config.xdg.configHome}/codex/plugins/cache/ponytail/ponytail";
in {
  skills = aiInputs.viicslen-lib.lib.skills.mkSkillAttrSet (aiInputs.viicslen-lib.lib.skills.fromInput src "skills");

  context = builtins.readFile "${src}/AGENTS.md";

  # These load ponytail as a plugin (ruleset, hooks, commands), so they skip the skills and context.
  nativeTargets = ["claude-code" "opencode" "opencode1" "codex"];

  options = {
    ponytail.enable = mkEnableOption (mdDoc "ponytail, as a plugin where the harness has one and as skills plus its ruleset elsewhere");
  };

  config = mkIf cfg.integrations.ponytail.enable (mkMerge [
    (optionalAttrs (hasAttrByPath ["modules" "programs" "claude-code" "marketplaces"] options) {
      modules.programs.claude-code = {
        marketplaces.ponytail = "DietrichGebert/ponytail";
        plugins."ponytail@ponytail" = true;
      };
    })
    # `settings`, not the `plugin(s)` option: the module overwrites the settings list with it.
    (optionalAttrs (hasAttrByPath ["programs" "opencode1" "settings"] options) {
      programs.opencode1.settings.plugin = [plugin];
    })
    (optionalAttrs (hasAttrByPath ["programs" "opencode2" "settings"] options) {
      programs.opencode2.settings.plugins = [plugin];
    })
    (optionalAttrs (hasAttrByPath ["programs" "codex" "settings"] options) (mkIf cfg.targets.codex {
      programs.codex.settings = {
        marketplaces.ponytail = {
          source_type = "local";
          source = "${src}";
        };
        plugins."ponytail@ponytail".enabled = true;
        hooks.state = trust;
      };

      # A copy, not a symlink: codex reads a symlinked plugin root as not installed.
      home.activation.ponytailCodexPlugin = hm.dag.entryAfter ["writeBoundary"] ''
        run rm -rf "${codexPlugins}"
        run mkdir -p "${codexPlugins}"
        run cp -r --no-preserve=mode ${src} "${codexPlugins}/${manifest.version}"
      '';
    }))
  ]);

  warnings =
    optional (cfg.integrations.ponytail.enable && !(isAttrs cfg.skills))
    "`modules.programs.ai.integrations.ponytail.enable` adds the ponytail skills only when `modules.programs.ai.skills` is an attribute set.";
}
