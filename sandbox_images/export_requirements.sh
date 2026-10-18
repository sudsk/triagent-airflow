# Exports a pinned requirements file from the monorepo's own uv.lock at one commit.
#
# Usage: sh scripts/sandbox_images/export_requirements.sh <airflow-repo> <commit-sha> <absolute-output-path>
#
# Uses a throwaway worktree so the shared clone's HEAD is never touched. --no-emit-workspace drops
# the monorepo's own local packages (airflow-core, task-sdk, providers, devel-common): they're loaded
# from source via PYTHONPATH in the image instead, so they track the repo the sandbox actually gets.
set -e
REPO="$1"
SHA="$2"
OUT="$3"
WT="$(mktemp -d)/airflow-lock"
git -C "$REPO" worktree add --detach "$WT" "$SHA"
(cd "$WT" && uv export --frozen --no-hashes --no-emit-workspace --all-groups > "$OUT")
git -C "$REPO" worktree remove --force "$WT"
echo "wrote $OUT ($(wc -l < "$OUT") lines)"
