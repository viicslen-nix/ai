{
  lib,
  pkgs,
  config,
  aiInputs,
  options,
  ...
}:
with lib; let
  name = "opencode-web";
  namespace = "services";

  cfg = config.modules.${namespace}.${name};
  homeManagerLoaded = builtins.hasAttr "home-manager" options;
in {
  options.modules.${namespace}.${name} = {
    enable = mkEnableOption "opencode web server service";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./packages/opencode.nix {inputs = aiInputs;};
      defaultText = literalExpression "pkgs.callPackage ./packages/opencode.nix { inputs = aiInputs; }";
      description = "The opencode package to use for the web service.";
    };

    port = mkOption {
      type = types.port;
      default = 43037;
      description = "The port the opencode web server will listen on.";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "The host address the opencode web server will bind to.";
    };

    hostname = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "opencode.local";
      description = ''
        Optional hostname that should resolve to this service.
        When set it is appended to networking.hosts."127.0.0.1".
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = homeManagerLoaded;
        message = "modules.services.opencode-web requires home-manager to be loaded as a NixOS module.";
      }
    ];

    networking.hosts = mkIf (cfg.hostname != null) {
      "127.0.0.1" = [cfg.hostname];
    };

    # Inject the per-user HM module into every home-manager user
    home-manager.sharedModules = [./hmModules/service.nix];
  };
}
