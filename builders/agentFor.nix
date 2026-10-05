# Agents are authored in opencode's frontmatter. Claude Code skips a file with
# no `name` without a word, and Copilot reads `tools` as an allowlist of aliases.
{
  lib,
  pkgs,
}: let
  # opencode tool → what to deny in Claude Code / drop from Copilot's allowlist.
  claudeTools = {
    write = ["Write"];
    edit = ["Edit" "Write"];
    patch = ["Edit"];
    bash = ["Bash"];
    webfetch = ["WebFetch"];
    websearch = ["WebSearch"];
    read = ["Read"];
    grep = ["Grep"];
    glob = ["Glob"];
    todowrite = ["TodoWrite"];
  };
  copilotTools = {
    write = ["edit"];
    edit = ["edit"];
    patch = ["edit"];
    bash = ["execute"];
    webfetch = ["web"];
    websearch = ["web"];
    read = ["read"];
    grep = ["search"];
    glob = ["search"];
    todowrite = ["todo"];
  };
  copilotAll = ["execute" "read" "edit" "search" "agent" "web" "todo"];

  # Denied = `tools.<t>: false` or `permission.<t>: deny`; the opencode-only keys go.
  denied = ''
    [(.tools // {} | to_entries | .[] | select(.value == false) | .key),
     (.permission // {} | to_entries | .[] | select(.value == "deny") | .key)]
    | map($map[.] // []) | flatten | unique
  '';
  strip = "del(.mode, .temperature, .permission, .tools, .model)";

  exprs = {
    claude-code = ''
      (${denied}) as $deny
      | ${strip}
      | {"name": strenv(NAME)} * .
      | with(select($deny | length > 0); .disallowedTools = ($deny | join(", ")))
    '';
    github-copilot-cli = ''
      (${denied}) as $deny
      | ${strip}
      | {"name": strenv(NAME)} * .
      | with(select($deny | length > 0); .tools = ($all - $deny) | .tools style="flow")
    '';
  };

  maps = {
    claude-code = claudeTools;
    github-copilot-cli = copilotTools;
  };
in
  target: name: content: let
    src =
      if lib.hm.strings.isPathLike content
      then content
      else pkgs.writeText "${name}.md" content;
  in
    pkgs.runCommandLocal "agent-${target}-${name}.md" {
      nativeBuildInputs = [pkgs.yq-go];
      NAME = name;
      MAP = builtins.toJSON maps.${target};
      ALL = builtins.toJSON copilotAll;
      EXPR = exprs.${target};
    } ''
      yq --front-matter=process \
        "(strenv(MAP) | from_json) as \$map | (strenv(ALL) | from_json) as \$all | $EXPR" \
        ${src} > $out
    ''
