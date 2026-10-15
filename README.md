# triagent-airflow

Airflow-specific wiring for [triagent](https://github.com/sudsk/triagent): the `profile.json`
triagent's registry (`agents/profiles.py`) reads to learn this repo's identity, plus the
Cloud Run Sandbox dispatcher image and sandbox-setup script Builder/Judge/Bug Prover use when
running against Airflow.

## Layout

- `profile.json` — identity (upstream/fork/app_name) and wiring (dispatcher URL, test-command
  template, sandbox setup command) that triagent's dashboard and pipeline read for `repo_id =
  "airflow"`. `dispatcher_url` is `null` until this repo's dispatcher image (below) is actually
  deployed to Cloud Run — fill it in once that URL exists, so triagent routes cloudrun-mode runs
  to it automatically instead of needing the global `TRIAGENT_DISPATCHER_URL` env var swapped by
  hand.
- `dispatcher/` — the Cloud Run Sandbox dispatcher image for Airflow's Python toolchain (layout
  "c", the one confirmed working after two earlier layouts — `b` and the original generic
  `dispatcher-airflow` — hit real environment quirks fixed one at a time; see
  `docs/AIRFLOW-SETUP.md`).
- `sandbox_setup/airflow_layout_c.sh` — the one-time-per-image setup step run before every
  sandboxed command (`PipelineState.sandbox_setup_command` in triagent).
- `docs/` — Airflow-specific setup notes and the real Tier 1-4 provider-migration feasibility
  analysis.

## Using this with triagent

Clone this repo anywhere under `TRIAGENT_PROFILES_ROOT` (default
`~/triagent-phase1/profiles/`) — the directory name doesn't matter, triagent discovers it by
finding `profile.json`:

```
git clone <this repo's url> ~/triagent-phase1/profiles/airflow
```

Onboarding data (`record.csv`, `deepwiki.md`) is separate and still lives under
`TRIAGENT_ONBOARDING_ROOT/airflow/` (`agents/onboarding.py`) — that was already outside
triagent's own git history before this repo existed, so it isn't duplicated here.
