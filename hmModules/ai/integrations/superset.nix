{
  lib,
  aiInputs,
}:
with lib; let
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
  skills = aiInputs.viicslen-lib.lib.skills.mkSkillAttrSet ../../../content/integrations/skills/superset;

  options = {
    superset = {
      enable = mkEnableOption (mdDoc "Superset skills and agent-state notifications from Claude Code hooks");
    };
  };
}
