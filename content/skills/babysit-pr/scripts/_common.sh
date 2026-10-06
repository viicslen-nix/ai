# Sourced by pr-watch and pr-threads. Sets REPO, PR, STATE_DIR, DRY_RUN, ARGS.
set -euo pipefail

die() {
  echo "error: $*" >&2
  exit 1
}

REPO="" PR="" DRY_RUN=0 ARGS=()
while (($#)); do
  case $1 in
    -R | --repo) REPO=$2; shift 2 ;;
    --pr) PR=$2; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

[[ -n $REPO ]] || REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner) || die "no repo; pass -R owner/repo"
[[ -n $PR ]] || PR=$(gh pr view --json number -q .number) || die "no PR for this branch; pass --pr N"

# Shared by both scripts: `own` lists comment IDs the agent posted, so pr-watch never reports them as new feedback.
STATE_DIR=/tmp/pr-watch/${REPO//\//_}-$PR
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/own" "$STATE_DIR/seen"

record_own() {
  echo "$1" >>"$STATE_DIR/own"
}
