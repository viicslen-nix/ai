{
  lib,
  cfg,
  pkgs,
  aiInputs,
  isAttrs,
}:
with lib; let
  bh = cfg.browser-harness;
  package = bh.package;
  headless = bh.headless;
  cdpUrl = "http://127.0.0.1:${toString headless.port}";
in {
  mcps = {
    browser-harness =
      {
        command = getExe' package "browser-harness-mcp";
      }
      // optionalAttrs headless.enable {
        # BU_NAME keys the daemon; sharing `default` would reuse one attached to the real browser.
        env = {
          BU_CDP_URL = cdpUrl;
          BU_NAME = "headless";
        };
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

      headless = {
        enable = mkEnableOption (mdDoc ''
          a headless Chromium on its own profile for the MCP server. Agents drive it
          instead of your browser; the `browser-harness` CLI still attaches to your real one
        '');

        browser = mkOption {
          type = types.package;
          default = pkgs.chromium;
          defaultText = literalExpression "pkgs.chromium";
          description = mdDoc "Chromium-based browser run headless.";
        };

        port = mkOption {
          type = types.port;
          default = 9333;
          description = mdDoc "Remote-debugging port of the headless browser, bound to loopback.";
        };
      };
    };
  };

  config = mkIf bh.enable (mkMerge [
    {home.packages = [package];}

    (mkIf headless.enable {
      systemd.user.services.browser-harness-chrome = {
        Unit.Description = "Headless Chromium for browser-harness agents";
        Service = {
          # %D is XDG_DATA_HOME. A non-default profile also skips Chrome's "Allow remote debugging?" prompt.
          ExecStart = escapeShellArgs [
            (getExe headless.browser)
            "--headless=new"
            "--remote-debugging-address=127.0.0.1"
            "--remote-debugging-port=${toString headless.port}"
            "--user-data-dir=%D/browser-harness/chrome"
            "--no-first-run"
            "--no-default-browser-check"
          ];
          Restart = "on-failure";
        };
        Install.WantedBy = ["default.target"];
      };
    })
  ]);

  warnings =
    optional (bh.enable && !(isAttrs cfg.skills))
    "`modules.programs.ai.browser-harness.enable` adds the browser-harness skill only when `modules.programs.ai.skills` is an attribute set.";
}
