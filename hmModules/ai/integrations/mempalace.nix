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
      command = lib.getExe' cfg.integrations.mempalace.package "mempalace-mcp";
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

      package = mkOption {
        type = types.package;
        default = aiInputs.packages.packages.${pkgs.stdenv.hostPlatform.system}.python.mempalace;
        defaultText = literalExpression "aiInputs.packages.packages.\${system}.python.mempalace";
        description = mdDoc "The mempalace package. It provides the `mempalace` CLI and the `mempalace-mcp` server.";
      };
    };
  };

  config = mkIf (cfg.integrations.mempalace.enable && cfg.integrations.mempalace.installPackage) {
    home.packages = [cfg.integrations.mempalace.package];
  };

  warnings =
    optional (cfg.integrations.mempalace.enable && !(isAttrs cfg.skills))
    "`modules.programs.ai.integrations.mempalace.enable` adds a default mempalace skill only when `modules.programs.ai.skills` is an attribute set.";
}
