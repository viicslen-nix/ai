{
  lib,
  cfg,
  pkgs,
  aiInputs,
  isAttrs,
}:
with lib; {
  commands = {
    coderabbit-review = ../../../content/integrations/commands/coderabbit/review.md;
  };

  agents = {
    coderabbit-reviewer = ../../../content/integrations/agents/coderabbit/reviewer.md;
  };

  skills = {
    coderabbit-autofix = ../../../content/integrations/skills/coderabbit/autofix/SKILL.md;
    coderabbit-review = ../../../content/integrations/skills/coderabbit/review/SKILL.md;
  };

  options = {
    coderabbit = {
      enable = mkEnableOption (mdDoc "CodeRabbit commands, skills, and agent for shared ai tooling");

      package = mkOption {
        type = types.package;
        default = aiInputs.packages.packages.${pkgs.stdenv.hostPlatform.system}.coderabbit;
        defaultText = literalExpression "aiInputs.packages.packages.\${system}.coderabbit";
        description = mdDoc "The CodeRabbit CLI the skills and agent run.";
      };
    };
  };

  config = mkIf (cfg.integrations.coderabbit.enable && cfg.integrations.coderabbit.installPackage) {
    home.packages = [cfg.integrations.coderabbit.package];
  };

  warnings =
    optional (cfg.integrations.coderabbit.enable && !(isAttrs cfg.skills))
    "`modules.programs.ai.integrations.coderabbit.enable` adds default CodeRabbit skills only when `modules.programs.ai.skills` is an attribute set.";
}
