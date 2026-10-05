# Rewrites a skill set's SKILL.md bodies. A reference is `x`, "x" or a
# word-initial /x; a relative link is ../x/. Only real paths and text are read:
# a store-path string would need IFD, so it passes through untouched.
{
  lib,
  pkgs,
}: let
  inherit (lib) attrNames concatMap concatStringsSep elemAt filter findFirst head imap0 isPath isString length mapAttrs mapAttrs' nameValuePair pathIsDirectory range replaceStrings splitString;

  refForms = name: ["`${name}`" ''"${name}"'' "`/${name}" " /${name}" "\n/${name}"];

  # Replaces the frontmatter `name:` line, whatever it held (`stitch::x` included).
  setName = name: body: let
    lines = splitString "\n" body;
    n = length lines;
    close =
      if n > 1 && head lines == "---"
      then findFirst (i: elemAt lines i == "---") null (range 1 (n - 1))
      else null;
  in
    if close == null
    then body
    else
      concatStringsSep "\n" (imap0 (i: line:
        if i > 0 && i < close && builtins.match "name:.*" line != null
        then "name: ${name}"
        else line)
      lines);

  # refs: old -> new reference text. dirs: old -> new directory, for ../old/ links.
  # names: skill key -> frontmatter name to set.
  rewrite = {
    refs ? {},
    dirs ? {},
    names ? {},
  }: skills: let
    olds = attrNames refs;
    oldDirs = attrNames dirs;
    replace =
      replaceStrings
      (concatMap refForms olds ++ map (d: "../${d}/") oldDirs)
      (concatMap (old: refForms refs.${old}) olds ++ map (d: "../${dirs.${d}}/") oldDirs);
    body = key: text:
      replace (
        if names ? ${key}
        then setName names.${key} text
        else text
      );

    one = key: content:
      if isPath content && pathIsDirectory content
      then let
        old = builtins.readFile (content + "/SKILL.md");
        new = body key old;
      in
        if new == old
        then content
        else
          pkgs.runCommandLocal "skill-${key}" {} ''
            cp -r ${content} $out
            chmod -R u+w $out
            cp ${pkgs.writeText "SKILL.md" new} $out/SKILL.md
          ''
      else if isPath content
      then let
        old = builtins.readFile content;
        new = body key old;
      in
        if new == old
        then content
        else new
      else if isString content && !(lib.hm.strings.isPathLike content)
      then body key content
      else content;
  in
    if refs == {} && dirs == {} && names == {}
    then skills
    else mapAttrs one skills;

  # Re-keys old -> new and rewrites every reference to the old name.
  rename = renames: skills: let
    olds = attrNames renames;
    clashes = filter (old: skills ? ${old} && skills ? ${renames.${old}}) olds;
    rekeyed = mapAttrs' (key: nameValuePair (renames.${key} or key)) skills;
  in
    assert lib.assertMsg (clashes == []) ''
      Skill rename clash — both the old and the new name are installed for
      ${concatStringsSep ", " (map (old: "${old} -> ${renames.${old}}") clashes)}
    '';
      rewrite {
        refs = renames;
        dirs = renames;
        names = lib.listToAttrs (map (old: nameValuePair renames.${old} renames.${old}) (filter (old: skills ? ${old}) olds));
      }
      rekeyed;
in {
  inherit rewrite rename;
}
