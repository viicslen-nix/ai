# Skill vendoring for this subflake. The root repo aliases these recipes.
#
# Small, skill-only upstreams ride as a `flake = false` input instead — see
# `mattpocock-skills` in flake.nix. Vendoring is for repos carrying a lot of
# non-skill weight, because a non-flake input has no sparse fetch and would
# copy the whole thing into the store.

# Where `gh skill` vendors upstream skill collections
SKILLS_DIR := "content/skills"

# Collections owned by one `modules.programs.ai` integration, one directory each
INTEGRATION_SKILLS_DIR := "content/integrations/skills"

# Vendor an upstream skill collection. Commit the result. Name a skill (or its
# path in the repo) to take just that one, `--all` for the whole collection,
# neither to pick interactively. `gh` takes one name per run and refuses `--all`
# beside it, so picking several means repeating the recipe.
# Usage: just vendor-skills plannotator/effective-html --all
#        just vendor-skills plannotator/effective-html html-plan
#        just vendor-skills google-labs-code/stitch-skills --all --pin v1.0
vendor-skills REPO *ARGS:
  gh skill install {{REPO}} --force --dir {{SKILLS_DIR}} {{ARGS}}
  git add {{SKILLS_DIR}}

# Vendor a collection that only one integration installs, into its own
# directory rather than the always-on profile set.
# Usage: just vendor-integration-skills orca stablyai/orca --all
vendor-integration-skills INTEGRATION REPO *ARGS:
  gh skill install {{REPO}} --force --dir {{INTEGRATION_SKILLS_DIR}}/{{INTEGRATION}} {{ARGS}}
  git add {{INTEGRATION_SKILLS_DIR}}/{{INTEGRATION}}

# Pull upstream changes into every vendored skill. `gh skill` tracks each one's
# origin in its own SKILL.md frontmatter, so there is no manifest to keep — and
# a skill written here by hand has none, so it is warned about and skipped.
# Usage: just update-skills [--dry-run]
update-skills *ARGS:
  #!/usr/bin/env bash
  set -euo pipefail
  for dir in {{SKILLS_DIR}} $(just _integration-skill-dirs); do
    gh skill update --all --dir "$dir" {{ARGS}}
    git add "$dir"
  done

# Show what upstream changed since our pins without touching anything: commits
# and diff for each `*-skills` flake input, then the diff `update-skills` would
# apply to the vendored skills (rehearsed on a temp copy, pinned ones skipped).
# Usage: just skill-changes | less -R
skill-changes:
  #!/usr/bin/env bash
  set -euo pipefail
  jq -r '.nodes | to_entries[] | select(.value.flake == false and (.key | endswith("-skills")))
    | [.key, .value.locked.owner, .value.locked.repo, .value.locked.rev, (.value.original.ref // "HEAD")] | @tsv' flake.lock |
    while IFS=$'\t' read -r name owner repo rev ref; do
      echo "=== $name: $owner/$repo ${rev:0:7}...$ref"
      gh api "repos/$owner/$repo/compare/$rev...$ref" --jq '.commits[] | "\(.sha[0:7]) \(.commit.message | split("\n")[0])"'
      gh api -H 'Accept: application/vnd.github.diff' "repos/$owner/$repo/compare/$rev...$ref"
    done
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  for dir in {{SKILLS_DIR}} $(just _integration-skill-dirs); do
    echo "=== vendored: $dir"
    mkdir -p "$tmp/$dir"
    cp -r "$dir/." "$tmp/$dir"
    gh skill update --all --dir "$tmp/$dir" 2>&1 |
      { grep -v -e 'has no GitHub metadata' -e 'is pinned to' || true; } >&2
    if f=$(grep -l '^ *github-pinned:' "$dir"/*/SKILL.md | head -1); then
      pin=$(sed -n 's/^ *github-pinned: *//p' "$f")
      repo=$(sed -n 's|^ *github-repo: *https://github.com/||p' "$f")
      latest=$(gh api "repos/$repo/releases?per_page=100" --jq "[.[].tag_name | select(startswith(\"${pin%%[0-9]*}\"))][0]")
      echo "⊘ pinned to $pin (latest $latest), skipped" >&2
    fi
    diff -ruN "$dir" "$tmp/$dir" || true
  done

# List the vendored skills with the repo and ref each came from. Hand-written
# skills have no origin and are omitted.
skills:
  #!/usr/bin/env bash
  set -euo pipefail
  {
    printf 'SKILL\tREPO\tREF\n'
    for dir in {{SKILLS_DIR}} $(just _integration-skill-dirs); do
      gh skill list --dir "$dir" --json skillName,sourceURL,version \
        --jq '.[] | select(.sourceURL != "") | [.skillName, (.sourceURL | sub("https://github.com/"; "")), .version] | @tsv'
    done
  } | column -t -s $'\t'

# Integration directories holding at least one vendored skill. Hand-written
# integration skills (coderabbit) have no origin metadata and are skipped.
[private]
_integration-skill-dirs:
  @grep -l '^ *github-repo:' {{INTEGRATION_SKILLS_DIR}}/*/*/SKILL.md 2>/dev/null | xargs -r -n1 dirname | xargs -r -n1 dirname | sort -u
