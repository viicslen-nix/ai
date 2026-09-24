{
  lib,
  pkgs,
  config,
  aiInputs,
  ...
}:
with lib; let
  name = "opencode";
  namespace = "programs";

  cfg = config.modules.${namespace}.${name};
in {
  # Define the configuration options for this module
  options.modules.${namespace}.${name} = {
    enable = mkEnableOption (mdDoc name);

    phpantom.enable = mkEnableOption (mdDoc "the phpantom PHP language server");

    model = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = mdDoc "The model to use for opencode.";
    };

    small_model = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = mdDoc "The small model to use for opencode.";
    };
  };

  # Apply configuration if the module is enabled
  config = mkIf cfg.enable {
    programs.opencode = {
      enable = true;
      package = aiInputs.opencode.packages.${pkgs.stdenv.hostPlatform.system}.default;
      enableMcpIntegration = true;

      # Configure available agents from local markdown files
      agents = {
        ask = ../../content/opencode/agents/ask.md;
        debug = ../../content/opencode/agents/debug.md;
        review = ../../content/opencode/agents/review.md;
        security = ../../content/opencode/agents/security.md;
        documentation = ../../content/opencode/agents/documentation.md;
        pr-review-fixer = ../../content/opencode/agents/pr-review-fixer.md;
      };

      # Configure available skills
      skills = {
        browser-automation = ../../content/opencode/skills/browser-automation.md;
      };

      # Main Opencode settings
      settings = {
        autoshare = false;
        # Use configured models if provided
        model = mkIf (cfg.model != null) cfg.model;
        small_model = mkIf (cfg.small_model != null) cfg.small_model;

        # File patterns to ignore
        watcher.ignore = [
          "**/node_modules/**"
          "**/.git/**"
          "**/.hg/**"
          "**/.svn/**"
          "**/.DS_Store"
          "**/dist/**"
          "**/build/**"
          "**/.next/**"
          "**/out/**"
          "**/vendor/**"
        ];

        # Language Server Protocol configuration
        lsp =
          {
            laravel = {
              command = ["${lib.getExe aiInputs.packages.packages.${pkgs.stdenv.hostPlatform.system}.php.laravel-lsp}"];
              extensions = [".php" ".blade.php"];
            };
          }
          // optionalAttrs cfg.phpantom.enable {
            "php intelephense".disabled = true;
            phpantom = {
              command = ["${lib.getExe aiInputs.packages.packages.${pkgs.stdenv.hostPlatform.system}.php.phpantom-lsp}"];
              extensions = [".php"];
            };
          };

        # Installed plugins
        plugin = [
          # Auth
          "opencode-antigravity-auth@latest"
          "opencode-claude-auth@latest"

          # Utils
          "opencode-pty@latest"
          "@tarquinen/opencode-dcp@latest"
          "opencode-websearch-cited@latest"
          "@mohak34/opencode-notifier@latest"
          "@zenobius/opencode-skillful@latest"
          "@nick-vi/opencode-type-inject@latest"
          "@different-ai/opencode-browser@latest"
          "@dietrichgebert/ponytail@latest"
        ];
      };
    };

    xdg.configFile."opencode/dcp.jsonc".source = ../../content/opencode/dcp.jsonc;
  };
}
