{
  lib,
  cfg,
  pkgs,
  aiInputs,
  isAttrs,
}:
with lib; let
  inherit (cfg.integrations.openwiki) package;
  # `openwiki integrations install <host>` writes the same MCP entry and skill
  # into ~/.claude.json and ~/.claude/skills — both Nix-owned here, so declare
  # them instead of running the installer.
  integration = "${package}/lib/node_modules/openwiki/integrations/openwiki";
in {
  mcps = {
    openwiki = {
      command = getExe package;
      # `--host` is run metadata only; every client shares this one backend.
      args = ["mcp" "--host" "claude"];
    };
  };

  skills = {
    # Just the SKILL.md; the sibling agents/ yaml are bob/codex host agents.
    openwiki = "${integration}/SKILL.md";
  };

  options = {
    openwiki = {
      enable = mkEnableOption (mdDoc "OpenWiki MCP server and skill for shared ai tooling");

      package = mkOption {
        type = types.package;
        default = aiInputs.packages.packages.${pkgs.stdenv.hostPlatform.system}.openwiki;
        defaultText = literalExpression "aiInputs.packages.packages.\${system}.openwiki";
        description = mdDoc "The OpenWiki package. It provides the CLI, the MCP server and the skill.";
      };
    };
  };

  config = mkIf (cfg.integrations.openwiki.enable && cfg.integrations.openwiki.installPackage) {
    home.packages = [package];
  };

  warnings =
    optional (cfg.integrations.openwiki.enable && !(isAttrs cfg.skills))
    "`modules.programs.ai.integrations.openwiki.enable` adds the default OpenWiki skill only when `modules.programs.ai.skills` is an attribute set.";
}
