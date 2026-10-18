# Sandbox setup for validating a layout B (transitional) apache/airflow checkout in cloudrun
# mode, against the pre-baked dispatcher-airflow-layoutb image (not the generic
# triagent-dispatcher-airflow service used for the first four attempts on #45835).
#
# Real history, 2026-10-11: the generic dispatcher's "install everything fresh every round"
# approach hit three real bugs in a row (a hatchling/editables limitation on local editable
# installs, pip treating bare directory names as PyPI package specs, then a ~1GB per-round
# export tar from reinstalling every third-party dependency each call) before a test ever ran
# cleanly. Real fix, same one layout C already proved: third-party dependencies are now pinned
# and baked into the image; the repo's own packages (core airflow/, task_sdk/, tests_common/,
# providers/google/) are never installed at all -- they're loaded via PYTHONPATH
# (dispatcher-airflow-layoutb/main.py's SANDBOX_DEFAULT_ENV), so this setup script now only
# needs to handle the one thing PYTHONPATH alone can't: nested provider directories
# (providers/common/sql/src, providers/common/compat/src, ...), via the same recursive glob
# layout C's setup script uses.
set -e
mkdir -p /tmp/airflow/logs
cat > /tmp/sitecustomize.py <<'PYEOF'
import glob
import sys

# providers/**/src with recursive=True also matches the bare "providers/src" (** matches zero
# segments too) -- confirmed real, 2026-10-11: providers/src is a genuine tracked directory in
# this era's repo with its own airflow/__init__.py, which overshadowed the real core airflow
# package when it landed on PYTHONPATH ahead of /root/repo. Excluded explicitly rather than
# tightening the glob pattern itself, since the exclusion is easier to read and audit.
for path in sorted(glob.glob("/root/repo/providers/**/src", recursive=True)):
    if path == "/root/repo/providers/src":
        continue
    if path not in sys.path:
        sys.path.insert(0, path)
PYEOF
