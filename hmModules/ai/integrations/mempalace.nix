{
  lib,
  cfg,
  pkgs,
  aiInputs,
  isAttrs,
}:
with lib; {
  # Contributed to `modules.programs.ai.mcps` rather than straight to
  # `programs.mcp.servers`, so it is routed like every other MCP server.
  mcps = {
    mempalace = {
      command = lib.getExe' aiInputs.packages.packages.${pkgs.stdenv.hostPlatform.system}.python.mempalace "mempalace-mcp";
    };
  };

  commands = {
    mempalace-help = ../../../content/integrations/commands/mempalace/help.md;
    mempalace-init = ../../../content/integrations/commands/mempalace/init.md;
    mempalace-mine = ../../../content/integrations/commands/mempalace/mine.md;
    mempalace-search = ../../../content/integrations/commands/mempalace/search.md;
    mempalace-status = ../../../content/integrations/commands/mempalace/status.md;
  };

  skills = {
    mempalace = ../../../content/integrations/skills/mempalace.md;
  };

  options = {
    mempalace = {
      enable = mkEnableOption (mdDoc "mempalace integration for shared ai tooling");
    };
  };

  warnings =
    optional (cfg.mempalace.enable && !(isAttrs cfg.skills))
    "`modules.programs.ai.mempalace.enable` adds a default mempalace skill only when `modules.programs.ai.skills` is an attribute set.";
}
