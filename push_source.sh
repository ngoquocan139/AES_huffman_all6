#!/bin/bash
set -e

if [ -n "$GIT_ADD_PATHS" ]; then
  # shellcheck disable=SC2086
  git add $GIT_ADD_PATHS
else
  git add -A
fi

git status

if [ -n "$COMMIT_MSG" ]; then
  msg="$COMMIT_MSG"
else
  echo "Nhap commit message:"
  read -r msg
fi

if git diff --cached --quiet; then
  echo "[INFO] no staged changes to commit"
else
  git commit -m "$msg"
fi

if [ -n "$GIT_PUSH_ARGS" ]; then
  # shellcheck disable=SC2086
  git push $GIT_PUSH_ARGS
else
  # shellcheck disable=SC2086
  git push ${DEFAULT_GIT_PUSH_ARGS:-origin HEAD:main}
fi
