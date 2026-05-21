#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE="${GITHUB_REMOTE:-origin}"
BRANCH="${GITHUB_BRANCH:-main}"
TMP_PARENT="${PUSH_TMP_PARENT:-/tmp}"
KEEP_TMP="${KEEP_PUSH_TMP:-0}"
DRY_RUN="${DRY_RUN:-0}"
COMMIT_MSG="${COMMIT_MSG:-chore: sync project updates}"
PUSH_MODE="${PUSH_MODE:-changes}"
RSYNC_COMMON=(-rt --no-owner --no-group --no-perms)

if ! command -v git >/dev/null 2>&1; then
  echo "[FAIL] git not found"
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "[FAIL] rsync not found"
  exit 1
fi

cd "$ROOT_DIR"

PUSH_URL="$(git remote get-url --push "$REMOTE")"
if [ -z "$PUSH_URL" ]; then
  echo "[FAIL] could not resolve push URL for remote '$REMOTE'"
  exit 1
fi

TMP_DIR="$(mktemp -d "$TMP_PARENT/aes_huffman_push.XXXXXX")"
cleanup() {
  if [ "$KEEP_TMP" != "1" ]; then
    rm -rf "$TMP_DIR"
  else
    echo "[INFO] kept temp repo: $TMP_DIR"
  fi
}
trap cleanup EXIT

echo "[INFO] cloning clean push workspace from $PUSH_URL"
git clone --quiet --no-checkout "$PUSH_URL" "$TMP_DIR"
git -C "$TMP_DIR" fetch --quiet origin "$BRANCH"
git -C "$TMP_DIR" checkout --quiet -B "$BRANCH" "origin/$BRANCH"

copy_file() {
  local src="$1"
  local rel="${src#$ROOT_DIR/}"
  mkdir -p "$TMP_DIR/$(dirname "$rel")"
  rsync "${RSYNC_COMMON[@]}" "$src" "$TMP_DIR/$rel"
}

copy_dir() {
  local rel="$1"
  shift || true
  [ -d "$ROOT_DIR/$rel" ] || return 0
  mkdir -p "$TMP_DIR/$rel"
  rsync "${RSYNC_COMMON[@]}" --delete "$@" "$ROOT_DIR/$rel/" "$TMP_DIR/$rel/"
}

remove_path() {
  local rel="$1"
  rm -rf "$TMP_DIR/$rel"
}

is_safe_path() {
  local rel="${1#./}"

  case "$rel" in
    .git/*|.Xil/*|vivado/build/*|vivado/logs/*|sim/work/*|sim/log/*|sim/dmem_dump/*|sim/loopback/*|sim/coverage/*|sim/ucdb/*)
      return 1
      ;;
    *.wlf|*.ucdb|*.elf|*.bin|*.mem|*.S|*.jou|*.log|*.qdb|*.qpg|*.qtl|*.vstf|instruction.mem|sim/instruction.mem)
      return 1
      ;;
  esac

  case "$rel" in
    Makefile|README|README.*|*.md|*.sh|*.py|*.tcl|*.f|*.xdc)
      return 0
      ;;
    docs/*|rtl/*|tb/*|tools/*|testcase/*)
      return 0
      ;;
    sim/Makefile|sim/*.f|sim/*.do|sim/*.csh|sim/*.tcl)
      return 0
      ;;
    vivado/*.tcl|vivado/constraints/*)
      return 0
      ;;
  esac

  return 1
}

copy_or_remove_safe_path() {
  local rel="${1#./}"
  [ -n "$rel" ] || return 0

  if ! is_safe_path "$rel"; then
    echo "[SKIP] $rel"
    return 0
  fi

  if [ -d "$ROOT_DIR/$rel" ]; then
    copy_dir "$rel"
  elif [ -f "$ROOT_DIR/$rel" ]; then
    copy_file "$ROOT_DIR/$rel"
  else
    remove_path "$rel"
  fi
}

sync_selected_paths() {
  local rel
  for rel in $GIT_ADD_PATHS; do
    rel="${rel#./}"
    if [ -d "$ROOT_DIR/$rel" ]; then
      copy_or_remove_safe_path "$rel"
    elif [ -f "$ROOT_DIR/$rel" ]; then
      copy_or_remove_safe_path "$rel"
    else
      copy_or_remove_safe_path "$rel"
    fi
  done
}

sync_tree_paths() {
  shopt -s nullglob

  for file in \
    "$ROOT_DIR"/.gitignore \
    "$ROOT_DIR"/Makefile \
    "$ROOT_DIR"/*.md \
    "$ROOT_DIR"/*.sh \
    "$ROOT_DIR"/*.py \
    "$ROOT_DIR"/*.tcl \
    "$ROOT_DIR"/*.f \
      "$ROOT_DIR"/*.xdc; do
    [ -f "$file" ] && copy_file "$file"
  done

  copy_dir docs
  copy_dir rtl
  copy_dir tb
  copy_dir tools

  copy_dir testcase \
    --exclude='*.S' \
    --exclude='*.elf' \
    --exclude='*.bin' \
    --exclude='*.mem' \
    --exclude='*.log' \
    --exclude='*.wlf' \
    --exclude='*.ucdb'

  if [ -d "$ROOT_DIR/sim" ]; then
    mkdir -p "$TMP_DIR/sim"
    for file in \
      "$ROOT_DIR"/sim/Makefile \
      "$ROOT_DIR"/sim/*.f \
      "$ROOT_DIR"/sim/*.do \
      "$ROOT_DIR"/sim/*.csh \
      "$ROOT_DIR"/sim/*.tcl; do
      [ -f "$file" ] && copy_file "$file"
    done
  fi

  copy_dir vivado \
    --exclude='build/' \
    --exclude='logs/' \
    --exclude='*.jou' \
    --exclude='*.log' \
    --exclude='*.str' \
    --exclude='*.dcp' \
    --exclude='.Xil/'
}

sync_changed_paths() {
  local changed
  local untracked
  local rel

  changed="$(git -C "$ROOT_DIR" diff --name-only HEAD -- || true)"
  untracked="$(git -C "$ROOT_DIR" ls-files --others --exclude-standard || true)"

  if [ -z "$changed$untracked" ]; then
    echo "[INFO] current working tree has no uncommitted paths"
    return 0
  fi

  {
    printf '%s\n' "$changed"
    printf '%s\n' "$untracked"
  } | sort -u | while IFS= read -r rel; do
    copy_or_remove_safe_path "$rel"
  done
}

if [ -n "${GIT_ADD_PATHS:-}" ]; then
  echo "[INFO] syncing explicit paths: $GIT_ADD_PATHS"
  sync_selected_paths
elif [ "$PUSH_MODE" = "tree" ]; then
  echo "[INFO] syncing full source/docs/config allowlist"
  sync_tree_paths
else
  echo "[INFO] syncing changed safe source/docs/config paths"
  sync_changed_paths
fi

find "$TMP_DIR" -type f -name '*.sh' -exec chmod 755 {} +

git -C "$TMP_DIR" add -A

echo "[INFO] staged changes:"
git -C "$TMP_DIR" status --short

if git -C "$TMP_DIR" diff --cached --quiet; then
  echo "[INFO] no source/docs/config changes to commit"
else
  src_name="$(git config user.name || true)"
  src_email="$(git config user.email || true)"
  git -C "$TMP_DIR" config user.name "${src_name:-luc-rgb-v}"
  git -C "$TMP_DIR" config user.email "${src_email:-luchdt.ic@gmail.com}"
  git -C "$TMP_DIR" commit -m "$COMMIT_MSG"
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "[INFO] DRY_RUN=1, skip push"
  git -C "$TMP_DIR" log --oneline --decorate -3
  exit 0
fi

echo "[INFO] pushing HEAD to $REMOTE/$BRANCH"
if ! git -C "$TMP_DIR" push origin "HEAD:$BRANCH"; then
  echo "[WARN] push rejected; rebasing once on latest origin/$BRANCH"
  git -C "$TMP_DIR" fetch --quiet origin "$BRANCH"
  git -C "$TMP_DIR" rebase "origin/$BRANCH"
  git -C "$TMP_DIR" push origin "HEAD:$BRANCH"
fi

echo "[PASS] pushed to $REMOTE/$BRANCH"
