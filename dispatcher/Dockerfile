# Sandbox image for the split Airflow layout (layout C, docs/ARCHITECTURE.md's profile design):
# dependencies pinned from the monorepo's own uv.lock at a 2026 base commit, baked in once. The
# repo's own packages are NOT installed -- they're loaded from the checked-out source via PYTHONPATH,
# so the sandbox always tests the code the pipeline actually edited, not a frozen copy.
#
# requirements.txt is generated, not hand-written: scripts/sandbox_images/export_requirements.sh.
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
ENV PYTHONPATH=/root/repo/airflow-core/src:/root/repo/task-sdk/src:/root/repo/devel-common/src:/root/repo/providers/google/src

CMD exec uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080}
