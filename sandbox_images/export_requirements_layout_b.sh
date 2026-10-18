#!/bin/sh
# Generates dispatcher-airflow-layoutb/requirements.txt: a real, resolved freeze of layout B's
# third-party dependencies. No uv.lock or checked-in constraints file exists in-tree for this
# era (confirmed directly against the #45835 base-commit worktree, 2026-10-10), so unlike layout
# C's export_requirements.sh (a plain `uv export` from an existing lock file), this does a real
# resolution via `uv pip install` once, locally, against the worktree's own pyproject files --
# then strips the local workspace package names out of the freeze, since main.py's
# SANDBOX_DEFAULT_ENV puts them on PYTHONPATH instead of installing them (see that file's
# docstring for why: avoids a real hatchling/editables build limitation hit 2026-10-11).
#
# Run locally on triagent-runner, NOT inside a sandbox:
#   sh scripts/sandbox_images/export_requirements_layout_b.sh ~/triagent-phase1/airflow-issue-45835
#
# If this fails while building task_sdk/tests_common/providers/google themselves (the same
# hatchling error, or a new one), that means even a plain `uv pip install <local-path>` still
# invokes hatch_build.py's custom hook -- the real fallback then is to skip installing the local
# paths entirely and hand-resolve their third-party dependencies instead (read each package's
# pyproject.toml [project.dependencies]/[dependency-groups] directly and feed those specs to
# `uv pip install` with no local paths at all). Report the exact error back if this happens;
# don't guess which fallback form is needed without seeing it.
set -e
WORKTREE="${1:?usage: $0 <path-to-airflow-issue-45835-worktree>}"
cd "$WORKTREE"

rm -rf /tmp/layoutb-freeze-venv
python3.12 -m venv /tmp/layoutb-freeze-venv
/tmp/layoutb-freeze-venv/bin/pip install -q --no-cache-dir uv

/tmp/layoutb-freeze-venv/bin/uv pip install --python /tmp/layoutb-freeze-venv/bin/python3.12 \
    ./task_sdk ./tests_common ./providers/google . pytest pytest-mock

/tmp/layoutb-freeze-venv/bin/uv pip freeze --python /tmp/layoutb-freeze-venv/bin/python3.12 \
    | grep -Ev '^-e file://| @ file://' \
    > requirements-layoutb-raw.txt

echo "Wrote $WORKTREE/requirements-layoutb-raw.txt"
echo "Review it (should contain zero local-path entries -- those are PYTHONPATH, not pip)."
echo "uv pip freeze emits local-path installs in two different formats depending on whether"
echo "uv treated them as editable: 'name @ file://...' for the ones named directly on the"
echo "install command (., task_sdk, tests_common, providers/google), and the older pip-style"
echo "'-e file://...' (no package name on that line at all) for providers pulled in"
echo "transitively as workspace dependencies (confirmed real 2026-10-11: common/compat,"
echo "common/io, common/sql, fab, ftp, http, imap, smtp, sqlite, standard all came back this"
echo "way even though no -e flag was passed on the command line) -- both forms are filtered"
echo "here. If a future uv version adds a third format, grep -n 'file://' the raw output"
echo "directly rather than assuming these two patterns are exhaustive."
echo "then copy it to dispatcher-airflow-layoutb/requirements.txt"
