{
  lib,
  cfg,
  pkgs,
  aiInputs,
  isAttrs,
}:
with lib; let
  package = cfg.browser-harness.package;
in {
  mcps = {
    browser-harness = {
      command = getExe' package "browser-harness-mcp";
    };
  };

  skills = {
    browser-harness = "${package}/${package.pythonModule.sitePackages}/browser_harness/SKILL.md";
  };

  options = {
    browser-harness = {
      enable = mkEnableOption (mdDoc "Browser Harness CLI, MCP server and skill for shared ai tooling");

      package = mkOption {
        type = types.package;
        default = aiInputs.packages.packages.${pkgs.stdenv.hostPlatform.system}.python.browser-harness;
        defaultText = literalExpression "aiInputs.packages.packages.\${system}.python.browser-harness";
        description = mdDoc "The browser-harness package. Must be built with its MCP server.";
      };
    };
  };

  config = mkIf cfg.browser-harness.enable {
    home.packages = [package];
  };

  warnings =
    optional (cfg.browser-harness.enable && !(isAttrs cfg.skills))
    "`modules.programs.ai.browser-harness.enable` adds the browser-harness skill only when `modules.programs.ai.skills` is an attribute set.";
}
