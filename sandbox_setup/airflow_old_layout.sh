# Sandbox setup for validating a pre-monorepo-split (old flat layout) apache/airflow checkout in
# cloudrun mode. Runs before every sandbox command (see scripts/run_issue.py --sandbox-setup-script).
#
# Deliberately not a venv and not system-wide: `python3 -m venv` fails inside the sandbox, and
# system-wide installs land under /usr/local, which the sandbox exports as part of its state --
# that bloated the saved tar past ~800 MB and got it truncated (2026-10-04). /tmp is not exported,
# so the packages live there, and a small wrapper on PATH points pytest at them.
#
# AIRFLOW_HOME moves to /tmp because /root is not writable for root in this sandbox after the tar
# import (owned by uid 1000), and Airflow's logging config writes there at import time.
set -e
pip install -q --no-cache-dir --target /tmp/site pytest openlineage-python time-machine requests-mock pytest-asyncio pytest-mock pytest-xdist '.[devel,google]'
mkdir -p /tmp/airflow/logs
cat > /usr/local/bin/pytest <<'WRAPPER'
#!/bin/sh
AIRFLOW_HOME=/tmp/airflow AIRFLOW__LOGGING__BASE_LOG_FOLDER=/tmp/airflow/logs PYTHONPATH=/tmp/site exec python3 -m pytest -p no:cacheprovider "$@"
WRAPPER
chmod +x /usr/local/bin/pytest
