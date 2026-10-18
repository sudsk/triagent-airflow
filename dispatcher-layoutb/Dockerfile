# Sandbox image for the transitional Airflow layout (layout B, docs/ARCHITECTURE.md's profile
# design): third-party dependencies pinned once, baked in. The repo's own packages (core
# airflow/, task_sdk/, tests_common/, providers/google/) are NOT installed -- they're loaded from
# the checked-out source via PYTHONPATH (main.py's SANDBOX_DEFAULT_ENV), so the sandbox always
# tests the code the pipeline actually edited, not a frozen copy, and the per-round overlay stays
# small (real problem found 2026-10-11: installing them fresh every round bloated the export tar
# to ~1GB and hit a hatchling/editables limitation on local editable installs).
#
# requirements.txt is generated, not hand-written -- see main.py's module docstring.
FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates build-essential pkg-config \
        libkrb5-dev libmariadb-dev libpq-dev libsasl2-dev libldap2-dev \
        libffi-dev libssl-dev libxml2-dev libxslt1-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY dispatcher-requirements.txt .
RUN pip install --no-cache-dir -r dispatcher-requirements.txt

COPY main.py .

# /root is owned by a non-root uid after the tar import, so Airflow's own home and logs go to /tmp.
ENV AIRFLOW_HOME=/tmp/airflow
ENV PYTHONPATH=/root/repo:/root/repo/task_sdk/src

CMD exec uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080}
