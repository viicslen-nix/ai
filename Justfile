# Skill vendoring for this subflake. The root repo aliases these recipes.
#
# Small, skill-only upstreams ride as a `flake = false` input instead — see
# `mattpocock-skills` in flake.nix. Vendoring is for repos carrying a lot of
# non-skill weight, because a non-flake input has no sparse fetch and would
# copy the whole thing into the store.

# Where `gh skill` vendors upstream skill collections
SKILLS_DIR := "content/skills"

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

# Pull upstream changes into every vendored skill. `gh skill` tracks each one's
# origin in its own SKILL.md frontmatter, so there is no manifest to keep — and
# a skill written here by hand has none, so it is warned about and skipped.
# Usage: just update-skills [--dry-run]
update-skills *ARGS:
  gh skill update --all --dir {{SKILLS_DIR}} {{ARGS}}
  git add {{SKILLS_DIR}}

# List the vendored skills with the repo and ref each came from. Hand-written
# skills have no origin and are omitted.
skills:
  @gh skill list --dir {{SKILLS_DIR}} --json skillName,sourceURL,version \
    --jq '["SKILL","REPO","REF"], (.[] | select(.sourceURL != "") | [.skillName, (.sourceURL | sub("https://github.com/"; "")), .version]) | @tsv' \
    | column -t -s $'\t'
