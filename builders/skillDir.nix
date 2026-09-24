# opencode v2 watches the parent of each resolved SKILL.md recursively, so a
# bare store file makes it watch all of /nix/store (~1M inotify watches, ENOSPC).
{lib, pkgs}: name: content:
if lib.isPath content && !lib.pathIsDirectory content
then pkgs.writeTextDir "SKILL.md" (builtins.readFile content)
else if lib.hm.strings.isPathLike content
then content
else pkgs.writeTextDir "SKILL.md" content
