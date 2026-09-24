{
  description = "AI harness configuration — shared config and per-harness modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    packages = {
      url = "github:viicslen-nix/packages";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The harness packages (claude-code, codex, copilot-cli, opencode2, …).
    # Leave `nixpkgs` un-overridden — it is what keeps cache.numtide.com hitting.
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
    };

    # opencode v1, which ships its own package and overlay.
    opencode = {
      url = "github:anomalyco/opencode";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Skill helpers: mkSkillAttrSet, selectFromInput, patchSkill.
    viicslen-lib = {
      url = "github:viicslen-nix/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mattpocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
    };

    flake-parts.url = "github:hercules-ci/flake-parts";

    # home-manager is reached through omniflake's index rather than carrying an
    # input of its own; see the `inputs` binding in `outputs` below. Consumers
    # should point this at their own omniflake so only one copy is locked.
    omniflake = {
      url = "github:fzakaria/omniflake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = rawInputs @ {flake-parts, ...}: let
    # home-manager under its old name, so every `inputs.home-manager` below —
    # the two packages and `_module.args.inputs` — is unchanged.
    inputs = rawInputs // {home-manager = rawInputs.omniflake.flakes.home-manager;};

    # `aiInputs`, not `inputs`: home-manager's `extraSpecialArgs` wins over
    # `_module.args`, so a consumer passing its own `inputs` would silently
    # shadow ours. It lives in a keyed module of its own because the option is
    # unique — defining it in each wrapper is four conflicting definitions.
    argsModule = {
      key = "viicslen-ai:args";
      _module.args.aiInputs = inputs;
    };

    # The `key` is not decoration either: two presets import the same module,
    # and the module system dedupes only by key.
    mkHmModule = name: path: {
      key = "viicslen-ai:${name}";
      imports = [argsModule path];
    };
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      perSystem = {
        lib,
        config,
        system,
        ...
      }: let
        pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [inputs.opencode.overlays.default];
        };
        mkHarness = import ./builders/mkHarness.nix {inherit pkgs inputs;};

        llm = inputs.llm-agents.packages.${system};
      in {
        formatter = pkgs.alejandra;

        packages = {
          default = pkgs.callPackage ./packages/opencode.nix {inherit inputs;};
          opencode = pkgs.callPackage ./packages/opencode.nix {inherit inputs;};
          oh-my-opencode = pkgs.callPackage ./packages/oh-my-opencode.nix {inherit inputs;};

          claude = mkHarness {
            name = "claude";
            modules = [./hmModules/claude-code];
            enable = {
              programs.claude-code.enable = true;
              modules.programs.aiProfile.enable = true;
            };
            package = llm.claude-code;
            configDirVar = "CLAUDE_CONFIG_DIR";
          };

          opencode2 = mkHarness {
            name = "opencode2";
            modules = [./hmModules/opencode/v2.nix];
            enable = {
              modules.programs.opencode2.enable = true;
              modules.programs.aiProfile.enable = true;
            };
            package = llm.opencode2;
            configDirVar = "OPENCODE_CONFIG_DIR";
          };

          codex = mkHarness {
            name = "codex";
            enable = {
              programs.codex.enable = true;
              modules.programs.aiProfile.enable = true;
            };
            package = llm.codex;
            configDirVar = "CODEX_HOME";
          };

          copilot = mkHarness {
            name = "copilot";
            enable = {
              programs.github-copilot-cli.enable = true;
              modules.programs.aiProfile.enable = true;
            };
            package = llm.copilot-cli;
            mainProgram = "copilot";
            configDirVar = "COPILOT_HOME";
          };

          # No config-dir variable exists: `agy` reads ~/.gemini wherever it
          # runs, so that is what gets synced — this one harness is not
          # self-contained on a borrowed machine.
          antigravity = mkHarness {
            name = "antigravity";
            enable = {
              programs.antigravity-cli.enable = true;
              modules.programs.aiProfile.enable = true;
            };
            package = llm.antigravity-cli;
            mainProgram = "agy";
            configDirVar = null;
            relDir = ".gemini";
          };
        };

        apps = {
          default = {
            type = "app";
            program = lib.getExe config.packages.default;
          };
          oh-my-opencode = {
            type = "app";
            program = lib.getExe config.packages.oh-my-opencode;
          };
        };
      };

      flake = {
        homeManagerModules = {
          # Everything, for a consumer that wants the lot.
          default.imports = [
            (mkHmModule "ai" ./hmModules/ai)
            (mkHmModule "profile" ./hmModules/profile.nix)
            (mkHmModule "claude-code" ./hmModules/claude-code)
            (mkHmModule "opencode" ./hmModules/opencode/v1.nix)
            (mkHmModule "opencode2" ./hmModules/opencode/v2.nix)
          ];

          ai = mkHmModule "ai" ./hmModules/ai;
          claude-code = mkHmModule "claude-code" ./hmModules/claude-code;
          opencode = mkHmModule "opencode" ./hmModules/opencode/v1.nix;
          opencode2 = mkHmModule "opencode2" ./hmModules/opencode/v2.nix;
          opencode-service = mkHmModule "opencode-service" ./hmModules/opencode/service.nix;
          profile = mkHmModule "profile" ./hmModules/profile.nix;
        };

        nixosModules = {
          opencode-web = {
            key = "viicslen-ai:opencode-web";
            imports = [./nixosModules/opencode-web.nix];
            # Same shadowing hazard as the home-manager side: the consumer's
            # `specialArgs.inputs` is not ours.
            _module.args.aiInputs = inputs;
            nixpkgs.overlays = [inputs.opencode.overlays.default];
          };
        };
      };
    };
}
