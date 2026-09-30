{
  lib,
  config,
  osConfig,
  ...
}:
with lib; let
  name = "opencode-web";

  nixosCfg = osConfig.modules.services.${name};
  cfg = config.services.${name};

  version = config.modules.programs.opencode.default or "v2";
  launcher =
    if nixosCfg.package != null
    then getExe nixosCfg.package
    else if version == "v1"
    then getExe' config.programs.opencode1.finalPackage "opencode1"
    else getExe' config.programs.opencode2.finalPackage "opencode2";
  # v2 renamed `web` to `serve`; the flags are the same.
  subcommand =
    if version == "v1"
    then "web"
    else "serve";
in {
  options.services.${name} = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to run the opencode web server for this user.";
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = literalExpression "config.age.secrets.opencode-web.path";
      description = ''
        Path to a file containing environment variables for the service,
        such as OPENCODE_SERVER_PASSWORD. Must not be in the Nix store.

        Example file contents:
          OPENCODE_SERVER_PASSWORD=your-secret-password
      '';
    };
  };

  config = mkIf (nixosCfg.enable && cfg.enable) {
    systemd.user.services.${name} = {
      Unit = {
        Description = "Opencode web server";
        After = ["network.target"];
      };

      Service =
        {
          ExecStart = "${launcher} ${subcommand} --hostname ${nixosCfg.host} --port ${toString nixosCfg.port}";
          Restart = "on-failure";
          RestartSec = "5s";
          Environment = "PATH=${config.home.profileDirectory}/bin:/run/current-system/sw/bin:/run/wrappers/bin";
        }
        // optionalAttrs (cfg.environmentFile != null) {
          EnvironmentFile = cfg.environmentFile;
        };

      Install = {
        WantedBy = ["default.target"];
      };
    };
  };
}
