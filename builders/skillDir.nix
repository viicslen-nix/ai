# opencode v2 watches the parent of each resolved SKILL.md recursively, so a
# bare store file makes it watch all of /nix/store (~1M inotify watches, ENOSPC).
{
  lib,
  pkgs,
}: name: content: let
  # A `"${pkg}/…/SKILL.md"` string; telling it from a directory otherwise needs IFD.
  isStoreFile =
    lib.isString content
    && lib.hasPrefix builtins.storeDir content
    && !(lib.hasInfix "\n" content)
    && lib.hasSuffix ".md" content;
in
  if lib.isPath content && !lib.pathIsDirectory content
  then pkgs.writeTextDir "SKILL.md" (builtins.readFile content)
  else if isStoreFile
  then
    pkgs.runCommand "skill-${name}" {} ''
      install -Dm644 ${content} $out/SKILL.md
    ''
  else if lib.hm.strings.isPathLike content
  then content
  else pkgs.writeTextDir "SKILL.md" content
