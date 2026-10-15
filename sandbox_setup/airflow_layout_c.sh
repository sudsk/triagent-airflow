# Sandbox setup for validating a split-layout (layout C) apache/airflow checkout in cloudrun mode.
# Runs before every sandbox command (see scripts/run_issue.py --sandbox-setup-script). Dependencies
# come from the pre-baked image (dispatcher-airflow-layoutc); this step only supplies `uv`, which
# devel-common's pytest plugin calls to regenerate its provider dependency list. Leaving the plugin
# unpatched keeps the repo's own files, and so the sandbox's diff, exactly as the pipeline edited them.
set -e
pip install -q --no-cache-dir uv
ln -sf /usr/local/bin/uv /usr/bin/uv || true
mkdir -p /tmp/airflow/logs
cat > /tmp/sitecustomize.py <<'PYEOF'
import glob
import sys

# Recursive, not providers/*/src -- real bug found 2026-10-10 validating #55127: Airflow nests
# some providers one level deeper (providers/common/sql/src, providers/common/compat/src, ...)
# instead of flat (providers/google/src). A flat glob silently missed every nested provider,
# so anything depending on apache-airflow-providers-common-sql (e.g. SpannerHook's DbApiHook
# base class) failed to import on every single run, not just occasionally.
for path in sorted(glob.glob("/root/repo/providers/**/src", recursive=True)):
    if path not in sys.path:
        sys.path.insert(0, path)
PYEOF
