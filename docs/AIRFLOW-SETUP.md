# Apache Airflow target-repo setup runbook

Practical "what's actually deployed and how do I build a new one" reference for everything
specific to onboarding `apache/airflow` as a target repo — moved out of `docs/SETUP.md` (2026-10-11)
because that file is triagent's own generic setup runbook, and no onboarded target repo's
infra/config belongs mixed into it. Full real narrative (every bug found validating `#45835`,
Judge findings, etc.) lives in `docs/TIER2-VALIDATION-SET.md` and `docs/BACKLOG.md` task 35 — this
file doesn't repeat that, just the reusable facts.

Status markers: ✅ done · 🟡 in progress · 🔲 not started yet.

## Task 35 — Tier 2 validation: per-layout dispatcher services ✅ real values, 🟡 layout B in progress

**Why per-layout dispatcher services exist at all**: `apache/airflow`'s repo layout changed
substantially across eras (monolithic `airflow/` → a `providers/` split → an `airflow-core/` split
→ renamed `task-sdk`/`devel-common`), so one generic sandbox image's `PYTHONPATH`/dependency set
can't serve every issue's base commit. Each era gets its own pre-baked Cloud Run service once
proven; the generic `triagent-dispatcher-airflow` (no baked deps, installs fresh every round) only
exists for fallback/exploration and is known fragile for real installs (see
`docs/TIER2-VALIDATION-SET.md`'s `#45835` section — hatchling/editables limitation, pip
bare-directory-name ambiguity, ~1GB per-round export tars, all from that fresh-install approach).

**Real deployed services, `hl2-gogl-adlc-t1iylu`, confirmed via `gcloud run services list
--region=us-central1`, 2026-10-11**:
- `triagent-dispatcher-airflow` — generic, no baked deps, fresh install every round (fragile, see above)
- `triagent-dispatcher-airflow-c` — layout C (the `airflow-core`/`providers` split era), pre-baked, working
- `triagent-dispatcher-airflow-b` — layout B (the transitional, pre-`airflow-core`-split era),
  pre-baked, deployed 2026-10-11: `https://triagent-dispatcher-airflow-b-rskrx72e6q-uc.a.run.app`
- `triagent-dispatcher-libphonenumber` — unrelated target repo, from task 45 (see `docs/SETUP.md`)
- `triagent-webhook` — GitHub webhook receiver, task 27/46 (see `docs/SETUP.md`)

**Real values confirmed off `triagent-dispatcher-airflow-c`'s own config** (`gcloud run services
describe triagent-dispatcher-airflow-c --region=us-central1 --project=hl2-gogl-adlc-t1iylu
--format="yaml(spec.template.spec.containers)"`):
```
image: us-central1-docker.pkg.dev/hl2-gogl-adlc-t1iylu/triagent-spike/triagent-dispatcher-airflow-layoutc:2026-09
env: TRIAGENT_SANDBOX_GCS_BUCKET=triagent-sandbox-tars-hl2-gogl-adlc-t1iylu
resources: cpu=2, memory=4Gi
sandboxLauncher: true
startupProbe: tcpSocket:8080, periodSeconds=240, timeoutSeconds=240, failureThreshold=1
```
Artifact Registry repo is `triagent-spike` (not `triagent`) — note the image path's repo segment
doesn't match the project-id-derived naming you'd guess. Build/deploy a new per-layout image the
same way (substitute the layout name):
```bash
gcloud builds submit --tag us-central1-docker.pkg.dev/hl2-gogl-adlc-t1iylu/triagent-spike/triagent-dispatcher-airflow-<layout>:<tag> \
  --project=hl2-gogl-adlc-t1iylu dispatcher-airflow-<layout>/
gcloud alpha run deploy triagent-dispatcher-airflow-<layout-short-name> \
  --image us-central1-docker.pkg.dev/hl2-gogl-adlc-t1iylu/triagent-spike/triagent-dispatcher-airflow-<layout>:<tag> \
  --region=us-central1 --project=hl2-gogl-adlc-t1iylu \
  --no-allow-unauthenticated --sandbox-launcher --cpu=2 --memory=4Gi \
  --set-env-vars=TRIAGENT_SANDBOX_GCS_BUCKET=triagent-sandbox-tars-hl2-gogl-adlc-t1iylu
```
`--sandbox-launcher` is an `alpha`-track flag on current `gcloud` — plain `gcloud run deploy`
rejects it with "unrecognized arguments" (confirmed real, 2026-10-11, deploying layout B). Use
`gcloud alpha run deploy` (or `beta`, if `alpha` isn't installed).

**Required follow-up step, every new per-layout service: grant `sk-triagent` `run.invoker` on it
specifically.** `--no-allow-unauthenticated` means each service needs its own IAM binding — this
does NOT carry over from an existing service's binding, even one on the same project/VM/bucket
(confirmed real, 2026-10-11: `triagent-dispatcher-airflow-b`'s first run failed with a 403 at the
very first `/do` call — shallow fetch — until this was granted). Do this right after every deploy:
```bash
gcloud run services add-iam-policy-binding triagent-dispatcher-airflow-<layout-short-name> \
  --region=us-central1 --project=hl2-gogl-adlc-t1iylu \
  --member="serviceAccount:sk-triagent@hl2-gogl-adlc-t1iylu.iam.gserviceaccount.com" \
  --role="roles/run.invoker"
```

**Real identity-split gotcha, hit for real 2026-10-11**: `gcloud builds submit` is normally run
from Cloud Shell under the human's own identity (`suds_kumar@epam.com`), which has no access to
the persistent VM's filesystem (that VM runs under its own service account) — so any sandbox-image
build input (e.g. a per-layout `requirements.txt` generated on the VM against a base-commit
worktree) has to travel through git to reach Cloud Shell; there's no shared filesystem between the
two identities/hosts. This is why per-layout `requirements.txt` files are checked into
`dispatcher-airflow-<layout>/requirements.txt` despite being a frozen snapshot of the *target*
repo's (apache/airflow's) own dependencies, not triagent's own config — ideally this would live
outside triagent's repo (a dedicated per-target-repo config repo, or a GCS-based build input), but
there's no alternative delivery path between Cloud Shell and the VM yet. Revisit if one gets built.

**Layout B status (2026-10-11): proven, same standing as layout C.**
`dispatcher-airflow-layoutb/` has `Dockerfile`, `main.py`, `requirements.txt` (generated via
`scripts/sandbox_images/export_requirements_layout_b.sh` against the `#45835` base-commit
worktree), `dispatcher-requirements.txt`; `scripts/sandbox_setup/airflow_layout_b.sh` is the
matching (dependency-install-free) setup script — same pattern as layout C, PYTHONPATH instead of
pip/uv-installing the repo's own packages, with one real exclusion the glob needs that layout C's
doesn't: `providers/src` (a genuine tracked directory in this era with its own `airflow/
__init__.py`) overshadows the real core `airflow` package if it isn't excluded from the recursive
`providers/**/src` glob. Deployed as `triagent-dispatcher-airflow-b`
(current URL: `gcloud run services describe triagent-dispatcher-airflow-b --region=us-central1
--project=hl2-gogl-adlc-t1iylu --format='value(status.url)'` — confirm live rather than reusing an
old one, the URL format changed between deploys here), image tag
`triagent-dispatcher-airflow-layoutb:2026-10`, revision `-00002-p87` as of the fix that added
`CAPTURE_WARNINGS_OUTPUT=/tmp/warnings.txt` to `SANDBOX_DEFAULT_ENV` (relative `warnings.txt`
defaults to an unwritable cwd otherwise). `#45835` converged clean (`28 passed`) and published as
`https://github.com/sudsk/airflow/pull/4` — real evidence that `agents/builder_judge.py`'s
`edit_file` tool (commit `c5f5476`) eliminates the full-file-rewrite docstring-corruption defect
that blocked v1–v3/v6, not just makes it rarer. Full narrative: `docs/TIER2-VALIDATION-SET.md`'s
`#45835` section.

## Running a real issue against Airflow — the exact commands

This has only ever been written down abbreviated (just `--repo-path`) in
`docs/TIER2-VALIDATION-SET.md`'s per-attempt notes, which made every run's exact invocation
un-reconstructable afterward. Full command set, every flag, so this doesn't need re-deriving from
`scripts/run_issue.py --help`/`agents/sandbox_env.py` each time.

**1. Cloud Run Sandbox env vars** — required together or `agents/sandbox_env.py` fails loud
(`TRIAGENT_SANDBOX_MODE=cloudrun requires both TRIAGENT_DISPATCHER_URL and
TRIAGENT_SANDBOX_GCS_BUCKET`). Fetch the dispatcher URL live every time — its format has changed
between deploys before (see layout B note above), never reuse a URL copied from an old session:

```bash
export TRIAGENT_SANDBOX_MODE=cloudrun
export TRIAGENT_DISPATCHER_URL=$(gcloud run services describe triagent-dispatcher-airflow-c \
  --region=us-central1 --project=hl2-gogl-adlc-t1iylu --format='value(status.url)')
export TRIAGENT_SANDBOX_GCS_BUCKET=triagent-sandbox-tars-hl2-gogl-adlc-t1iylu
```

Substitute `triagent-dispatcher-airflow-b` + `scripts/sandbox_setup/airflow_layout_b.sh` (step 3
below) for an issue whose base commit predates the `airflow-core`/`providers` split. If neither
layout's setup script works against a given base commit, that's a new era — see Task 47 item 3,
don't assume it's layout C by default just because it's the newest proven one.

**2. Base-commit worktree** — off the merge commit's first parent, not the PR's `base.sha` field
(the methodology bug `docs/TIER2-VALIDATION-SET.md`'s `#56138` attempt 1 found: `base.sha` can
drift from the real pre-merge state):

```bash
cd ~/triagent-phase1/airflow
git fetch upstream main
git worktree add ~/triagent-phase1/airflow-issue-<N> $(git rev-parse <merge_commit_sha>^1)
```

**3. The run itself** — from `~/triagent-phase1/triagent` (`scripts/`/`agents/` live there).
`--issue-body-file` takes a file, not inline text (real issue bodies are long/multi-line).
`--repo-id` defaults to `--repo-path`'s own directory name (`airflow-issue-<N>`, which won't match
any onboarding record) — pass `--repo-id airflow` explicitly so `deep_wiki_table_of_contents`
looks up the right key, even though no Airflow onboarding record exists yet either way (Task 47
item 3):

```bash
cd ~/triagent-phase1/triagent
cat > /tmp/issue-<N>-body.txt <<'EOF'
<issue text here>
EOF

python3 scripts/run_issue.py \
  --issue-number <N> \
  --issue-title "<short title>" \
  --issue-body-file /tmp/issue-<N>-body.txt \
  --issue-url "https://github.com/apache/airflow/pull/<N>" \
  --repo-path ~/triagent-phase1/airflow-issue-<N> \
  --repo-id airflow \
  --sandbox-setup-script scripts/sandbox_setup/airflow_layout_c.sh \
  --test-command-template "pytest providers/google/tests/unit/<module> -q"
```

**Always pass `--test-command-template` explicitly for Airflow.** Its default
(`DEFAULT_TEST_COMMAND_TEMPLATE` in `run_issue.py`) is `"mvn -pl <module> test -q"` — a Maven
template left over from the libphonenumber validation set. Found for real (2026-10-12, issue
#74237, the bug-path dry run): omitting it against a Python/pytest repo doesn't error loud — Bug
Hunter just can't derive a sensible `<module>` fill for a Maven command, returns no command
(`test_command_derived: false`), and Bug Prover then correctly refuses to claim reproduction
(`confirmed: false, reason: "no_test_command_available"`) rather than faking it — the whole run
ends quietly ("insufficient investigation confidence") with no error anywhere to grep for. Check
the run's JSONL recording (`~/triagent-phase1/run_issue_<N>_<uuid>.jsonl`, `tail` the last few
lines) if a run ends this early with no Builder/Judge rounds — this exact signature is the tell.
The template above is layout C's pytest shape, no `pip install` prefix needed (the pre-baked image
+ `sitecustomize.py` PYTHONPATH wiring already cover it); use the old-layout install+pytest
compound command instead for a layout B base commit (see the per-layout install commands in
`docs/TIER2-VALIDATION-SET.md`'s Cloud Run sandbox section).

**Second real finding, same run, one step later: `--test-command-template`'s `<module>`
derivation only works for Bug Hunter/Bug Prover's own reproduction check, not for TDD Architect's
authoritative `state.test_command`, for a pytest-shaped template.** TDD Architect's instruction
(`agents/tdd_architect.py`'s `_TEST_COMMAND_CLAUSE`) tells the model to find `<module>` by
searching for a Maven-style build-system marker file (`find . -name pom.xml`, directory-of) and
using its directory — written entirely with libphonenumber's Maven layout in mind, same family of
assumption as the hardcoded Maven default template itself. A pytest template where `<module>` is
a *test subpath* (`providers/google/tests/unit/<module>`), not a module-with-its-own-marker-file,
has no such marker to find — TDD Architect correctly follows its own instruction ("if you can't
determine the right module, do not guess — omit the TEST_COMMAND line") rather than guess wrong,
and `agents/builder_judge.py::run_cycle` then fails loud: `ValueError: run_cycle requires
state.test_command`. Confirmed real, 2026-10-12, issue #74237: Bug Hunter/Bug Prover's
reproduction check passed fine with the templated form, but TDD Architect omitted TEST_COMMAND.

**Workaround until this is fixed (Task 31's own scope — this is additional, newly-found evidence
for that task, not a separate one): pass `--test-command` as a full override instead of
`--test-command-template`**, with the exact test file path(s) already known (from the real PR's
own changed-files list, or wherever Bug Hunter's spec says the test belongs) — this skips
derivation entirely at both Bug Hunter and TDD Architect, per `run_issue.py`'s own `--test-command`
docstring ("skips Bug Hunter's derivation entirely if given"):

```bash
--test-command "pytest <test file path(s), space-separated> -q"
```

`--issue-url` points at the real PR, not a fabricated issue URL — there usually isn't a separate
GitHub issue for these, same as the Tier 2 enhancement set (`docs/TIER2-VALIDATION-SET.md`:
"write realistic issue text for each [merged PR]").

**4. Review/decide** — printed by `run_issue.py` itself at the end of its run, with the real
`--session-id` filled in; don't try to guess or reconstruct this by hand:

```bash
python3 scripts/review.py show   --app-name airflow --user-id issue-<N> --session-id <printed>
python3 scripts/review.py decide --app-name airflow --user-id issue-<N> --session-id <printed> --decision approve
```

**Third real finding, same run, after approval: a published PR against `sudsk/airflow` can show
a wildly inflated diff (361 commits, 2,575 files) that has nothing to do with the real fix.**
Root cause confirmed: `sudsk/airflow`'s `main` is 449 commits behind `apache/airflow`'s `main`
(check with `git rev-list --count origin/main..upstream/main` from inside the airflow clone) — the
worktree for any issue is built from a recent `upstream` commit per the base-commit convention
above, but `publish.py` pushes the branch to `origin` (the fork) and `gh pr create` diffs it
against the fork's own stale `main`, which never received those 449 commits. The branch's own
actual commit is unaffected — confirmed via the GitHub API (`GET
/repos/sudsk/airflow/commits/<branch>`) that it's a clean, real 2-file diff; the PR UI's inflated
count is purely a display artifact of comparing against a stale base, not a leak of unrelated
changes. **No fix applied** — not worth syncing the fork or changing `publish.py`'s PR-base logic
for a demo-validation PR that's never merged — but real for any future run against this fork:
either `git fetch upstream main && git push origin upstream/main:main` to resync before a run, or
have `publish.py` pin an explicit `--base` rather than relying on `gh`'s inferred one, if a
realistic-looking PR diff ever matters (e.g. for the live Airflow-team demo). See
`docs/backlog/phase-2.md` task 35 for the full writeup.
