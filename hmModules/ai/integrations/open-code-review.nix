{
  lib,
  cfg,
  pkgs,
  aiInputs,
  isAttrs,
}:
with lib; let
  ocr = cfg.integrations.open-code-review;
  skillsDir = ../../../content/integrations/skills/open-code-review;
  vendoredTag = head (builtins.match ".*\n *github-pinned: ([^\n]*)\n.*" (builtins.readFile (skillsDir + "/open-code-review/SKILL.md")));
  packageTag = "v${ocr.package.version}";
in {
  skills = {
    open-code-review-delegate = skillsDir + "/open-code-review-delegate";
    # Our package moves the global rule file to XDG.
    open-code-review = aiInputs.viicslen-lib.lib.skills.patchSkill (skillsDir + "/open-code-review/SKILL.md") [
      {
        from = "`~/.opencodereview/rule.json`";
        to = "`\${XDG_CONFIG_HOME:-~/.config}/opencodereview/rule.json`";
      }
    ];
  };

  options = {
    open-code-review = {
      enable = mkEnableOption (mdDoc "Open Code Review (`ocr`) and its native and delegate review skills");

      package = mkOption {
        type = types.package;
        default = aiInputs.packages.packages.${pkgs.stdenv.hostPlatform.system}.open-code-review;
        defaultText = literalExpression "aiInputs.packages.packages.\${system}.open-code-review";
        description = mdDoc "The `ocr` CLI the skills run.";
      };
    };
  };

  config = mkIf (ocr.enable && ocr.installPackage) {
    home.packages = [ocr.package];
  };

  warnings =
    optional (ocr.enable && !(isAttrs cfg.skills))
    "`modules.programs.ai.integrations.open-code-review.enable` adds the OCR skills only when `modules.programs.ai.skills` is an attribute set."
    ++ optional (ocr.enable && vendoredTag != packageTag)
    "`modules.programs.ai.integrations.open-code-review`: the vendored skills are pinned to ${vendoredTag} but the CLI is ${packageTag}. Re-vendor with `just vendor-integration-skills open-code-review alibaba/open-code-review skills/<name> --pin ${packageTag}` in flakes/ai.";
}
