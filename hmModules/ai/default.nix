{
  lib,
  pkgs,
  config,
  options,
  aiInputs,
  ...
} @ args:
with lib; let
  name = "ai";
  namespace = "programs";
  # A special arg only under the NixOS module; a standalone (`nix run`) eval has none.
  osConfig = args.osConfig or {};

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
  supersetIntegration = import ./integrations/superset.nix {inherit lib cfg pkgs aiInputs;};
  coderabbitIntegration = import ./integrations/coderabbit.nix {
    inherit
      lib
      cfg
      pkgs
      aiInputs
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
  orcaIntegration = import ./integrations/orca.nix {
    inherit
      lib
      cfg
      pkgs
      aiInputs
      isAttrs
      ;
  };
  browserHarnessIntegration = import ./integrations/browser-harness.nix {
    inherit
      lib
      cfg
      pkgs
      aiInputs
      osConfig
      isAttrs
      ;
  };
  jevIntegration = import ./integrations/jev.nix {
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
    // optionalAttrs cfg.integrations.mempalace.enable mempalaceIntegration.mcps
    // optionalAttrs cfg.integrations.openwiki.enable openwikiIntegration.mcps
    // optionalAttrs cfg.integrations.browser-harness.enable browserHarnessIntegration.mcps;
  effectiveCommands =
    cfg.commands
    // optionalAttrs cfg.integrations.mempalace.enable mempalaceIntegration.commands
    // optionalAttrs cfg.integrations.coderabbit.enable coderabbitIntegration.commands;
  effectiveAgents = cfg.agents // optionalAttrs cfg.integrations.coderabbit.enable coderabbitIntegration.agents;
  # Hook lists for the same event come from several integrations, so they are
  # concatenated per event rather than overwritten.
  effectiveHooks = zipAttrsWith (_: concatLists) (
    optional cfg.integrations.superset.enable supersetIntegration.hooks
  );
  skillIntegrations = {
    mempalace = mempalaceIntegration;
    coderabbit = coderabbitIntegration;
    openwiki = openwikiIntegration;
    orca = orcaIntegration;
    browser-harness = browserHarnessIntegration;
    jev = jevIntegration;
    superset = supersetIntegration;
  };
  allIntegrations = skillIntegrations // {gateway = mcpGatewayIntegration;};
  renameSkills = import ../../builders/renameSkills.nix {inherit lib pkgs;};
  skillDir = import ../../builders/skillDir.nix {inherit lib pkgs;};
  enabledIntegrations = filter (integration: cfg.integrations.${integration}.enable) (attrNames skillIntegrations);

  # A namespaced skill is `<ns>:<short>` in Claude Code (a plugin) and
  # `<ns>-<short>` everywhere else; `short` drops an upstream `<ns>-` prefix.
  member = ns: orig: content: let
    short = removePrefix "${ns}-" orig;
  in {
    inherit ns orig content short;
    flat =
      if orig == ns
      then orig
      else "${ns}-${short}";
    plugin = "${ns}:${short}";
  };
  integrationMembers = concatMap (integration: let
    ns = cfg.integrations.${integration}.skillNamespace;
  in
    optionals (ns != "") (mapAttrsToList (member ns) skillIntegrations.${integration}.skills))
  enabledIntegrations;
  collectionMembers = concatLists (mapAttrsToList (ns: origs:
    map (orig: member ns orig cfg.skills.${orig}) (filter (orig: cfg.skills ? ${orig}) origs))
  cfg.skillNamespaces);
  members = listToAttrs (map (m: nameValuePair m.flat m) (integrationMembers ++ collectionMembers));
  plainSkills =
    removeAttrs cfg.skills (map (m: m.orig) collectionMembers)
    // mergeAttrsList (map (integration:
      optionalAttrs (cfg.integrations.${integration}.skillNamespace == "") skillIntegrations.${integration}.skills)
    enabledIntegrations);
  memberClashes = filter (key: plainSkills ? ${key}) (attrNames members);

  # Only hyphenated bare names are rewritten: Superset's `setup`, `page` and
  # `browser` are ordinary words in other skills' prose.
  distinctive = hasInfix "-";
  mkView = {
    refOf,
    dirOf,
    nameOf,
  }: let
    ms = attrValues members;
  in
    renameSkills.rename cfg.skillRenames (renameSkills.rewrite {
        refs = listToAttrs (concatMap (m:
          optional (m.flat != m.orig) (nameValuePair m.flat (refOf m))
          ++ optional (m.plugin != refOf m) (nameValuePair m.plugin (refOf m))
          ++ optional (distinctive m.orig && m.orig != refOf m) (nameValuePair m.orig (refOf m)))
        ms);
        dirs = listToAttrs (map (m: nameValuePair m.orig (dirOf m)) (filter (m: m.orig != dirOf m) ms));
        names = mapAttrs (_: nameOf) members;
      }
      (plainSkills // mapAttrs (_: m: m.content) members));

  flatSkills = mkView {
    refOf = m: m.flat;
    dirOf = m: m.flat;
    nameOf = m: m.flat;
  };
  claudeSkills = mkView {
    refOf = m: m.plugin;
    dirOf = m: m.short;
    nameOf = m: m.short;
  };

  effectiveSkills =
    if isAttrs cfg.skills
    then
      assert assertMsg (memberClashes == []) ''
        modules.programs.ai: namespaced skills clash with plain skills of the same name: ${concatStringsSep ", " memberClashes}
      ''; flatSkills
    else cfg.skills;

  # Loaded through CLAUDE_CODE_PLUGIN_DIRS rather than linked under
  # `skills/`: opencode scans ~/.claude/skills recursively and would list
  # every short name (`doctor`, `page`) as a skill of its own.
  claudePlugins = mapAttrs (ns: ms:
    pkgs.runCommandLocal "claude-plugin-${ns}" {} (''
        install -Dm644 ${pkgs.writeText "plugin.json" (builtins.toJSON {name = ns;})} $out/.claude-plugin/plugin.json
        mkdir -p $out/skills
      ''
      + concatMapStrings (m: ''
        cp -rL ${skillDir m.short (claudeSkills.${m.flat} or m.content)} $out/skills/${m.short}
      '')
      ms))
  (groupBy (m: m.ns) (attrValues members));

  mkDefaultAttrs = attrs: mapAttrs (_: mkDefault) attrs;
  # opencode also reads claude-code's skills directory.
  claudeCodeSkills =
    if isAttrs cfg.skills
    then mapAttrs skillDir (removeAttrs claudeSkills (attrNames members))
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
  imports = map (integration:
    mkRenamedOptionModule
    ["modules" namespace name integration]
    ["modules" namespace name "integrations" integration])
  (attrNames allIntegrations);

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

    skillRenames = mkOption {
      type = types.attrsOf types.str;
      default = {};
      example = {code-review = "review-code";};
      description = mdDoc ''
        Old skill name → new name. References to the old name in every skill
        (`` `old` ``, `"old"`, a word-initial `/old`) are rewritten, and a skill
        installed under the old name is re-keyed. Use it when a local skill
        replaces an upstream one under a different name.
      '';
    };

    skillNamespaces = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = {};
      example = {stitch = ["code-to-design" "stitch-loop"];};
      description = mdDoc ''
        Namespace → names of skills in `skills` that belong to it. Claude Code
        gets each namespace as a plugin, so `stitch-loop` is `/stitch:loop`;
        every other target gets flat `stitch-loop`, `stitch-code-to-design`.
        `ns:x`, hyphenated old names and `../old/` links are rewritten to match.
      '';
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

    integrations = mapAttrs (integration: module:
      module.options.${integration}
      // optionalAttrs (module.options.${integration} ? package) {
        installPackage = mkOption {
          type = types.bool;
          default = true;
          description = mdDoc ''
            Put `package` on `PATH`. Off, the integration still runs it by store
            path (MCP server, service, wrappers); only the CLI is not installed.
          '';
        };
      }
      // optionalAttrs (module ? skills) {
        skillNamespace = mkOption {
          type = types.str;
          default =
            if length (attrNames module.skills) > 1
            then integration
            else "";
          defaultText = literalExpression ''"${integration}" if it ships more than one skill, else ""'';
          description = mdDoc ''
            Namespace for this integration's skills, as `modules.programs.ai.skillNamespaces`
            does for a collection. `""` installs them under their upstream names.
          '';
        };
      })
    allIntegrations;
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
        ++ openwikiIntegration.warnings
        ++ orcaIntegration.warnings
        ++ browserHarnessIntegration.warnings
        ++ jevIntegration.warnings
        ++ supersetIntegration.warnings;
    }
    # With the gateway on, clients see only the gateway; the real servers
    # become its backends.
    (optionalAttrs hasMcpOption {
      programs.mcp = mkIf (effectiveMcps != {}) {
        enable = mkDefault true;
        servers = mkDefaultAttrs (
          if cfg.integrations.gateway.enable
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
        settings =
          optionalAttrs (effectiveHooks != {}) {hooks = effectiveHooks;}
          // optionalAttrs (claudePlugins != {}) {
            env.CLAUDE_CODE_PLUGIN_DIRS = concatStringsSep ":" (map toString (attrValues claudePlugins));
          };
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
    mempalaceIntegration.config
    coderabbitIntegration.config
    supersetIntegration.config
    openwikiIntegration.config
    orcaIntegration.config
    browserHarnessIntegration.config
    jevIntegration.config
    mcpGatewayIntegration.config
  ]);
}
