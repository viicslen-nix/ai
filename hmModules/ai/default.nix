{
  lib,
  pkgs,
  config,
  options,
  aiInputs,
  ...
}:
  with lib; let
    name = "ai";
    namespace = "programs";

    cfg = config.modules.${namespace}.${name};
    mempalaceIntegration = import ./integrations/mempalace.nix {
      inherit
        lib
        cfg
        pkgs
        aiInputs
        isAttrs
        ;
    };
    supersetIntegration = import ./integrations/superset.nix {inherit lib;};
    coderabbitIntegration = import ./integrations/coderabbit.nix {
      inherit
        lib
        cfg
        isAttrs
        ;
    };
    openwikiIntegration = import ./integrations/openwiki.nix {
      inherit
        lib
        cfg
        pkgs
        aiInputs
        isAttrs
        ;
    };
    mcpGatewayIntegration = import ./integrations/mcp-gateway.nix {
      inherit lib cfg pkgs config;
      mcps = effectiveMcps;
    };

    commandDefinitionType = types.submodule {
      options = {
        prompt = mkOption {
          type = types.nullOr types.lines;
          default = null;
          description = mdDoc "Prompt text for structured command outputs (for example antigravity-cli).";
        };

        description = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = mdDoc "Command description for structured command outputs.";
        };

        content = mkOption {
          type = types.nullOr (types.either types.lines types.path);
          default = null;
          description = mdDoc "Raw markdown command content for markdown-based CLIs.";
        };
      };
    };

    commandValueType = types.oneOf [
      types.lines
      types.path
      commandDefinitionType
    ];

    sharedContentType = types.attrsOf (types.either types.lines types.path);
    commandContentType = types.attrsOf commandValueType;
    sharedSkillsType = types.either (types.attrsOf (types.oneOf [types.lines types.path types.str])) types.path;

    hasMcpOption = hasAttrByPath ["programs" "mcp" "servers"] options;
    hasOpencode1Option = hasAttrByPath ["programs" "opencode1" "commands"] options;
    hasOpencode1SkillsOption = hasAttrByPath ["programs" "opencode1" "skills"] options;
    hasOpencodeOption = hasAttrByPath ["programs" "opencode2" "commands"] options;
    hasOpencodeSkillsOption = hasAttrByPath ["programs" "opencode2" "skills"] options;
    hasClaudeCodeOption = hasAttrByPath ["programs" "claude-code" "commands"] options;
    hasClaudeCodeSkillsOption = hasAttrByPath ["programs" "claude-code" "skills"] options;
    hasAntigravityOption = hasAttrByPath ["programs" "antigravity-cli" "commands"] options;
    hasAntigravitySkillsOption = hasAttrByPath ["programs" "antigravity-cli" "skills"] options;
    hasGithubCopilotCliOption = hasAttrByPath ["programs" "github-copilot-cli" "agents"] options;
    hasGithubCopilotCliSkillsOption = hasAttrByPath ["programs" "github-copilot-cli" "skills"] options;
    # codex has no `commands` or `agents`, so `context` is what proves it exists.
    hasCodexOption = hasAttrByPath ["programs" "codex" "context"] options;
    hasCodexSkillsOption = hasAttrByPath ["programs" "codex" "skills"] options;

    effectiveMcps =
      cfg.mcps
      // optionalAttrs cfg.mempalace.enable mempalaceIntegration.mcps
      // optionalAttrs cfg.openwiki.enable openwikiIntegration.mcps;
    effectiveCommands =
      cfg.commands
      // optionalAttrs cfg.mempalace.enable mempalaceIntegration.commands
      // optionalAttrs cfg.coderabbit.enable coderabbitIntegration.commands;
    effectiveAgents = cfg.agents // optionalAttrs cfg.coderabbit.enable coderabbitIntegration.agents;
    # Hook lists for the same event come from several integrations, so they are
    # concatenated per event rather than overwritten.
    effectiveHooks = zipAttrsWith (_: concatLists) (
      optional cfg.superset.enable supersetIntegration.hooks
    );
    effectiveSkills =
      if isAttrs cfg.skills
      then
        cfg.skills
        // optionalAttrs cfg.mempalace.enable mempalaceIntegration.skills
        // optionalAttrs cfg.coderabbit.enable coderabbitIntegration.skills
        // optionalAttrs cfg.openwiki.enable openwikiIntegration.skills
      else cfg.skills;

    mkDefaultAttrs = attrs: mapAttrs (_: mkDefault) attrs;
    skillDir = import ../../builders/skillDir.nix {inherit lib pkgs;};
    # opencode also reads claude-code's skills directory.
    claudeCodeSkills =
      if isAttrs effectiveSkills
      then mapAttrs skillDir effectiveSkills
      else effectiveSkills;

    mkDefaultSkills = skills:
      if isAttrs skills
      then mkDefaultAttrs skills
      else mkDefault skills;
    hasGlobalContext = cfg.context != "";
    hasGlobalSkills = effectiveSkills != {};

    isPathLike = value:
      isPath value
      || (isString value && (hasPrefix builtins.storeDir value || hasPrefix "/" value));

    normalizeCommand = value:
      if isAttrs value
      then value
      else {
        prompt = null;
        description = null;
        content = value;
      };

    normalizedCommands = mapAttrs (_: normalizeCommand) effectiveCommands;

    toPromptString = command:
      if command.prompt != null
      then command.prompt
      else if command.content == null
      then ""
      else if isPathLike command.content
      then builtins.readFile command.content
      else command.content;

    toAntigravityCommand = name: command: {
      prompt = toPromptString command;
      description =
        if command.description != null
        then command.description
        else "Run ${name} command.";
    };

    toMarkdownCommand = name: command:
      if command.content != null
      then command.content
      else
        concatStringsSep "" [
          (optionalString (command.description != null) "# ${name}\n\n${command.description}\n\n")
          (toPromptString command)
        ];

    opencodeCommands = mapAttrs toMarkdownCommand normalizedCommands;
    claudeCodeCommands = mapAttrs toMarkdownCommand normalizedCommands;
    antigravityCommands = mapAttrs toAntigravityCommand normalizedCommands;
  in {
    options.modules.${namespace}.${name} = {
      enable = mkEnableOption (mdDoc "shared AI tooling") // {default = true;};

      mcps = mkOption {
        type = types.attrsOf types.attrs;
        default = {};
        description = mdDoc "MCP servers forwarded to `programs.mcp.servers`.";
        example = literalExpression ''
          {
            context7 = {
              url = "https://mcp.context7.com/mcp";
            };
          }
        '';
      };

      commands = mkOption {
        type = commandContentType;
        default = {};
        description = mdDoc "Global commands forwarded to enabled AI CLI targets.";
      };

      agents = mkOption {
        type = sharedContentType;
        default = {};
        description = mdDoc "Global agents forwarded to supported agent targets.";
      };

      context = mkOption {
        type = types.either types.lines types.path;
        default = "";
        description = mdDoc "Global context forwarded to enabled AI CLI targets.";
      };

      skills = mkOption {
        type = sharedSkillsType;
        default = {};
        description = mdDoc "Global skills forwarded to enabled AI CLI targets.";
      };

      targets = {
        opencode = mkOption {
          type = types.bool;
          default = true;
          description = mdDoc "Forward commands and agents to opencode (v2).";
        };

        opencode1 = mkOption {
          type = types.bool;
          default = true;
          description = mdDoc "Forward commands and agents to opencode 1.";
        };

        claude-code = mkOption {
          type = types.bool;
          default = true;
          description = mdDoc "Forward commands and agents to claude-code.";
        };

        antigravity-cli = mkOption {
          type = types.bool;
          default = true;
          description = mdDoc "Forward commands to antigravity-cli.";
        };

        github-copilot-cli = mkOption {
          type = types.bool;
          default = true;
          description = mdDoc "Forward agents (and MCP integration) to github copilot cli HM module.";
        };

        codex = mkOption {
          type = types.bool;
          default = true;
          description = mdDoc "Forward context and skills to codex. It takes no commands or agents.";
        };
      };

      inherit (mempalaceIntegration.options) mempalace;
      inherit (coderabbitIntegration.options) coderabbit;
      inherit (openwikiIntegration.options) openwiki;
      inherit (supersetIntegration.options) superset;
      inherit (mcpGatewayIntegration.options) gateway;
    };

    config = mkIf cfg.enable (mkMerge [
      {
        assertions =
          [
            {
              assertion = all (command: command.content != null || command.prompt != null) (attrValues normalizedCommands);
              message = "`modules.programs.ai.commands.<name>` must set either `content` or `prompt` when using attribute syntax.";
            }
          ]
          ++ mcpGatewayIntegration.assertions;

        warnings =
          optional (!hasMcpOption && effectiveMcps != {})
          "`modules.programs.ai.mcps` is set, but `programs.mcp` is unavailable in this Home Manager version."
          ++ optional (!hasOpencode1Option && cfg.targets.opencode1 && (effectiveCommands != {} || effectiveAgents != {} || hasGlobalContext || hasGlobalSkills))
          "`modules.programs.ai.targets.opencode1` is enabled, but `programs.opencode1` is unavailable."
          ++ optional (!hasOpencodeOption && cfg.targets.opencode && (effectiveCommands != {} || effectiveAgents != {} || hasGlobalContext || hasGlobalSkills))
          "`modules.programs.ai.targets.opencode` is enabled, but `programs.opencode2` is unavailable."
          ++ optional (!hasClaudeCodeOption && cfg.targets.claude-code && (effectiveCommands != {} || effectiveAgents != {} || hasGlobalContext || hasGlobalSkills))
          "`modules.programs.ai.targets.claude-code` is enabled, but `programs.claude-code` is unavailable."
          ++ optional (!hasAntigravityOption && cfg.targets.antigravity-cli && (effectiveCommands != {} || hasGlobalContext || hasGlobalSkills))
          "`modules.programs.ai.targets.antigravity-cli` is enabled, but `programs.antigravity-cli` is unavailable."
          ++ optional (!hasGithubCopilotCliOption && cfg.targets.github-copilot-cli && (effectiveAgents != {} || hasGlobalContext || hasGlobalSkills))
          "`modules.programs.ai.targets.github-copilot-cli` is enabled, but `programs.github-copilot-cli` is unavailable."
          ++ optional (!hasCodexOption && cfg.targets.codex && (hasGlobalContext || hasGlobalSkills))
          "`modules.programs.ai.targets.codex` is enabled, but `programs.codex` is unavailable."
          ++ optional (!hasOpencode1SkillsOption && cfg.targets.opencode1 && hasGlobalSkills)
          "`modules.programs.ai.skills` is set, but `programs.opencode1.skills` is unavailable."
          ++ optional (!hasOpencodeSkillsOption && cfg.targets.opencode && hasGlobalSkills)
          "`modules.programs.ai.skills` is set, but `programs.opencode2.skills` is unavailable."
          ++ optional (!hasClaudeCodeSkillsOption && cfg.targets.claude-code && hasGlobalSkills)
          "`modules.programs.ai.skills` is set, but `programs.claude-code.skills` is unavailable."
          ++ optional (!hasAntigravitySkillsOption && cfg.targets.antigravity-cli && hasGlobalSkills)
          "`modules.programs.ai.skills` is set, but `programs.antigravity-cli.skills` is unavailable."
          ++ optional (!hasGithubCopilotCliSkillsOption && cfg.targets.github-copilot-cli && hasGlobalSkills)
          "`modules.programs.ai.skills` is set, but `programs.github-copilot-cli.skills` is unavailable."
          ++ optional (!hasCodexSkillsOption && cfg.targets.codex && hasGlobalSkills)
          "`modules.programs.ai.skills` is set, but `programs.codex.skills` is unavailable."
          ++ mempalaceIntegration.warnings
          ++ coderabbitIntegration.warnings
          ++ openwikiIntegration.warnings;

      }
      # With the gateway on, clients see only the gateway; the real servers
      # become its backends.
      (optionalAttrs hasMcpOption {
        programs.mcp = mkIf (effectiveMcps != {}) {
          enable = mkDefault true;
          servers = mkDefaultAttrs (
            if cfg.gateway.enable
            then mcpGatewayIntegration.servers
            else effectiveMcps
          );
        };
      })
      (optionalAttrs hasOpencode1Option (mkIf cfg.targets.opencode1 {
        programs.opencode1 = {
          enableMcpIntegration = true;
          commands = mkDefaultAttrs opencodeCommands;
          agents = mkDefaultAttrs effectiveAgents;
          context = mkIf hasGlobalContext (mkDefault cfg.context);
          skills = mkIf (hasGlobalSkills && hasOpencode1SkillsOption) (mkDefaultSkills effectiveSkills);
        };
      }))
      (optionalAttrs hasOpencodeOption (mkIf cfg.targets.opencode {
        programs.opencode2 = {
          enableMcpIntegration = true;
          commands = mkDefaultAttrs opencodeCommands;
          agents = mkDefaultAttrs effectiveAgents;
          context = mkIf hasGlobalContext (mkDefault cfg.context);
          skills = mkIf (hasGlobalSkills && hasOpencodeSkillsOption) (mkDefaultSkills effectiveSkills);
        };
      }))
      (optionalAttrs hasClaudeCodeOption (mkIf cfg.targets.claude-code {
        programs.claude-code = {
          enableMcpIntegration = true;
          commands = mkDefaultAttrs claudeCodeCommands;
          agents = mkDefaultAttrs effectiveAgents;
          context = mkIf hasGlobalContext (mkDefault cfg.context);
          skills = mkIf (hasGlobalSkills && hasClaudeCodeSkillsOption) (mkDefaultSkills claudeCodeSkills);
          settings = optionalAttrs (effectiveHooks != {}) {hooks = effectiveHooks;};
        };
      }))
      (optionalAttrs hasAntigravityOption (mkIf cfg.targets.antigravity-cli {
        programs.antigravity-cli = {
          enableMcpIntegration = true;
          commands = mkDefaultAttrs antigravityCommands;
          context = mkIf hasGlobalContext {
            GEMINI = mkDefault cfg.context;
          };
          skills = mkIf (hasGlobalSkills && hasAntigravitySkillsOption) (mkDefaultSkills effectiveSkills);
        };
      }))
      (optionalAttrs hasGithubCopilotCliOption (mkIf cfg.targets.github-copilot-cli {
        programs.github-copilot-cli = {
          enableMcpIntegration = true;
          agents = mkDefaultAttrs effectiveAgents;
          context = mkIf hasGlobalContext (mkDefault cfg.context);
          skills = mkIf (hasGlobalSkills && hasGithubCopilotCliSkillsOption) (mkDefaultSkills effectiveSkills);
        };
      }))
      (optionalAttrs hasCodexOption (mkIf cfg.targets.codex {
        programs.codex = {
          enableMcpIntegration = true;
          context = mkIf hasGlobalContext (mkDefault cfg.context);
          skills = mkIf (hasGlobalSkills && hasCodexSkillsOption) (mkDefaultSkills effectiveSkills);
        };
      }))
      openwikiIntegration.config
      mcpGatewayIntegration.config
    ]);
  }
