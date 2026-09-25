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

  config = mkIf cfg.orca.enable {
    home.packages = [cfg.orca.package];
  };

  warnings =
    optional (cfg.orca.enable && !(isAttrs cfg.skills))
    "`modules.programs.ai.orca.enable` adds the Orca skills only when `modules.programs.ai.skills` is an attribute set.";
}
