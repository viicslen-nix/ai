# One LLM proxy (CLIProxyAPI or any gateway speaking the Anthropic, OpenAI
# Responses and Gemini APIs) for every harness. Harnesses that hold several
# providers get it beside their own; the rest get a `<bin>-<name>` launcher, so
# the plain command keeps its own login.
{
  lib,
  pkgs,
  config,
  options,
  ...
}:
with lib; let
  ai = config.modules.programs.ai;
  cfg = ai.proxy;

  jsonFormat = pkgs.formats.json {};

  root = removeSuffix "/" cfg.baseUrl;
  hasKey = cfg.apiKeyFile != null;
  # home-manager agenix reports its path with a literal `${XDG_RUNTIME_DIR}`, which only a shell expands.
  keyLink = "${config.xdg.stateHome}/ai-proxy/${cfg.name}-api-key";
  # A keyless proxy still needs something in the key slot for most clients.
  keyCommand =
    if hasKey
    then ''"$(cat ${escapeShellArg keyLink})"''
    else "none";

  apis = ["anthropic" "openai" "gemini"];
  modelsOf = api: filterAttrs (_: m: m.api == api) cfg.models;
  providerId = api: "${cfg.name}-${api}";
  providerName = api: "${cfg.label} (${
    {
      anthropic = "Anthropic";
      openai = "OpenAI";
      gemini = "Gemini";
    }.${
      api
    }
  })";
  apiOf = model: cfg.models.${model}.api or null;

  on = target: path:
    ai.enable && cfg != null && cfg.targets.${target} && hasAttrByPath path options;
  enabled = path: attrByPath (path ++ ["enable"]) false config;

  # hiPrio: as the plain command, it collides with the harness's own package.
  launcher = bin: body:
    (
      if cfg.default
      then hiPrio
      else id
    ) (pkgs.writeShellScriptBin (
        if cfg.default
        then bin
        else "${bin}-${cfg.name}"
      ) ''
        set -eu
        ${body}
      '');

  exportModel = var: model:
    optionalString (model != null) ''
      export ${var}="''${${var}:-${model}}"
    '';

  claudeLauncher = launcher "claude" ''
    ANTHROPIC_AUTH_TOKEN=${keyCommand}
    export ANTHROPIC_AUTH_TOKEN
    export ANTHROPIC_BASE_URL=${escapeShellArg root}
    export CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1
    ${exportModel "ANTHROPIC_MODEL" cfg.launchers.claude.model}
    exec ${getExe config.programs.claude-code.finalPackage} "$@"
  '';

  codexLauncher = launcher "codex" ''
    exec ${getExe config.programs.codex.package} \
      -c model_provider=${escapeShellArg cfg.name} \
      ${optionalString (cfg.launchers.codex.model != null) "-c model=${escapeShellArg cfg.launchers.codex.model}"} \
      "$@"
  '';

  copilotModel = cfg.launchers.copilot.model;
  copilotApi =
    if copilotModel != null && apiOf copilotModel != null
    then apiOf copilotModel
    else "openai";
  copilotLauncher = launcher "copilot" ''
    COPILOT_PROVIDER_API_KEY=${keyCommand}
    export COPILOT_PROVIDER_API_KEY
    ${
      if copilotApi == "anthropic"
      then ''
        export COPILOT_PROVIDER_TYPE=anthropic
        export COPILOT_PROVIDER_BASE_URL=${escapeShellArg root}
      ''
      else ''
        export COPILOT_PROVIDER_TYPE=openai
        export COPILOT_PROVIDER_BASE_URL=${escapeShellArg "${root}/v1"}
        export COPILOT_PROVIDER_WIRE_API=${
          if copilotApi == "openai"
          then "responses"
          else "completions"
        }
      ''
    }
    ${exportModel "COPILOT_MODEL" copilotModel}
    exec ${getExe' config.programs.github-copilot-cli.package "copilot"} "$@"
  '';

  # agy takes `modelProvider` only from ~/.gemini/antigravity-cli/settings.json
  # and has no config-dir variable, so the launcher runs it under a HOME of its
  # own: the real home's entries linked in, except a .gemini rebuilt from
  # home-manager's files with the proxy's settings.json.
  geminiFiles =
    filter (f: hasPrefix ".gemini/" f.target && f.target != ".gemini/antigravity-cli/settings.json")
    (attrValues config.home.file);
  geminiManifest = pkgs.writeText "agy-${cfg.name}-files" (
    concatMapStrings (f: "${f.target}\t${f.source}\n") geminiFiles
  );
  agySettings = config.home.file.".gemini/antigravity-cli/settings.json".source or (jsonFormat.generate "settings.json" {});
  antigravityLauncher = launcher "agy" ''
    real=$HOME
    home="''${XDG_DATA_HOME:-$HOME/.local/share}/agy-${cfg.name}"
    mkdir -p "$home/.gemini/antigravity-cli"

    for f in "$real"/* "$real"/.[!.]* "$real"/..?*; do
      [ -e "$f" ] || [ -L "$f" ] || continue
      name=''${f##*/}
      [ "$name" = .gemini ] && continue
      [ -e "$home/$name" ] || [ -L "$home/$name" ] || ln -s "$f" "$home/$name"
    done
    find "$home" -maxdepth 1 -xtype l -delete

    find "$home/.gemini" -type l -lname '${builtins.storeDir}/*' -delete
    while IFS="$(printf '\t')" read -r target source; do
      mkdir -p "$(dirname "$home/$target")"
      ln -sfn "$source" "$home/$target"
    done < ${geminiManifest}
    ${getExe pkgs.jq} '. + {modelProvider: "gemini"}' ${agySettings} > "$home/.gemini/antigravity-cli/settings.json"

    GEMINI_API_KEY=${keyCommand}
    export GEMINI_API_KEY
    export GOOGLE_GEMINI_BASE_URL=${escapeShellArg root}
    # agy ignores GEMINI_MODEL; a later --model still wins.
    HOME=$home exec ${getExe' config.programs.antigravity-cli.package "agy"} \
      ${optionalString (cfg.launchers.antigravity.model != null) "--model ${escapeShellArg cfg.launchers.antigravity.model}"} \
      "$@"
  '';

  opencode1Provider = api: {
    name = providerName api;
    npm =
      {
        anthropic = "@ai-sdk/anthropic";
        openai = "@ai-sdk/openai";
        gemini = "@ai-sdk/google";
      }.${
        api
      };
    options = {
      baseURL = baseUrlFor api;
      apiKey =
        if hasKey
        then "{file:${keyLink}}"
        else "none";
    };
    models = mapAttrs (id: m:
      {
        name =
          if m.name != null
          then m.name
          else id;
      }
      // optionalAttrs (m.contextWindow != null && m.maxOutput != null) {
        limit = {
          context = m.contextWindow;
          output = m.maxOutput;
        };
      })
    (modelsOf api);
  };

  opencode2Provider = api: {
    name = providerName api;
    package =
      {
        anthropic = "@opencode/ai/providers/anthropic";
        openai = "@opencode/ai/providers/openai/responses";
        gemini = "@opencode/ai/providers/google";
      }.${
        api
      };
    settings = {
      baseURL = baseUrlFor api;
      apiKey =
        if hasKey
        then "{file:${keyLink}}"
        else "none";
    };
    models = mapAttrs (id: m: {modelID = id;} // optionalAttrs (m.name != null) {inherit (m) name;}) (modelsOf api);
  };

  # The AI SDK clients all append the route to a versioned base.
  baseUrlFor = api:
    {
      anthropic = "${root}/v1";
      openai = "${root}/v1";
      gemini = "${root}/v1beta";
    }.${
      api
    };

  piProvider = api: {
    name = providerName api;
    baseUrl =
      {
        anthropic = root;
        openai = "${root}/v1";
        gemini = "${root}/v1beta";
      }.${
        api
      };
    api =
      {
        anthropic = "anthropic-messages";
        openai = "openai-responses";
        gemini = "google-generative-ai";
      }.${
        api
      };
    apiKey =
      if hasKey
      then "!cat ${escapeShellArg keyLink}"
      else "none";
    models = mapAttrsToList (id: m:
      {
        inherit id;
        inherit (m) reasoning;
      }
      // optionalAttrs (m.name != null) {inherit (m) name;}
      // optionalAttrs (m.contextWindow != null) {inherit (m) contextWindow;}
      // optionalAttrs (m.maxOutput != null) {maxTokens = m.maxOutput;})
    (modelsOf api);
  };

  usedApis = filter (api: modelsOf api != {}) apis;
  providers = mk: listToAttrs (map (api: nameValuePair (providerId api) (mk api)) usedApis);

  modelType = types.submodule ({name, ...}: {
    options = {
      name = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = mdDoc "Display name. Null shows the id.";
      };

      api = mkOption {
        type = types.enum apis;
        description = mdDoc ''
          Which of the proxy's APIs serves `${name}`: `anthropic` (Messages),
          `openai` (Responses) or `gemini`. Each becomes its own provider in
          opencode and pi.
        '';
      };

      contextWindow = mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
        description = mdDoc "Context window in tokens, for harnesses that cannot look it up.";
      };

      maxOutput = mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
        description = mdDoc "Maximum output tokens.";
      };

      reasoning = mkOption {
        type = types.bool;
        default = false;
        description = mdDoc "Whether the model thinks; pi offers thinking levels only for these.";
      };
    };
  });

  launcherModel = what:
    mkOption {
      type = types.nullOr types.str;
      default = null;
      description = mdDoc "Model the launcher starts with${what}. Null leaves the harness's own default.";
    };

  targetOption = desc:
    mkOption {
      type = types.bool;
      default = true;
      description = mdDoc desc;
    };
in {
  options.modules.programs.ai.proxy = mkOption {
    default = null;
    description = mdDoc ''
      An LLM proxy every harness can use, such as CLIProxyAPI. opencode and pi
      get it as extra providers; Claude Code, Codex, Copilot CLI and
      Antigravity get `<bin>-<name>` launchers beside the plain commands, or
      in their place with `default`.
    '';
    example = literalExpression ''
      {
        baseUrl = "https://cliproxy.tail1234.ts.net";
        apiKeyFile = config.age.secrets.cliproxyapi-api-key.path;
        models = {
          claude-opus-5-5 = { api = "anthropic"; reasoning = true; };
          gpt-6-sol = { api = "openai"; reasoning = true; };
        };
        launchers.codex.model = "gpt-6-sol";
      }
    '';
    type = types.nullOr (types.submodule ({config, ...}: {
      options = {
        name = mkOption {
          type = types.strMatching "[a-zA-Z0-9_-]+";
          default = "proxy";
          description = mdDoc "Suffix of the launchers (`claude-<name>`) and prefix of the opencode/pi provider ids (`<name>-anthropic`).";
        };

        label = mkOption {
          type = types.str;
          default = toUpper (substring 0 1 config.name) + substring 1 (-1) config.name;
          defaultText = literalExpression "the capitalized `name`";
          example = "CLIProxyAPI";
          description = mdDoc "Display name of the providers in opencode and pi: `<label> (Anthropic)`, `<label> (OpenAI)`, `<label> (Gemini)`.";
        };

        baseUrl = mkOption {
          type = types.str;
          example = "http://cliproxy:8317";
          description = mdDoc "Root URL, without `/v1`: each harness appends the path its API needs.";
        };

        apiKeyFile = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = mdDoc "File holding the bare API key, read at launch or per request. Null for a proxy that takes no key.";
        };

        models = mkOption {
          type = types.attrsOf modelType;
          default = {};
          description = mdDoc "Models listed in opencode and pi, keyed by the id the proxy serves. Neither discovers a custom provider's models.";
        };

        default = mkEnableOption (mdDoc ''
          the proxy as the only endpoint of Claude Code, Codex, Copilot CLI and
          Antigravity, in place of their own logins. Claude Code and Codex get it
          in their config files, which every caller reads; Copilot and agy take
          it only from the environment, so `copilot` and `agy` become the
          launchers, and a caller holding their store path bypasses them. No
          `<bin>-<name>` launchers are installed
        '');

        launchers = {
          claude.model = launcherModel " (`ANTHROPIC_MODEL`)";
          codex.model = launcherModel "";
          copilot.model = launcherModel "; required by Copilot unless `--model` is passed. Its `api` picks the wire format";
          antigravity.model = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "gemini-3.8-flash-high";
            description = mdDoc ''
              Model the launcher starts with, by agy's own name (`agy-<name> models`).
              agy sends the API name without the tier suffix (`gemini-3.8-flash`),
              which the proxy must serve, e.g. through a CLIProxyAPI model alias.
            '';
          };
        };

        targets = {
          claude-code = targetOption "Add the `claude-<name>` launcher.";
          codex = targetOption "Add the provider to config.toml and the `codex-<name>` launcher.";
          opencode = targetOption "Add the providers to opencode v2.";
          opencode1 = targetOption "Add the providers to opencode v1.";
          pi = targetOption "Write the providers to pi's models.json.";
          github-copilot-cli = targetOption "Add the `copilot-<name>` launcher.";
          antigravity-cli = targetOption "Add the `agy-<name>` launcher.";
        };
      };
    }));
  };

  config = mkMerge [
    (optionalAttrs (hasAttrByPath ["programs" "claude-code" "finalPackage"] options) (
      mkIf (on "claude-code" ["programs" "claude-code"] && enabled ["programs" "claude-code"] && config.programs.claude-code.package != null) {
        programs.claude-code.settings = mkIf cfg.default (
          {
            env = {
              ANTHROPIC_BASE_URL = root;
              CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY = "1";
            };
            apiKeyHelper =
              if hasKey
              then "cat ${escapeShellArg keyLink}"
              else "echo none";
          }
          // optionalAttrs (cfg.launchers.claude.model != null) {inherit (cfg.launchers.claude) model;}
        );
        home.packages = mkIf (!cfg.default) [claudeLauncher];
      }
    ))

    (optionalAttrs (hasAttrByPath ["programs" "codex" "settings"] options) (
      mkIf (on "codex" ["programs" "codex"] && enabled ["programs" "codex"]) {
        programs.codex.settings = mkMerge [
          (mkIf cfg.default ({model_provider = cfg.name;} // optionalAttrs (cfg.launchers.codex.model != null) {inherit (cfg.launchers.codex) model;}))
          {
            model_providers.${cfg.name} =
              {
                inherit (cfg) name;
                base_url = "${root}/v1";
                wire_api = "responses";
                model_catalog_url = "${root}/v1/models";
              }
              // optionalAttrs hasKey {
                auth = {
                  command = "cat";
                  args = [keyLink];
                };
              };
          }
        ];
        home.packages = mkIf (!cfg.default && config.programs.codex.package != null) [codexLauncher];
      }
    ))

    (optionalAttrs (hasAttrByPath ["programs" "github-copilot-cli" "package"] options) (
      mkIf (on "github-copilot-cli" ["programs" "github-copilot-cli"] && enabled ["programs" "github-copilot-cli"] && config.programs.github-copilot-cli.package != null) {
        home.packages = [copilotLauncher];
      }
    ))

    (optionalAttrs (hasAttrByPath ["programs" "antigravity-cli" "package"] options) (
      mkIf (on "antigravity-cli" ["programs" "antigravity-cli"] && enabled ["programs" "antigravity-cli"] && config.programs.antigravity-cli.package != null) {
        home.packages = [antigravityLauncher];
      }
    ))

    (optionalAttrs (hasAttrByPath ["programs" "opencode1" "settings"] options) (
      mkIf (on "opencode1" ["programs" "opencode1"] && usedApis != []) {
        programs.opencode1.settings.provider = providers opencode1Provider;
      }
    ))

    (optionalAttrs (hasAttrByPath ["programs" "opencode2" "settings"] options) (
      mkIf (on "opencode" ["programs" "opencode2"] && usedApis != []) {
        programs.opencode2.settings.providers = providers opencode2Provider;
      }
    ))

    # A file of our own, not pi.nix's `models`: that one is installed only
    # when absent, so a later change would never arrive.
    (optionalAttrs (hasAttrByPath ["programs" "pi" "coding-agent"] options) (
      mkIf (on "pi" ["programs" "pi" "coding-agent"] && enabled ["programs" "pi" "coding-agent"] && usedApis != []) {
        xdg.configFile."pi/models.json".source = jsonFormat.generate "models.json" {
          providers = providers piProvider;
        };
      }
    ))

    (mkIf (ai.enable && cfg != null) {
      home.activation.aiProxyKeyLink = mkIf hasKey (hm.dag.entryAfter ["writeBoundary"] ''
        (
          XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
          run mkdir -p ${escapeShellArg (dirOf keyLink)}
          run ln -sfn "${escape ["\\" "\"" "`"] cfg.apiKeyFile}" ${escapeShellArg keyLink}
        )
      '');

      warnings =
        optional (cfg.models == {} && (cfg.targets.opencode || cfg.targets.opencode1 || cfg.targets.pi))
        "`modules.programs.ai.proxy.models` is empty, so opencode and pi get no proxy provider; neither discovers a custom provider's models.";
    })
  ];
}
