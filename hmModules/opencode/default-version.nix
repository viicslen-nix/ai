{
  lib,
  config,
  options,
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
    # A harness package imports one version's module only; default to that one.
    default =
      if options.programs ? opencode2
      then "v2"
      else "v1";
    defaultText = literalExpression ''"v2", or "v1" when only the v1 module is imported'';
    description = mdDoc ''
      Which opencode answers to the `opencode` command, owns the
      {file}`~/.config/opencode` symlink, and runs `opencode-web`. Each version
      keeps its own config and data under `opencode1` / `opencode2` either way.
      The chosen version is enabled whenever the other one is.
    '';
  };

  config.assertions = [
    {
      assertion = (enabled.v1 || enabled.v2) -> enabled.${cfg.default};
      message = "`modules.programs.opencode.default` is \"${cfg.default}\", but that opencode is disabled.";
    }
  ];
}
