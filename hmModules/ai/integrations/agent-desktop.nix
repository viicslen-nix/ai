{
  lib,
  cfg,
  pkgs,
  osConfig,
  isAttrs,
}:
with lib; let
  ad = cfg.integrations.agent-desktop;

  cli = pkgs.writeShellApplication {
    name = "agent-desktop";
    runtimeInputs = with pkgs; [sway dbus wayvnc vncdotool grim wtype jq tigervnc iproute2 util-linux coreutils gnused gnugrep systemd];
    text = builtins.readFile ./agent-desktop.sh;
  };

  skill = ''
    ---
    name: agent-desktop
    description: Run, test, review or screenshot a desktop GUI app (Wayland or X11, GTK, Qt, Electron, Tauri, a native window) in a private headless desktop instead of the user's screen. Use whenever a task needs a GUI window opened, clicked, typed into or looked at. Not for web pages, which go through a headless browser.
    ---

    # agent-desktop

    Never open a GUI window on the user's own session: it steals their focus,
    and they are working on that screen. `agent-desktop` gives you a headless
    desktop (sway, 1920x1080, scale 1) of your own. Nothing in it reaches the
    user's screen, keyboard or mouse; they can watch it read-only with
    `agent-desktop view <name>`.

    ## Workflow

    ```bash
    agent-desktop up mytest                       # pick a name per task
    agent-desktop run mytest -- ./result/bin/app  # detached; prints its log path
    agent-desktop windows mytest                  # wait until the window is listed
    agent-desktop shot mytest                     # prints the PNG path; read it as an image
    agent-desktop click mytest 640 400
    agent-desktop type mytest 'hello'
    agent-desktop key mytest Return ctrl+s
    agent-desktop down mytest                     # always, when done
    ```

    - Coordinates are screenshot pixels, top-left origin. A single window fills
      the output, so its title bar takes the top few pixels.
    - Also `dclick`, `drag <x1> <y1> <x2> <y2>`, `scroll <x> <y> up|down [steps]`,
      and `size <name> 1280x800` to test another resolution.
    - The pointer exists only during a pointer command, so hover effects are gone
      by the time `shot` runs. Use `hover <name> <x> <y>`, which screenshots
      while the pointer is held there.
    - `exec <name> -- <cmd>` runs a command against the desktop in the
      foreground, with `swaymsg`, `grim` and `wtype` on `PATH`: for example
      `exec mytest -- swaymsg '[app_id="foo"] floating enable'`.
    - `run` goes through your shell's environment, so dev-shell tools and the
      working directory carry over. Apps get the desktop's own Wayland socket,
      X display and D-Bus session bus.
    - An app the user already has open can still hand your launch over to their
      copy, through a lock file or socket in its config directory. The sign is
      that `windows` never lists it. Then pass the app's own profile flag
      (`--user-data-dir=…` for Chromium and Electron), or `run <name> --fresh`, which
      gives it empty `XDG_*_HOME` directories that `down` deletes.
    - App output goes to the log path `run` printed. Read it when a window never
      appears.
    - `down` stops the desktop and every app started in it. Desktops do not
      stop on their own when your session ends; `agent-desktop list` shows what
      is still running.
    - If the user asks to see what you are doing, tell them
      `agent-desktop view <name>` (add `--interact` to take control).
  '';
in {
  skills.agent-desktop = skill;

  context = ''
    Never launch a GUI app on the user's desktop session. Test, review and screenshot desktop apps inside `agent-desktop` (see the agent-desktop skill).
  '';

  options = {
    agent-desktop = {
      enable = mkEnableOption (mdDoc "`agent-desktop`, private headless desktops agents test GUI apps in, and its skill");

      viewerEntry.enable =
        mkEnableOption (mdDoc "an \"Agent Desktop\" launcher entry that watches every running agent desktop")
        // {
          default = attrByPath ["services" "graphical-desktop" "enable"] false osConfig;
          defaultText = literalExpression "osConfig.services.graphical-desktop.enable or false";
        };
    };
  };

  config = mkIf ad.enable (mkMerge [
    {
      home.packages = [cli];

      systemd.user.services."agent-desktop@" = {
        Unit.Description = "Headless agent desktop %i";
        Service = {
          ExecStart = "${getExe cli} _session %i";
          ExecStopPost = "${pkgs.coreutils}/bin/rm -rf %t/agent-desktop/%i";
          # The user manager carries the real session's variables; sway would nest into it.
          UnsetEnvironment = ["WAYLAND_DISPLAY" "DISPLAY" "SWAYSOCK" "NIRI_SOCKET" "HYPRLAND_INSTANCE_SIGNATURE"];
          Environment = ["WLR_BACKENDS=headless" "WLR_LIBINPUT_NO_DEVICES=1" "XDG_CURRENT_DESKTOP=sway" "XDG_SESSION_TYPE=wayland"];
        };
      };
    }

    (mkIf ad.viewerEntry.enable {
      xdg.desktopEntries.agent-desktop = {
        name = "Agent Desktop";
        genericName = "Watch agent desktops";
        comment = "Watch every running agent desktop in a view-only VNC viewer";
        exec = "agent-desktop view";
        icon = "preferences-desktop-remote-desktop";
        terminal = false;
        categories = ["Development"];
      };
    })
  ]);

  warnings =
    optional (ad.enable && !(isAttrs cfg.skills))
    "`modules.programs.ai.integrations.agent-desktop.enable` adds the agent-desktop skill only when `modules.programs.ai.skills` is an attribute set.";
}
