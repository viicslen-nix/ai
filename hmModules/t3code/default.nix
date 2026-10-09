{
  lib,
  pkgs,
  config,
  options,
  aiInputs,
  ...
} @ args:
with lib; let
  name = "t3code";
  namespace = "programs";

  cfg = config.modules.${namespace}.${name};

  osConfig = args.osConfig or {};
  graphical = attrByPath ["services" "graphical-desktop" "enable"] false osConfig;
  inherit (pkgs.stdenv.hostPlatform) system;

  # A package built to sit beside another t3code advertises its renamed files in passthru.
  cliProgram = pkg: pkg.cliProgram or "t3";
  iconName = pkg: pkg.iconName or "t3code";

  # Both fixes must land on the unwrapped derivation, not on the outer wrapper.
  withConnect = icfg: base:
    base.override {
      t3code-unwrapped = base.unwrapped.overrideAttrs (old: {
        postPatch =
          (old.postPatch or "")
          + ''
            cp .env.example .env

            # niri-flake labels git builds `unstable <date>`, which this gate cannot read.
            if [ -f apps/desktop/src/snapShot/NiriSnapShot.ts ]; then
              substituteInPlace apps/desktop/src/snapShot/NiriSnapShot.ts \
                --replace-fail '/^(?:niri )?(\d+)\.(\d+)/' '/^(?:niri )?(?:unstable )?(\d+)[.-](\d+)/'
            fi
          '';

        postInstall =
          (old.postInstall or "")
          + ''
            for program in "$out/bin/t3" "$desktop/bin/t3code-desktop"; do
              wrapProgram "$program" \
                --set-default T3CODE_CLOUDFLARED_PATH "${getExe cfg.cloudflaredPackage}"${
              optionalString (icfg.stateDir != null) " --set-default T3CODE_HOME ${escapeShellArg icfg.stateDir}"
            }
            done
          '';
      });
    };

  instanceOptions = {
    icfg,
    enable,
    package,
    packageText,
    stateDir,
    stateDirText,
    port,
  }: {
    inherit enable;

    package = mkOption {
      type = types.package;
      default = package;
      defaultText = literalExpression packageText;
      description = mdDoc ''
        Stock t3code package providing the CLI and the desktop app.
        It is rebuilt with the T3 Connect public config and a pinned
        cloudflared before being installed.
      '';
    };

    # Never install a stock `t3code-desktop` alongside this; the app must come from here.
    finalPackage = mkOption {
      type = types.package;
      readOnly = true;
      default = withConnect icfg icfg.package;
      defaultText = literalExpression "package rebuilt with the T3 Connect public config and a pinned cloudflared";
      description = mdDoc "The package actually installed, after the fixes above.";
    };

    stateDir = mkOption {
      type = types.nullOr types.str;
      default = stateDir;
      defaultText = literalExpression stateDirText;
      description = mdDoc ''
        `T3CODE_HOME`: projects, threads, worktrees and the T3 Connect
        login. `null` keeps upstream's `~/.t3`.
      '';
    };

    # Off when the `serve` unit is the server: the app cannot attach to it and spawns a second backend on the same database.
    desktopApp = mkOption {
      type = types.bool;
      default = graphical && !icfg.serve.enable;
      defaultText = literalExpression "osConfig.services.graphical-desktop.enable && !serve.enable";
      description = mdDoc "Install the Electron desktop app. Use the `webapps` entry against the served port instead when `serve` is on.";
    };

    serve = {
      enable = mkEnableOption (mdDoc "the T3 Code server as a systemd user service") // {default = true;};

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = mdDoc ''
          Interface to bind. Leave on loopback when reaching the machine
          through T3 Connect — the relay client dials out from here.
        '';
      };

      port = mkOption {
        type = types.port;
        default = port;
        description = mdDoc "Port for the HTTP/WebSocket server.";
      };

      workingDirectory = mkOption {
        type = types.str;
        default = config.home.homeDirectory;
        description = mdDoc "Working directory for provider sessions.";
      };

      tailscaleServe = mkEnableOption (mdDoc "exposing the server over HTTPS on the Tailnet");
    };
  };

  instances = [
    {
      unit = name;
      description = "T3 Code server";
      icfg = cfg;
    }
    {
      unit = "${name}-nightly";
      description = "T3 Code nightly server";
      icfg = cfg.nightly;
    }
  ];

  enabled = filter (i: i.icfg.enable) instances;

  relativeStateDir = icfg: let
    home = "${config.home.homeDirectory}/";
  in
    if icfg.stateDir == null
    then ".t3"
    else if hasPrefix home icfg.stateDir
    then removePrefix home icfg.stateDir
    else null;
in {
  options.modules.${namespace}.${name} =
    instanceOptions {
      icfg = cfg;
      enable = mkEnableOption (mdDoc "T3 Code");
      package = aiInputs.llm-agents.packages.${system}.t3code;
      packageText = "aiInputs.llm-agents.packages.\${system}.t3code";
      stateDir = null;
      stateDirText = "null";
      port = 3773;
    }
    // {
      # Installs beside the stable one: renamed commands, launcher and icons, its own state.
      nightly = instanceOptions {
        icfg = cfg.nightly;
        enable = mkEnableOption (mdDoc "T3 Code nightly, alongside the stable build");
        package = aiInputs.packages.packages.${system}.t3code.nightly;
        packageText = "aiInputs.packages.packages.\${system}.t3code.nightly";
        stateDir = "${config.xdg.dataHome}/t3code-nightly";
        stateDirText = ''"''${config.xdg.dataHome}/t3code-nightly"'';
        port = 3783;
      };

      cloudflaredPackage = mkOption {
        type = types.package;
        default = pkgs.cloudflared;
        defaultText = literalExpression "pkgs.cloudflared";
        description = mdDoc ''
          Relay client T3 Connect tunnels through. Pinning it here keeps
          `t3 connect link` from fetching its own copy at runtime.
        '';
      };

      # The D-Bus name is shared, so a nightly bind would capture whichever app started first.
      snapShotShortcut = mkOption {
        type = types.nullOr types.str;
        default = "Ctrl+Shift+2";
        description = mdDoc ''
          niri key combination that triggers a T3 Code SnapShot. Declared
          here because T3 Code cannot write the Nix-generated niri config.
          Only applied when niri is enabled; `null` binds nothing.
        '';
      };
    };

  config = mkMerge [
    {
      # `out` is the CLI; the Electron app is the `desktop` output, and it
      # is only useful on a graphical host.
      home.packages = concatMap ({icfg, ...}:
        [icfg.finalPackage]
        ++ optional icfg.desktopApp icfg.finalPackage.desktop)
      enabled;
    }

    # Headless hosts have no `programs.niri` option at all, so even a false mkIf would fail.
    (optionalAttrs (options.programs ? niri) {
      programs.niri.settings.binds = mkIf (cfg.enable && attrByPath ["programs" "niri" "enable"] false osConfig && cfg.desktopApp && cfg.snapShotShortcut != null) {
        ${cfg.snapShotShortcut} = {
          repeat = false;
          action.spawn = [
            (getExe' pkgs.glib "gdbus")
            "call"
            "--session"
            "--dest"
            "com.t3tools.T3Code.SnapShot"
            "--object-path"
            "/com/t3tools/SnapShot"
            "--method"
            "com.t3tools.SnapShot.Capture"
          ];
        };
      };
    })

    {
      # Don't swap this for `t3 service install`: its unit runs a self-updating launcher.
      systemd.user.services = listToAttrs (map ({
        unit,
        description,
        icfg,
      }:
        nameValuePair unit {
          Unit = {
            Description = description;
            After = ["network-online.target"];
            Wants = ["network-online.target"];
          };

          Service = {
            Type = "simple";
            WorkingDirectory = icfg.serve.workingDirectory;
            ExecStart = concatStringsSep " " ([
                (getExe' icfg.finalPackage (cliProgram icfg.finalPackage))
                "serve"
                "--no-browser"
                "--host"
                icfg.serve.host
                "--port"
                (toString icfg.serve.port)
              ]
              ++ optional icfg.serve.tailscaleServe "--tailscale-serve");
            KillMode = "mixed";
            Restart = "always";
            RestartSec = 5;
          };

          Install.WantedBy = ["default.target"];
        }) (filter (i: i.icfg.serve.enable) enabled));
    }

    # `t3 connect login`/`link` persist their authorization here, alongside
    # the project database — losing it means re-authorizing every boot.
    # Impermanence is the consumer's module; an undeclared option fails even under mkIf.
    (optionalAttrs (hasAttrByPath ["modules" "functionality" "impermanence"] options) {
      modules.functionality.impermanence = let
        imp = config.modules.functionality.impermanence;
      in
        mkIf (imp.enable && imp.autoPersistence) {
          directories = filter (d: d != null) (map (i: relativeStateDir i.icfg) enabled);
        };
    })

    # Test `options`, not `config`: gating the attr name on config.…webapps.enable recurses.
    (optionalAttrs (options.modules.programs ? webapps) {
      modules.programs.webapps.apps = mkIf config.modules.programs.webapps.enable (map ({
        unit,
        icfg,
        ...
      }: {
        name = unit;
        url = "http://127.0.0.1:${toString icfg.serve.port}";
        floating = false;
        icon = "${icfg.finalPackage.desktop}/share/icons/hicolor/scalable/apps/${iconName icfg.finalPackage}.svg";
      }) (filter (i: i.icfg.serve.enable) enabled));
    })
  ];
}
