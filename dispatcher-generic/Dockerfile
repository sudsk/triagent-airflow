# Task 35/47's Airflow dispatcher (docs/BACKLOG.md) -- same generic dispatcher pattern as
# dispatcher/Dockerfile (task 45, libphonenumber), toolchain generalized for Airflow instead of
# pinned to it. main.py itself is identical to dispatcher/main.py (copied, not modified) -- it was
# already generalized to one flexible /do endpoint during task 45, so only the toolchain baked
# into THIS image differs.
#
# Deliberately NOT pinned to one apache-airflow release, unlike scripts/spike_cloudrun_airflow's
# Dockerfile (built for one specific system test at one specific release). Task 35's own real
# validation batch runs 8 issues against 8 different real historical base commits, spanning
# different real Airflow eras with genuinely incompatible pinned dependencies -- confirmed real,
# 2026-10-02: issue #40063's own base commit (2024-06-10, pre-monorepo-split) needs
# SQLAlchemy<1.5 (flask-appbuilder's own real constraint at that era), while triagent's own
# orchestrator needs SQLAlchemy>=2.0 (google-adk[db]) -- the exact conflict that made running
# target-repo tests in triagent's own shared .venv unsafe. Baking in one fixed Airflow version
# here would just relocate that same conflict into this image instead of solving it.
#
# Real fix: this image stays a generic Python toolchain -- git, build tooling for any C-extension
# wheels an older pinned dependency might need to compile, and nothing Airflow-specific. Each
# checkout's OWN pinned dependencies get installed fresh, inside the sandbox, per invocation --
# as the first half of the compound test command itself (e.g. `pip install -e . -q && pytest
# ...`), not baked into this image -- so every issue gets correctly isolated, era-appropriate
# dependencies, never touching triagent's own orchestrator .venv on the host VM at all. Slower
# per-invocation than a pre-warmed image (no dependency cache between sandbox calls, unlike
# dispatcher/Dockerfile's pre-warmed /root/.m2) -- an accepted tradeoff for a one-off validation
# batch, not a high-frequency production path; revisit if Task 35's batch size grows enough to
# make per-invocation install time a real bottleneck.
FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .

WORKDIR /app
CMD exec uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080}
