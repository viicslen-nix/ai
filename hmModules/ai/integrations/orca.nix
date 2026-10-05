{
  lib,
  cfg,
  pkgs,
  aiInputs,
  isAttrs,
}:
with lib; {
  skills = aiInputs.viicslen-lib.lib.skills.mkSkillAttrSet ../../../content/integrations/skills/orca;

  options = {
    orca = {
      enable = mkEnableOption (mdDoc "Orca ADE and its discovery skills for shared ai tooling");

      package = mkOption {
        type = types.package;
        default = aiInputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.orca;
        defaultText = literalExpression "aiInputs.llm-agents.packages.\${system}.orca";
        description = mdDoc "The Orca package. It provides `orca-ide`, which the skills resolve guides through.";
      };
    };
  };

  config = mkIf (cfg.integrations.orca.enable && cfg.integrations.orca.installPackage) {
    home.packages = [cfg.integrations.orca.package];
  };

  warnings =
    optional (cfg.integrations.orca.enable && !(isAttrs cfg.skills))
    "`modules.programs.ai.integrations.orca.enable` adds the Orca skills only when `modules.programs.ai.skills` is an attribute set.";
}
