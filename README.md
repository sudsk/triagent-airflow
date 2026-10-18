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
- `dispatcher/` — the Cloud Run Sandbox dispatcher image for Airflow's Python toolchain, layout
  "c" — the current, confirmed-working one (see `docs/AIRFLOW-SETUP.md`). This is the one
  `profile.json`'s `dispatcher_url` points at once deployed.
- `dispatcher-layoutb/` — the previous proven monorepo layout, superseded by layout "c" but kept
  for reference rather than deleted (not dead weight — it worked for a real set of issues before
  an environment quirk forced the move to "c").
- `dispatcher-generic/` — the original, pre-monorepo-split dispatcher: plain Python, no toolchain
  baked in, dependencies installed fresh on every call. Kept as the fragile fallback/exploration
  path, not used by default.
- `sandbox_setup/airflow_layout_c.sh` — the one-time-per-image setup step run before every
  sandboxed command (`PipelineState.sandbox_setup_command` in triagent) for the current layout.
- `sandbox_setup/airflow_layout_b.sh` — the equivalent setup step for `dispatcher-layoutb/`.
- `sandbox_setup/airflow_old_layout.sh` — the equivalent setup step for `dispatcher-generic/`
  (pre-monorepo-split, flat-layout checkouts).
- `sandbox_images/export_requirements.sh` / `export_requirements_layout_b.sh` — export a pinned
  `dispatcher-requirements.txt` from the target repo's own `uv.lock` at a given commit, for layout
  "c" and layout "b" respectively. Run from Cloud Shell against a real checkout; output feeds the
  corresponding `dispatcher*/dispatcher-requirements.txt`.
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
