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
KEEP_FILE="$CONFIG_DIR/.ai-sync-keep"

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

  # Never installed, or ours already: no question to ask.
  if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
    install_file "$src" "$dst"
    continue
  fi
  if [ -L "$dst" ] && case "$(readlink "$dst")" in /nix/store/*) true ;; *) false ;; esac; then
    install_file "$src" "$dst"
    continue
  fi

  # A real file: identical content needs no prompt either.
  if cmp -s "$src" "$dst"; then
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
  diff --color=always -u "$dst" "$src" | tail -n +3
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
  printf 'ai-sync: kept your version of %d file(s): %s\n' \
    "${#skipped[@]}" "${skipped[*]}" >&2
fi
