#!/usr/bin/env bash
# Reconcile a store-built config tree into a writable config directory.
#
# Ownership is decided by the target itself, not by a manifest: a symlink into
# the store is ours and is retargeted silently, a regular file is someone's
# edit (the user's, or the harness rewriting its own config) and is diffed and
# confirmed. That keeps the prompts to the handful of files that actually
# diverged, out of the 50-80 a harness generates.
set -uo pipefail

MANIFEST="$1" # tab-separated: <relative path>\t<store path>
CONFIG_DIR="$2"
REL_DIR="$3" # CONFIG_DIR relative to $HOME, as home-manager names it
KEEP_FILE="$CONFIG_DIR/.ai-sync-keep"

# home-manager already manages this harness here: it keeps these files current,
# so there is nothing to add, and taking even one of them over makes the next
# activation fail with "would be clobbered".
#
# Ask the generation what it *declares*, not the directory what it holds: the
# files are missing exactly when an activation has failed, which is when this
# matters most, and a path home-manager only starts managing later would slip
# past a check that looked at disk.
stood_down() {
  printf 'ai-sync: %s is managed by home-manager; leaving it alone\n' \
    "$CONFIG_DIR" >&2
  exit 0
}

hm_gen=$(readlink -f \
  "${XDG_STATE_HOME:-$HOME/.local/state}/home-manager/gcroots/current-home" 2>/dev/null) || hm_gen=""
if [ -n "$hm_gen" ] && [ -n "$REL_DIR" ] && [ -e "$hm_gen/home-files/$REL_DIR" ]; then
  stood_down
fi

# Fallback for a home-manager that keeps no such gcroot.
while IFS=$'\t' read -r rel _; do
  [ -n "$rel" ] || continue
  case "$(readlink "$CONFIG_DIR/$rel" 2>/dev/null)" in
  *-home-manager-files/*) stood_down ;;
  esac
done <"$MANIFEST"

mkdir -p "$CONFIG_DIR"
touch "$KEEP_FILE" 2>/dev/null || true

# `a`/`q` answered once apply to the rest of the run.
answer_all=""
skipped=()

interactive() { [ -t 0 ] && [ -t 1 ]; }

kept() { grep -Fxq "$1" "$KEEP_FILE" 2>/dev/null; }

install_file() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  ln -sfn "$src" "$dst"
}

while IFS=$'\t' read -r rel src; do
  [ -n "$rel" ] || continue
  dst="$CONFIG_DIR/$rel"

  # Never installed: no question to ask.
  if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
    install_file "$src" "$dst"
    continue
  fi

  if [ -L "$dst" ] && case "$(readlink "$dst")" in /nix/store/*) true ;; *) false ;; esac; then
    install_file "$src" "$dst"
    continue
  fi

  # A multi-file skill is a directory, so this compares trees, not just files —
  # `cmp` reports "Is a directory" and claims every one of them differs.
  if diff -rq "$src" "$dst" >/dev/null 2>&1; then
    continue
  fi

  if kept "$rel"; then
    continue
  fi

  case "${AI_SYNC:-}" in
  force)
    install_file "$src" "$dst"
    continue
    ;;
  skip)
    skipped+=("$rel")
    continue
    ;;
  esac

  if ! interactive; then
    skipped+=("$rel")
    continue
  fi

  case "$answer_all" in
  a)
    install_file "$src" "$dst"
    continue
    ;;
  q)
    skipped+=("$rel")
    continue
    ;;
  esac

  printf '\n\033[1m%s\033[0m differs from the version this build carries:\n\n' "$rel"
  if [ -d "$src" ]; then
    diff --color=always -ru "$dst" "$src"
  else
    diff --color=always -u "$dst" "$src" | tail -n +3
  fi
  printf '\nReplace it? [y]es / [n]o / [a]ll / [q]uit asking: '
  read -r reply </dev/tty || reply=n

  case "$reply" in
  y | Y) install_file "$src" "$dst" ;;
  a | A)
    answer_all=a
    install_file "$src" "$dst"
    ;;
  q | Q)
    answer_all=q
    skipped+=("$rel")
    ;;
  *)
    printf '%s\n' "$rel" >>"$KEEP_FILE"
    skipped+=("$rel")
    ;;
  esac
done <"$MANIFEST"

if [ ${#skipped[@]} -gt 0 ]; then
  printf 'ai-sync: kept your version of %d file(s); AI_SYNC=force replaces them\n' \
    "${#skipped[@]}" >&2
fi
