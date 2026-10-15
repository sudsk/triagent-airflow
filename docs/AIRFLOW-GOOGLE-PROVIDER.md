# Apache Airflow `providers/google` — feasibility analysis

Detailed backing analysis for `docs/BACKLOG.md` task 24. This is the load-bearing document for
whether triagent can move beyond a single validated repo (`google/libphonenumber`) to Apache
Airflow's `providers/google` — the real subset EPAM engineers actually work on
(https://github.com/apache/airflow/tree/main/providers/google), by the user's own scoping call,
not a formal survey of alternative candidates. Written 2026-09-06, from real evidence, not
extrapolated from the libphonenumber batch alone.

## Verdict, up front

**~23% of this real, ~4-year body of work (60 real PRs) is already provable with triagent's
validated capability today, zero new work.** That reaches **~50% with a modest, ~4-8 week
investment** (validating the already-built but never-proven enhancement path), and **~68% with
one further architecture investment** (~4-8 weeks, a new routing path for mechanical migrations).
**The remaining ~31% (system-test work, needing a live cloud environment to verify) needs a
deliberately granted, sandboxed GCP project — and even once granted, a real, separate ~6-10 week
engineering workstream, not a config change, to actually use it.** None of this is a guess: every
number here is computed from real GitHub data, and every capability claim is checked against this
project's own real code, not assumed.

## Evidence base

Two real datasets, both fetched directly via the GitHub API, not sampled:

1. **100 most recent open issues** on `apache/airflow` (general queue triage — see the published
   artifact, `docs/BACKLOG.md`'s Airflow case study cross-reference).
2. **266 real closed PRs, `providers/google` label, from the 4 named EPAM engineers who work this
   area today** — MaksYermak, olegkachur-e, VladaZakharova, molcay. 255 merged, spanning October
   2021 to August 2026. This is the dataset this document is built on: a real, sustained,
   ~4-year track record, not a snapshot.

## The corrected category breakdown

The original automated classification (keyword-matched against PR titles) put 31 PRs (11.7%) in
an opaque "other" bucket. Manually reviewing all 31 titles found most of them were mis-bucketed
by the keyword matcher (titles that didn't start with "Fix"/"Add"/"Create" but were the same
shape of work) — reclassifying them gives the real, precise picture:

| Category | Count | Notes |
|---|---|---|
| System-test maintenance | 82 | unchanged from the original pass |
| Bug fix | 48 | +9 reclassified from "other" |
| Add capability/param | 41 | +5 reclassified from "other" |
| New operator/feature | 33 | +2 reclassified from "other" |
| Deprecation | 22 | +1 reclassified from "other" |
| Version bump/migration | 13 | +4 reclassified from "other" |
| Rebrand/rename | 11 | +3 reclassified from "other" |
| Refactor/cleanup | 9 | +6 reclassified from "other" |
| Revert | 3 | unchanged |
| Docs | 3 | unchanged |
| Genuinely ambiguous (title alone insufficient) | 1 | `#21091`, kept unclassified rather than guessed |

Total: 266, cross-checked twice (per-category sum, and against the original 235 + 31 reclassified
= 266). This reclassification is itself a limitation worth stating plainly: it's a manual,
title-level review, more careful than the automated keyword pass, but not a full body-text/diff
review of all 266 PRs — a handful of individual placements could shift with a deeper read.

**"System-test maintenance" is not "a bug fix that requires a system test to verify it."** It's
PRs where the system test itself is the subject of the change — its resource IDs, region pinning,
the external API/dependency version it targets, cleanup tooling, flakiness/race conditions, or
adding/removing test coverage — not a defect in the provider's actual runtime code (operator/hook/
sensor logic that ships to users). Real examples from this same dataset, fetched live: `Fix Ray
Job system test in Google provider`, `Fix the google provider dataform system test`, `Change
Dataform system test to avoid race condition and infinite execution`, `Update system test to the
latest api version of google-ads`. Several literally start with "Fix" — the classifier evidently
checks for the phrase "system test" as a higher-priority signal before falling back to generic
"Fix"/"Add" keyword matching, since what's broken is the test harness, not user-facing
functionality. This is exactly why the category sits in Tier 4, not Tier 1: the coding isn't
harder, but *verifying* any of these requires actually running the system test against live GCP
resources — the same Problem 2 (needs a live cloud environment) `docs/CAPABILITIES.md` already
names — whereas a Tier-1 bug fix validates with a local test run, the same shape as
libphonenumber's `mvn test`.

## The four tiers

| Tier | Categories | PRs | % | What it takes |
|---|---|---|---|---|
| **1 — Doable now** | Bug fix, refactor/cleanup, revert | 60 | 22.6% | Nothing — same shape as the 5 validated libphonenumber fixes |
| **2 — Doable in 4-8 weeks** | Add-param, new-feature | 74 | 27.8% | Validate the already-built enhancement path (Spec Analyst) against real historical PRs |
| **3 — Doable in 4-8 weeks, different work** | Deprecation, version-bump, rebrand | 46 | 17.3% | An operating-model assumption + real new architecture (a third Router path) |
| **4 — Sequenced: an access decision, then 6-10 weeks of execution engineering** | System-test | 82 | 30.8% | A sandboxed GCP project grant (per the user, low-friction, expected) — access is not the bottleneck; the engineering effort that follows is |
| Residual | Docs, genuinely ambiguous | 4 | 1.5% | Outside current scope, low volume |

**Tier 1 + 2 = 134/266 (50.4%)** reachable with zero new infrastructure. **Tier 1 + 2 + 3 =
180/266 (67.7%)** reachable with one additional architecture change. Tier 4 (30.8%) is not blocked
in any hard sense — the access decision itself is expected to be straightforward — but it is a
real, separate engineering effort once granted, not a config change. Addressed in full below,
since "grant the access" turned out not to be the whole story.

**A note on all the estimates below**: they assume AI-assisted development throughout (this
project has itself been built this way — e.g. Bug Prover was designed, built, and verified against
a real Gemini call in a single day, per `docs/DECISIONS.md`), and are biased toward the lower end
of what's realistic on that basis. That compression is real, but it isn't uniform: AI assistance
meaningfully speeds up *writing code once a defect is diagnosed or a design is decided* — it does
nothing to speed up *discovering what actually breaks against a real system*, or *whether an
external tool (Breeze) behaves the way it needs to*. Those are bounded by real iteration cycles
against real systems, not by coding speed. Each estimate below says explicitly which kind of work
it is.

---

## Tier 1 — doable now (60 PRs, 22.6%)

Same shape as the 5 already-validated libphonenumber fixes: narrow, mockable, logic-level
changes, verifiable without live infrastructure. Real examples from this exact dataset:
[#40664](https://github.com/apache/airflow/pull/40664) ("Fix behavior for `reattach_state`
parameter in `BigQueryInsertJobOperator`"), [#39206](https://github.com/apache/airflow/pull/39206)
("Fix `GCSObjectExistenceSensor`... deferrable and non-deferrable mode"),
[#53707](https://github.com/apache/airflow/pull/53707) (closes a real, prior community-reported
issue, reworks a real prior PR — a genuine issue-to-fix loop, exactly triagent's design). Refactor
and revert PRs (12 combined) share the same low-external-dependency profile and are folded into
this tier rather than treated separately.

No new engineering required. This is the baseline to keep validating against, the same discipline
already proven on libphonenumber.

## Tier 2 — validate the enhancement path (74 PRs, 27.8%) — the single best investment

Tracked as a real Phase 2 task: `docs/BACKLOG.md`/`docs/PLAN.md` task 35.

Triagent's architecture already has a dedicated path for this (Spec Analyst → TDD Architect, the
same convergence point the bug path uses) — it has just never been exercised against a real issue.
The entire 5-issue validation batch (`docs/PHASE1-RESULTS.md`) was bug fixes.

**The plan, with real timing per step:**
1. Pick 5-8 real, already-merged `add-param`/`new-feature` PRs from this exact 266-PR dataset as a
   validation set, and write realistic issue text for each. AI-assisted, compresses well — days,
   not weeks.
2. Run them through the pipeline as fresh issues, using each real PR's own description as the
   issue text. Expect and find real pipeline defects — the bug path found 10+ real ones during its
   own validation (`docs/PHASE1-RESULTS.md`), and there's no reason to expect this path is cleaner
   on a first real run. **This step is the real pacing item, and only partly compresses under AI
   assistance**: *discovering* what breaks is bounded by real Gemini calls and real review, not
   coding speed — but *fixing* a diagnosed defect is exactly the kind of work AI-assisted
   development speeds up (this project's own real history already shows same-day fixes once a
   root cause is found).
3. Harden Judge's review instructions specifically for this path. "Is this a reasonable new
   operator design, consistent with the codebase's existing conventions" is a different judgment
   call than "does this fix match the reported bug" — Judge's current instructions
   (`agents/builder_judge.py`) were written entirely with the bug path in mind. This is a genuinely
   new kind of review problem (design-quality judgment, not pass/fail verification) with no
   existing calibration to build from — the one piece of this tier that could run long regardless
   of tooling speed, since it's validated empirically against real examples, not written faster.

**Honest estimate: 4-8 weeks.** The lower end assumes this path behaves about as well as the bug
path's cleanest issues (a single clean attempt, no real defects found); the upper end assumes at
least one issue proves as rocky as the bug path's worst case (five attempts, six real defects). It
remains the highest-leverage single investment available regardless of where in that range it
lands: it roughly doubles triagent's addressable share of this real corpus using architecture that
already exists, not a new capability built from scratch.

## Tier 3 — deprecation/version-bump/rebrand (46 PRs, 17.3%) — a reframe, not a wall

The earlier framing ("needs external context neither Bug Hunter nor Spec Analyst has any
mechanism to read") is true only if triagent has to *autonomously discover* the external fact
(a Google policy page, a new API version, a business rebrand). But triagent's operating model is
reactive — it responds to an issue someone wrote. Every real historical PR in this bucket was
initiated by an engineer who *already knew* the external fact and then did the work. If that same
fact is stated plainly in the issue text handed to triagent — exactly how an EPAM engineer would
file an internal ticket for it, since they already know the fact — **the external-context gap
disappears**. Real examples: [#67113](https://github.com/apache/airflow/pull/67113) cites Google's
own external policy page with a real cited restriction date;
[#66415](https://github.com/apache/airflow/pull/66415) (the "Sovereign Cloud" rename) has almost
no PR body at all — the real reason lives entirely outside the codebase, but an issue that simply
states "Google renamed TPC to Sovereign Cloud, update all references" removes the need for
triagent to discover that fact itself.

**The real, remaining gap: TDD Architect's "write a failing test first" doesn't fit these tasks.**
There's no natural failing test for "the string TPC should now read Sovereign Cloud" or "the
default API version should be v18." Recognizing this as a different task shape needs real, new
architecture, not a small tweak to an existing path:

1. **A new Router category** ("mechanical migration"), classifying an issue into it correctly
   rather than force-fitting the existing bug/enhancement binary. New classification logic, new
   test cases. AI-assisted, compresses well once the category is defined — days to a week.
2. **A new verification paradigm**: "existing regression suite still passes at the new
   version/name" plus a completeness check (e.g., a grep confirms zero remaining old-string
   occurrences), replacing TDD Architect's test-first step for this path specifically. Deciding
   *what counts as sufficient verification here* is real design thinking, not fast to shortcut —
   but implementing it, once decided, is ordinary agent-instruction/tooling work that compresses
   well under AI-assisted development.
3. **Validation against 3-5 real historical examples from this bucket**, same discipline as
   Tier 2 — expect real surprises. This step doesn't compress as much: discovering what actually
   breaks against real Airflow code is bounded by real iteration, not coding speed.

**Honest estimate: 4-8 weeks.** Genuinely new architecture (a third path through the graph), not
a tweak — comparable in scope to Tier 2, and with less to anchor the estimate against, since
nothing like it has been attempted in this project yet.

## Tier 4 — system-test (82 PRs, 30.8%) — two separate problems, not one

### 4a. The access decision

Genuine Problem 2 in `docs/CAPABILITIES.md`'s own framework: a real Airflow `system_test` needs an
actual live GCP project, real credentials, sometimes real cost. No amount of triagent engineering
closes this on its own — it needs a deliberate, granted, sandboxed GCP project. Per the user's own
call (2026-09-06), this is not a hard constraint: access can be granted. **But granting access is
necessary, not sufficient** — see below.

### 4b. The engineering workstream, once access exists

Assume the sandboxed project and credentials are handed over tomorrow. Six real pieces of work
stand between that and an agent that can actually run a system test:

| # | Gap | Risk | Est. |
|---|---|---|---|
| 1 | **Breeze itself must run inside the sandbox.** ~~High-risk, 2-4 weeks~~ — **resolved for real, 2026-09-24**: task 42 (`docs/BACKLOG.md`) closed with a real BigQuery system test run **17/18 tasks passing** against live GCP through the full chain — Cloud Run Sandbox, injected credentials, `pytest --system`, `dag.test()` — no mocks, real dataset/table create-and-delete round-trips. Real tooling obstacles along the way (a `uv`-based provider-dependency regenerator scanning the whole monorepo, a stale pre-monorepo path convention in `deprecations_ignore.yml`, cross-provider test-tree imports) were each found and fixed with small, targeted, root-cause patches, not broad workarounds — documented in full in task 42. The one unresolved piece is OpenLineage lineage-event verification specifically (a real, understood, but distinct root cause — a test-only transport class needs registering inside Airflow's own task-runner subprocess, not just pytest's process — deliberately not built, scoped out as secondary to this gap). | **Low — real execution mechanism confirmed working end-to-end** | Done; breadth across the other 81 real cases still unconfirmed |
| 2 | **Credential injection.** ~~Low — well-precedented, 3-5 days~~ — **confirmed real and solved, 2026-09-20** (`docs/BACKLOG.md` task 42): sandboxes genuinely can't reach the metadata server (confirmed via a real `DefaultCredentialsError`, not assumed), so a short-lived token injected from the non-sandboxed caller's own ADC is the real, working pattern — verified end-to-end against a real BigQuery API call. Airflow's own hooks needed a slight variant (a caller-generated, single-request-scoped key file, since `google.auth.default()` — which Airflow calls internally — needs a file path or the metadata server, not a bare token) — still real, still short-lived, still no standing credential beyond one request. | Done — real, working pattern confirmed | Done |
| 3 | **Resource lifecycle management.** Airflow's own maintainers already solved half of this: [#41788](https://github.com/apache/airflow/pull/41788) "Add ENV_ID for job_name in Cloud Run system tests" shows the real test harness already supports per-run unique resource naming. Triagent needs to use that convention correctly, plus build a reaper for resources left behind by a crashed run — standard SRE tooling. Confirmed 2026-09-16: `providers/google/tests/system/google/README.md` documents exactly two required env vars, `SYSTEM_TESTS_GCP_PROJECT` and `SYSTEM_TESTS_ENV_ID` — real, simple, not speculative. | Low-medium — the hard half is already solved upstream | ~1 week |
| 4 | **A verification harness for DAG-based, often-async tests.** ~~Medium-high~~ — **the "best case" named here is now confirmed real, 2026-09-16**: Airflow's own `contributing-docs/testing/system_tests.rst` documents `pytest --system <path>` as a direct, non-interactive command, and states no scheduler/webserver is needed "for direct pytest execution without an executor." This is close to the `mvn test` shape after all, for the cases that don't need an executor. | Medium — real path exists, per-test executor need still unconfirmed | 1-2 weeks |
| 5 | **Cost/round-cap economics.** A real system test takes real minutes and real dollars, nothing like libphonenumber's near-instant `mvn test`. Builder⇄Judge's ≤2-round loop was tuned against that fast, cheap profile — this tier needs its own separate budget/limit. **Sharper 2026-09-16**: the real per-service provisioning times vary enormously (see 4c) — a flat round-cap/timeout doesn't fit a set that spans "submit a Dataflow job" to "stand up a Cloud Composer environment." | Low-medium — config and policy, but needs per-service tiers, not one number | 3-5 days |
| 6 | **Security model hardening.** Today's sandbox isolation stops a hostile/buggy agent from escaping the local filesystem/subprocess boundary. Real, live cloud credentials raise the stakes of any bug: least-privilege IAM, hard resource quotas, spend alerts, a genuinely disposable project — not the production or shared one. | Low — standard cloud-security configuration, can run in parallel with the code work | ~1 week |

Items 2, 3, 5, 6 are well-precedented, mostly implementation of known patterns, and can run in
parallel — under two weeks combined critical path. **Item 1 narrowed materially on 2026-09-16
(see 4c) and item 4's best case is now confirmed, not hypothetical** — real risk remains in
*breadth* (does the direct path cover most of the 82 real cases) rather than *existence*, which is
a smaller, more bounded question than this document originally posed.

### 4c. Real findings, 2026-09-16 — the framing was two problems bigger, and one problem smaller

Pulled the real 82-PR Tier 4 list live (GitHub search API, all 4 named engineers, `"system test"
in:title`, merged — 18+13+46+5 = 82, exactly matching the count above) and checked Airflow's own
current docs, not assumptions carried over from the original analysis.

**Smaller than assumed: Breeze/Docker-in-Docker is not actually required.**
`contributing-docs/testing/system_tests.rst` documents three ways to run a system test, not one:
Breeze (the convenience wrapper, "makes sure... all additional required services are started"),
**direct pytest** — `pytest --system providers/google/tests/system/google/cloud/bigquery/
example_bigquery_queries.py`, which "works outside Docker if you have dependencies installed" —
and importing the DAG into a real running Airflow instance. For direct pytest "without an
executor," no scheduler/webserver is needed at all. `providers/google/tests/system/google/
README.md` confirms the real setup is just two env vars (`SYSTEM_TESTS_GCP_PROJECT`,
`SYSTEM_TESTS_ENV_ID`) plus `gcloud` configured — much closer to `mvn test`'s shape than the
original "Docker-Compose-in-Docker" framing assumed. **Not fully resolved**: whether every one of
the 82 real cases works via this direct path, or whether some genuinely depend on the "additional
services" Breeze provides (a local metastore, a message broker, etc.) — that's the real remaining
question, narrower than "does Breeze even work headlessly at all."

**Bigger than assumed: there is no single "execution framework" — the real corpus is
heterogeneous across 20+ distinct live services, two of which aren't even GCP-billed.** Categorized
the real 82 titles by which system they touch: **Dataflow/Apache Beam** (7), **Vertex AI** —
datasets, AutoML, feature store, image training (10), **Dataproc** — incl. SparkR, Metastore (5),
**Dataform** (3), **Cloud Composer** — a managed Airflow environment as the system under test,
itself (3), **Google Workspace** — Sheets, Calendar, Drive (3), **BigQuery**, **Bigtable**,
**Datastore**, **Cloud Run**, **Cloud Functions**, **GCE**, **GKE + Kueue**, **Ray**, **Managed
Kafka**, **ML Engine** (1 each), plus generic xcom/ORM/AF2-compatibility and resource-cleanup-
tooling PRs not tied to any one service. **Two real outliers**: `google-ads` and `DV360` (Display &
Video 360) system tests hit Google Ads/Marketing Platform APIs — entirely separate products with
their own developer-token/account access, **not covered by a "sandboxed GCP project" grant at
all**. This is a real, previously-unflagged access gap distinct from Problem 2. Several services
also carry genuinely long real provisioning times that a flat round-cap won't fit uniformly —
Cloud Composer environment creation and Vertex AI training/AutoML jobs run tens of minutes to
hours, materially different from a Dataflow job submission or a BigQuery query.

**Also confirmed**: there's no central permissions list. `README.md` explicitly punts "specific
permissions" to individual test docstrings, per-provider, per-service — matching the heterogeneity
finding above. Discovering the real IAM/API-enablement needs for a meaningful subset of the 82
cases is itself real, per-test investigation work, not a one-time setup task.

**Stronger evidence than doc prose, found checking a real example rather than trusting the docs
alone**: fetched a real system-test file (`providers/google/tests/system/google/cloud/bigquery/
example_bigquery_queries.py`) and — because the first read of it looked like it contradicted the
"no executor needed" claim above (a `with DAG(...) as dag:` block reads like a deployment
requirement) — traced `get_test_run(dag)` to its real source
(`devel-common/src/tests_common/test_utils/system_tests.py`). It returns a `@pytest.mark.system`
test that calls Airflow's own `dag.test(use_executor=os.environ.get(
"_AIRFLOW__SYSTEM_TEST_USE_EXECUTOR") == "1", ...)` — which runs the whole DAG **in-process**, no
separate scheduler/webserver/executor daemon, unless that env var is explicitly set (off by
default). This is stronger than the earlier contributing-docs citation — a verified real function,
not a claim about intended usage — and it directly confirms `docs/BACKLOG.md` task 42's premise:
the common case really is "install deps, set two env vars, run pytest," no Docker-in-Docker, no
Breeze. Real remaining unknown, unchanged: whether every one of the 82 cases uses this same
`get_test_run` pattern, or whether some opt into `use_executor=True` (a real, heavier path this
same file supports) for reasons not yet surveyed.

**Net effect on this tier's own numbers**: item 1's risk drops (a real non-Docker path exists),
item 4's best case is confirmed, item 5 needs per-service tiers not a flat cap, and there's a new,
real, previously-missing line item — non-GCP credential access for `google-ads`/`DV360` cases —
that the original 6-item gap table didn't have room for. The 6-10 week total estimate isn't
revised here pending the still-real "breadth" question in item 1, but the shape of the risk has
changed materially enough to be worth a fresh read before Track 3 spike planning, not just an
incremental note.

### Recommended de-risking step

This project already has a stated discipline for exactly this situation: spike first, build
second (Task 9's real model-API spike before any agent was built, `docs/DECISIONS.md`). Apply the
same rule here. **Before committing the full plan, run a 1-2 week spike answering a narrower
question than originally posed**: for a small, deliberately diverse sample across the 20+ real
services named in 4c (not just one easy case), does `pytest --system <path>` reach a clean
pass/fail against a real sandboxed GCP project, and for the `google-ads`/`DV360` cases
specifically, what does obtaining that separate access even look like? That answer is the
difference between a confident estimate and real, open-ended risk.

**Where this actually runs, concretely, as of 2026-09-17**: not GKE, and not the originally-feared
Docker-in-Docker — `docs/BACKLOG.md` task 43 found and confirmed a real Cloud Run Sandboxes
recipe (`sandbox do --write --export-tar=...`/`--import-tar=...`) that already handles both real
tool execution and cross-call persistence for this project's simpler libphonenumber case. Task 42
is the concrete next step: the same recipe, with Python/Airflow/the google provider package baked
into the image instead of `git`, run against one cheap real `pytest --system` case first (a
BigQuery or Dataflow example — not Vertex AI training or Cloud Composer, whose real provisioning
times run tens of minutes to hours). That single run is this section's spike, scoped small on
purpose; only after it succeeds does "a small, deliberately diverse sample across the 20+ real
services" become the right next size to attempt.

## Can all three (Tier 2, Tier 3, Tier 4) target the same Phase 2?

Yes — architecturally, all three are independent. Tier 2 touches Spec Analyst/Judge instructions;
Tier 3 touches Router (a new category) and a new verification paradigm replacing TDD Architect for
that path; Tier 4 touches the sandbox/execution layer (credentials, Breeze, resource lifecycle).
None of the three overlap in the code they change, so none of them technically blocks another.

**The real constraint is staffing, not architecture.** With three genuinely separate
workstreams/people, the critical path is the *longest* single tier — Tier 4's spike-plus-build —
so Phase 2 lands around **2-3 months**. With the same one or two people working through all three
sequentially, it's additive: roughly **15-28 weeks (3.5-7 months)**.

**One real gate to keep, not remove**: Tier 4's spike should still come first and act as a
checkpoint before committing its full 6-10 week build — 2026-09-16's findings (4c) mean the
question it's actually checking is narrower now (does the real `pytest --system` path cover most
of the 82 real, heterogeneous cases, and what does `google-ads`/`DV360` access even look like) but
it's still a real go/no-go gate, not a formality. It doesn't touch Tier 2 or Tier 3 at all, so
those two should proceed regardless of what the spike finds; there's no reason to gate them on
Tier 4's outcome.

**Recommendation**: run Tier 2's enhancement-path validation, Tier 3's mechanical-migration
architecture, and Tier 4's spike in parallel from day one of Phase 2, with different
people/workstreams — reaching ~68% of the real corpus addressable in roughly 2-3 months of
wall-clock time, not 6, provided Tier 4's spike doesn't surface a fundamental blocker (in which
case Tier 4's remaining build gets re-scoped, not Tier 2 or Tier 3).

---

## Access dependencies (verified against real primary sources)

- **No signed CLA required** for a regular PR contributor on this real ASF project — checked
  directly against `contributing-docs/01_roles_in_airflow_project.rst`. CLA is only mentioned for
  elevated roles (e.g. Security Team). Consistent with real evidence: these 4 engineers have 255
  real merged PRs with no indication of any special access requirement beyond a standard GitHub
  account.
- **EPAM's existing standing is real and substantial** — 255 real merged PRs from named EPAM
  engineers is itself the answer to "does EPAM have an existing relationship with this project."
- **A real, concrete requirement, found not assumed**: Apache Airflow has an explicit Gen-AI
  contribution policy (`contributing-docs/05_pull_requests.rst`, quoted verbatim, fetched
  directly): *"State in your PR description that you have used Gen-AI tools to assist in creating
  the PR."* Enforcement risk is real too — maintainers may close PRs (and future contributions)
  from a non-complying contributor. The policy's substantive requirements (human review before
  submission, final responsibility resting with the human, no blind trust of generated code)
  already match triagent's human-approval-gate design almost exactly — but the disclosure line
  itself is a genuine, not-yet-built code change: `agents/publish.py` needs to add this statement
  to the PR body for an Airflow target, something libphonenumber's real PRs never needed.

## What would change this analysis

- A full body-text/diff review of all 266 PRs (this analysis is title-level for the bulk of them,
  with real PR bodies checked only for a representative cited sample) could shift a handful of
  individual category placements, though unlikely to change the tier totals materially.
- The Breeze headless-execution spike (Tier 4b) is the single highest-value next data point —
  it resolves the largest remaining uncertainty in this entire document.
- If EPAM's actual near-term ask is narrower than "all of `providers/google`" (e.g., one specific
  sub-area), this tiering should be re-run against that narrower real PR history rather than
  assumed to generalize.
