{
  lib,
  config,
  ...
}:
with lib; let
  cfg = config.modules.programs.opencode;

  enabled = {
    v1 = config.programs.opencode1.enable or false;
    v2 = config.programs.opencode2.enable or false;
  };
in {
  options.modules.programs.opencode.default = mkOption {
    type = types.enum ["v1" "v2"];
    default = "v2";
    description = mdDoc ''
      Which opencode answers to the `opencode` command, owns the
      {file}`~/.config/opencode` symlink, and runs `opencode-web`. Each version
      keeps its own config and data under `opencode1` / `opencode2` either way.
    '';
  };

  config.assertions = [
    {
      assertion = (enabled.v1 || enabled.v2) -> enabled.${cfg.default};
      message = "`modules.programs.opencode.default` is \"${cfg.default}\", but that opencode is not enabled.";
    }
  ];
}
