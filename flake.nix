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

      # No `apps`: every package is a `writeShellScriptBin`, so it carries
      # `meta.mainProgram` and `nix run .#<name>` resolves straight to it.
      perSystem = {
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

        # Everything `just` reaches for. `gh skill` is a preview command, so a
        # gh old enough to lack it makes every recipe here fail.
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            gh
            git
            just
            alejandra
            util-linux # column, for `just skills`
          ];

          shellHook = ''
            echo "ai — just vendor-skills <owner/repo> [skill|--all] | update-skills | skills"
          '';
        };

        packages = {
          default = config.packages.opencode;

          opencode = mkHarness {
            name = "opencode";
            modules = [./hmModules/opencode/v2.nix];
            enable = {
              modules.programs.opencode.enable = true;
              modules.programs.aiProfile.enable = true;
            };
            package = llm.opencode2;
            mainProgram = "opencode2";
            target = "opencode";
            configDirVar = "OPENCODE_CONFIG_DIR";
          };

          # v1, kept reachable while it is retired. `op1` is the short alias.
          opencode1 = mkHarness {
            name = "opencode1";
            modules = [./hmModules/opencode/v1.nix];
            enable = {
              modules.programs.opencode1.enable = true;
              modules.programs.aiProfile.enable = true;
            };
            package = inputs.opencode.packages.${system}.default;
            mainProgram = "opencode";
            aliases = ["op1"];
            target = "opencode1";
            configDirVar = "OPENCODE_CONFIG_DIR";
          };

          oh-my-opencode = mkHarness {
            name = "oh-my-opencode";
            modules = [
              ./hmModules/opencode/v1.nix
              ./hmModules/opencode/oh-my.nix
            ];
            enable = {
              modules.programs.opencode1.enable = true;
              modules.programs.aiProfile.enable = true;
            };
            package = inputs.opencode.packages.${system}.default;
            mainProgram = "opencode";
            target = "opencode1";
            configDirVar = "OPENCODE_CONFIG_DIR";
            # The v1 module writes `opencode1/`; this variant keeps its own directory.
            relDir = ".config/opencode1";
            destDir = ".config/oh-my-opencode";
          };

          claude = mkHarness {
            name = "claude";
            modules = [./hmModules/claude-code];
            enable = {
              programs.claude-code.enable = true;
              modules.programs.aiProfile.enable = true;
            };
            target = "claude-code";
            package = llm.claude-code;
            configDirVar = "CLAUDE_CONFIG_DIR";
          };

          # The old name for what `opencode` now is.
          opencode2 = config.packages.opencode;

          codex = mkHarness {
            name = "codex";
            enable = {
              programs.codex.enable = true;
              modules.programs.aiProfile.enable = true;
            };
            target = "codex";
            package = llm.codex;
            configDirVar = "CODEX_HOME";
          };

          copilot = mkHarness {
            name = "copilot";
            enable = {
              programs.github-copilot-cli.enable = true;
              modules.programs.aiProfile.enable = true;
            };
            target = "github-copilot-cli";
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
            target = "antigravity-cli";
            package = llm.antigravity-cli;
            mainProgram = "agy";
            configDirVar = null;
            relDir = ".gemini";
          };
        };
      };

      flake = {
        homeManagerModules = {
          # Everything, for a consumer that wants the lot — including the
          # opinions, which is the point of asking for all of it. `mkDefault`, so
          # `enable = false` still turns them off.
          default.imports = [
            ({lib, ...}: {
              key = "viicslen-ai:profile-on";
              config.modules.programs.aiProfile.enable = lib.mkDefault true;
            })
            (mkHmModule "ai" ./hmModules/ai)
            (mkHmModule "profile" ./hmModules/profile.nix)
            (mkHmModule "claude-code" ./hmModules/claude-code)
            (mkHmModule "opencode" ./hmModules/opencode/v2.nix)
            (mkHmModule "opencode1" ./hmModules/opencode/v1.nix)
          ];

          ai = mkHmModule "ai" ./hmModules/ai;
          claude-code = mkHmModule "claude-code" ./hmModules/claude-code;
          opencode = mkHmModule "opencode" ./hmModules/opencode/v2.nix;
          opencode1 = mkHmModule "opencode1" ./hmModules/opencode/v1.nix;
          # The old name for what `opencode` now is.
          opencode2 = mkHmModule "opencode" ./hmModules/opencode/v2.nix;
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
