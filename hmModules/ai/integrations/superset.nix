{
  lib,
  cfg,
  pkgs,
  aiInputs,
}:
with lib; let
  skillsDir = ../../../content/integrations/skills/superset;
  vendoredTag = let
    pin = builtins.match ".*\n *github-pinned: ([^\n]*)\n.*" (builtins.readFile (skillsDir + "/browser/SKILL.md"));
  in
    if pin == null
    then null
    else head pin;
  packageTag = "cli-v${cfg.integrations.superset.package.version}";

  # A no-op outside a Superset workspace ($SUPERSET_HOME_DIR unset), so the same
  # one-liner is safe on every event Superset wants to observe.
  notify = {
    type = "command";
    command = ''[ -n "$SUPERSET_HOME_DIR" ] && [ -x "$SUPERSET_HOME_DIR/hooks/notify.sh" ] && SUPERSET_AGENT_ID=claude "$SUPERSET_HOME_DIR/hooks/notify.sh" || true'';
  };

  on = [{hooks = [notify];}];
  onEvery = [
    {
      matcher = "*";
      hooks = [notify];
    }
  ];
in {
  hooks = {
    PermissionRequest = onEvery;
    PostToolUse = onEvery;
    PostToolUseFailure = onEvery;
    UserPromptSubmit = on;
    SessionStart = on;
    SessionEnd = on;
    Stop = on;
    StopFailure = on;
  };

  # Vendored, pinned to the superset-cli release: the package ships them too,
  # but listing a built package's directory at eval time is IFD.
  skills = aiInputs.viicslen-lib.lib.skills.mkSkillAttrSet skillsDir;

  options = {
    superset = {
      enable = mkEnableOption (mdDoc "Superset CLI, skills and agent-state notifications from Claude Code hooks");

      package = mkOption {
        type = types.package;
        default = aiInputs.packages.packages.${pkgs.stdenv.hostPlatform.system}.superset.cli;
        defaultText = literalExpression "aiInputs.packages.packages.\${system}.superset.cli";
        description = mdDoc "The Superset CLI the skills drive. The desktop app is separate.";
      };
    };
  };

  config = mkIf (cfg.integrations.superset.enable && cfg.integrations.superset.installPackage) {
    home.packages = [cfg.integrations.superset.package];
  };

  warnings =
    optional (cfg.integrations.superset.enable && vendoredTag != null && vendoredTag != packageTag)
    "`modules.programs.ai.integrations.superset`: the vendored skills are pinned to ${vendoredTag} but the CLI is ${packageTag}. Re-vendor with `just vendor-integration-skills superset superset-sh/superset plugins/superset/skills/<name> --pin ${packageTag}` in flakes/ai.";
}
