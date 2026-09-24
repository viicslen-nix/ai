{
  lib,
  config,
  aiInputs,
  ...
}:
with lib; let
  cfg = config.modules.programs.aiProfile;

  inherit
    (aiInputs.viicslen-lib.lib.skills)
    mkMarkdownAttrSet
    mkSkillAttrSet
    selectFromInput
    patchSkill
    ;

  mattpocock = aiInputs.mattpocock-skills;

  # Curated by name — the upstream repo also carries in-progress/misc/deprecated.
  upstreamSkills = selectFromInput mattpocock [
    "skills/engineering/codebase-design"
    "skills/engineering/diagnosing-bugs"
    "skills/engineering/domain-modeling"
    "skills/engineering/grill-with-docs"
    "skills/engineering/implement"
    "skills/engineering/improve-codebase-architecture"
    "skills/engineering/prototype"
    "skills/engineering/research"
    "skills/engineering/resolving-merge-conflicts"
    "skills/engineering/tdd"
    "skills/engineering/to-spec"
    "skills/engineering/to-tickets"
    "skills/engineering/triage"
    "skills/engineering/wayfinder"
    "skills/productivity/grill-me"
    "skills/productivity/grilling"
    "skills/productivity/handoff"
    "skills/productivity/wait-what"
    "skills/productivity/writing-for-agents"
  ];

  patchedSkills = {
    grilling =
      patchSkill
      "${mattpocock}/skills/productivity/grilling/SKILL.md"
      (import ../content/skill-patches/grilling.nix);
    implement =
      patchSkill
      "${mattpocock}/skills/engineering/implement/SKILL.md"
      (import ../content/skill-patches/implement.nix);
  };
in {
  options.modules.programs.aiProfile = {
    enable = mkEnableOption (mdDoc "the opinionated AI harness profile — skills, commands, plugins and the credential-free MCP backends");
  };

  config = mkIf cfg.enable {
    modules.programs.claude-code = {
      marketplaces = {
        mempalace = "MemPalace/mempalace";
        ponytail = "DietrichGebert/ponytail";
        worktrunk = "max-sixty/worktrunk";
      };

      plugins = {
        "document-skills@anthropic-agent-skills" = true;
        "example-skills@anthropic-agent-skills" = false;
        "laravel-simplifier@laravel" = true;
        "mempalace@mempalace" = true;
        "phpstorm-plugin@phpstorm-marketplace" = true;
        "ponytail@ponytail" = true;
        "worktrunk@worktrunk" = true;
        "playground@claude-plugins-official" = true;
      };
    };

    modules.programs.ai = {
      enable = true;
      gateway.enable = true;
      superset.enable = true;
      mempalace.enable = true;
      coderabbit.enable = true;
      openwiki.enable = true;
      context = ../content/AGENTS.md;
      # Order matters — last wins, and ./skills shadows both upstream layers.
      skills = upstreamSkills // patchedSkills // mkSkillAttrSet ../content/skills;
      commands = mkMarkdownAttrSet ../content/commands;

      # Credential-free backends only. Anything needing a secret is the
      # consumer's to add, so this flake stays runnable anywhere.
      mcps = {
        context7 = {
          url = "https://mcp.context7.com/mcp";
          oauth.enabled = true;
        };
        gh_grep = {
          url = "https://mcp.grep.app";
          protocol_version = "2025-06-18";
        };
        linear = {
          url = "https://mcp.linear.app/mcp";
          oauth.enabled = true;
        };
        playwright = {
          command = "npx";
          args = [
            "-y"
            "@playwright/mcp@latest"
            "--ignore-https-errors"
            "--browser"
            "chromium"
          ];
        };
      };
    };
  };
}
