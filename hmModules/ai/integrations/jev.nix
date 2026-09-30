{
  lib,
  cfg,
  pkgs,
  aiInputs,
  isAttrs,
}:
with lib; let
  jev = cfg.jev;
  bh = cfg.browser-harness;
  useHeadless = bh.enable && bh.headless.enable;

  readKey = var: file:
    optionalString (file != null) ''
      ${var}="$(cat "${file}")"
      export ${var}
    '';

  wrapper = pkgs.writeShellScriptBin "jev" ''
    set -euo pipefail
    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

    ${readKey "TYPESAFE_API_KEY" jev.typesafeApiKeyFile}
    ${readKey "TEXT_MODEL_API_KEY" jev.textModel.apiKeyFile}
    export TEXT_MODEL_BASE_URL="''${TEXT_MODEL_BASE_URL:-${jev.textModel.baseUrl}}"
    export TEXT_MODEL="''${TEXT_MODEL:-${jev.textModel.model}}"
    ${optionalString (jev.textModel.reasoning != null) ''
      export TEXT_MODEL_REASONING="''${TEXT_MODEL_REASONING:-${jev.textModel.reasoning}}"
    ''}
    ${optionalString useHeadless ''
      export BU_CDP_URL="''${BU_CDP_URL:-http://127.0.0.1:${toString bh.headless.port}}"
      # Its own daemon: sharing the MCP backend's would tie jev to whichever started it.
      export BU_NAME="''${BU_NAME:-jev}"
    ''}
    exec ${getExe jev.package} "$@"
  '';
in {
  skills = aiInputs.viicslen-lib.lib.skills.selectFromInput aiInputs.typesafe-skills [
    "skills/typesafe-ai"
  ];

  options = {
    jev = {
      enable = mkEnableOption (mdDoc "Jev Ultrafast browser agent and its local inspector (`jev`)");

      package = mkOption {
        type = types.package;
        default = aiInputs.packages.packages.${pkgs.stdenv.hostPlatform.system}.python.jev-ultrafast;
        defaultText = literalExpression "aiInputs.packages.packages.\${system}.python.jev-ultrafast";
        description = mdDoc "The jev-ultrafast package.";
      };

      typesafeApiKeyFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = mdDoc "File holding the bare TypeSafe API key, read at launch. Null leaves `TYPESAFE_API_KEY` to the environment or `./.env`.";
      };

      textModel = {
        baseUrl = mkOption {
          type = types.str;
          default = "https://openrouter.ai/api/v1";
          description = mdDoc "OpenAI-compatible endpoint that writes `TYPE_TEXT` values.";
        };

        model = mkOption {
          type = types.str;
          default = "inception/mercury-2.5";
          description = mdDoc "Model name sent to `textModel.baseUrl`. It must answer with bare JSON; `response_format` is not enforced by every provider.";
        };

        apiKeyFile = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = mdDoc "File holding the bare API key for `textModel.baseUrl`, read at launch.";
        };

        reasoning = mkOption {
          type = types.nullOr types.str;
          default = "none";
          description = mdDoc "`TEXT_MODEL_REASONING`; `none` disables reasoning. Null leaves jev's per-provider default.";
        };
      };
    };
  };

  config = mkIf jev.enable {
    home.packages = [wrapper];
  };

  warnings =
    optional (jev.enable && !(isAttrs cfg.skills))
    "`modules.programs.ai.jev.enable` adds the TypeSafe skill only when `modules.programs.ai.skills` is an attribute set.";
}
