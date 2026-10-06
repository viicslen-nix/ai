# Needs lukasl-dev/pi.nix's home-manager module beside it (flake.nix pairs
# them): that module owns the package, settings.json and mcp.json, which its
# wrapper merges into the agent dir at launch. Context, skills and commands go
# in as real files rather than its wrapper flags, so pi finds them however it
# is started and mkHarness can sync them.
{
  lib,
  pkgs,
  config,
  ...
}:
with lib; let
  cfg = config.modules.programs.pi;
  pi = config.programs.pi.coding-agent;

  skillDir = import ../../builders/skillDir.nix {inherit lib pkgs;};

  # Sourced by pi.nix's wrapper, so the default is expanded at launch: a value
  # baked in at eval time would point `nix run .#pi` at the throwaway user.
  envFile = pkgs.writeText "pi-env" ''
    PI_CODING_AGENT_DIR="''${PI_CODING_AGENT_DIR:-''${XDG_CONFIG_HOME:-$HOME/.config}/pi}"
    PI_SKIP_VERSION_CHECK="''${PI_SKIP_VERSION_CHECK:-1}"
  '';

  keepsAgentDir =
    pi.environment
    == envFile
    || (isAttrs pi.environment && !isDerivation pi.environment && pi.environment.PI_CODING_AGENT_DIR != null);

  mkEntry = content:
    if hm.strings.isPathLike content
    then {source = content;}
    else {text = content;};

  toPiShape = s:
    optionalAttrs (s.enabled != null) {inherit (s) enabled;}
    // optionalAttrs (cfg.mcpExposure != null) {exposure = cfg.mcpExposure;}
    // getAttrs (filter (n: s ? ${n}) ["timeout" "description" "exposure" "toolExposure"]) s
    // (
      if s.url != null
      then {
        inherit (s) url;
        headers = s.headers or {};
        # `enabled` is opencode's switch; pi signs in whenever a server asks.
        oauth = removeAttrs (s.oauth or {}) ["enabled"];
      }
      else
        {
          inherit (s) command;
          args = s.args or [];
          env = s.env or {};
        }
        // optionalAttrs (s ? cwd) {inherit (s) cwd;}
    );

  mcpServers =
    if cfg.enableMcpIntegration && config.programs.mcp.enable
    then
      mapAttrs (_: server:
        hm.mcp.transformMcpServer {
          inherit server;
          extraTransforms = [toPiShape];
          mkFileRef = path: "!cat ${escapeShellArg path}";
        })
      config.programs.mcp.servers
    else {};
in {
  options.modules.programs.pi = {
    enableMcpIntegration = mkEnableOption (mdDoc "forwarding `programs.mcp.servers` into pi's {file}`mcp.json`");

    mcpExposure = mkOption {
      type = types.nullOr (types.enum ["codemode" "deferred" "direct" "hidden"]);
      default = null;
      description = mdDoc ''
        `exposure` for every forwarded MCP server that does not set its own.
        `null` keeps pi's default, `codemode`.
      '';
    };

    context = mkOption {
      type = types.either types.lines types.path;
      default = "";
      description = mdDoc "Global instructions, written to {file}`pi/AGENTS.md` in the agent dir.";
    };

    commands = mkOption {
      type = types.attrsOf (types.either types.lines types.path);
      default = {};
      description = mdDoc "Prompt templates, written to {file}`pi/prompts/<name>.md` and run as `/<name>`.";
    };

    skills = mkOption {
      type = types.either (types.attrsOf (types.oneOf [types.lines types.path types.str])) types.path;
      default = {};
      description = mdDoc ''
        Skills. A directory is linked to {file}`pi/skills/<name>/`; anything
        else is written as {file}`pi/skills/<name>/SKILL.md`. A single path is
        linked as the whole {file}`pi/skills` directory.
      '';
    };
  };

  config = mkMerge [
    # pi.nix's module takes `osConfig`, which only home-manager's NixOS module
    # provides; a special arg, when present, wins over this.
    {_module.args.osConfig = mkDefault {};}

    (mkIf pi.enable {
      warnings = optional (!keepsAgentDir) ''
        `programs.pi.coding-agent.environment` replaces the one setting PI_CODING_AGENT_DIR,
        so pi falls back to ~/.pi/agent while its context, skills and prompts are in
        ${config.xdg.configHome}/pi. Set `PI_CODING_AGENT_DIR` in it too.
      '';

      programs.pi.coding-agent = {
        environment = mkDefault envFile;
        # ~/.agents/skills holds runtime installers' stale copies of skills we ship.
        settings.skills = ["!${config.home.homeDirectory}/.agents/skills/**"];
        mcp.mcpServers = mkIf (mcpServers != {}) mcpServers;
      };

      home.activation.piStaleSkillLinks =
        import ../../builders/staleSkillLinks.nix {inherit lib;} "${config.xdg.configHome}/pi/skills";

      # Per file, never the directory: pi writes auth.json, sessions and its
      # own settings in here.
      xdg.configFile =
        {
          "pi/AGENTS.md" =
            if isPath cfg.context
            then {source = cfg.context;}
            else mkIf (cfg.context != "") {text = cfg.context;};

          "pi/skills" = mkIf (!isAttrs cfg.skills) {
            source = cfg.skills;
            recursive = true;
          };
        }
        // mapAttrs' (name: content: nameValuePair "pi/prompts/${name}.md" (mkEntry content)) cfg.commands
        // optionalAttrs (isAttrs cfg.skills) (mapAttrs' (name: content:
          nameValuePair "pi/skills/${name}" {
            source = skillDir name content;
            recursive = true;
          })
        cfg.skills);
    })
  ];
}
