"""Cloud Run Sandbox dispatcher -- Task 45 (docs/BACKLOG.md). Layout B (transitional)
apache/airflow sandbox image, built 2026-10-11 after layout B's fresh-install-every-round
approach (the generic triagent-dispatcher-airflow service) proved fragile: a hatchling/editables
limitation on local editable installs, then a pip bare-directory-name ambiguity, then a ~1GB
per-round export tar from reinstalling every third-party dependency on every call. Same fix
layout C already proved: third-party dependencies pinned and baked into the image once;
the repo's own packages (core airflow/, task_sdk/, tests_common/, providers/google/) are NOT
installed at all -- they're loaded via PYTHONPATH from the checked-out source, so the sandbox
always tests the code the pipeline actually edited, and the per-round overlay stays small.

requirements.txt is a real `uv`-resolved freeze of this era's third-party dependencies (no
uv.lock/constraints file exists in-tree for this era -- generated once via a local, non-sandbox
`uv pip install` resolution against this worktree's pyproject files, then filtered to exclude
the local workspace package names). See docs/TIER2-VALIDATION-SET.md for the real history.

Run locally (no --sandbox-launcher, `sandbox` won't exist, and no real bucket -- for
syntax-checking only): uvicorn dispatcher.main:app --reload --port 8081
"""

from __future__ import annotations

import logging
import os
import shlex
import subprocess
import tempfile
import uuid

from fastapi import FastAPI
from google.cloud import storage
from pydantic import BaseModel

logger = logging.getLogger("dispatcher")

app = FastAPI(title="triagent cloud run sandbox dispatcher")

DEFAULT_TIMEOUT_SECONDS = 300.0

# The image's own ENV lines don't reach commands run inside a sandbox (confirmed real for layout
# C, 2026-10-05), so the same values are passed on every call here. /tmp is first so Python
# auto-imports /tmp/sitecustomize.py (the setup script writes it), which globs every provider's
# src dir recursively at runtime -- same real fix layout C needed (providers nest one level
# deeper in places, e.g. providers/common/sql/src). Unlike layout C, the core `airflow` package
# here is the old monolithic layout (root of the repo, not airflow-core/src), and task_sdk/
# tests_common sit at the repo root too (tests_common has no src/ subdir at all) -- confirmed
# directly against the #45835 base-commit worktree, 2026-10-10/11.
SANDBOX_DEFAULT_ENV = {
    "PYTHONPATH": ":".join([
        "/tmp",
        "/root/repo",
        "/root/repo/task_sdk/src",
    ]),
    "AIRFLOW_HOME": "/tmp/airflow",
    "AIRFLOW__LOGGING__BASE_LOG_FOLDER": "/tmp/airflow/logs",
    "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    # tests_common/_internals/capture_warnings.py defaults to a relative "warnings.txt" (written
    # under cwd, /root/repo) when this isn't set -- /root/repo isn't writable in this image.
    # Confirmed real, 2026-10-11: PermissionError during collection, not test failures.
    "CAPTURE_WARNINGS_OUTPUT": "/tmp/warnings.txt",
}

# Required, not defaulted -- a dispatcher that silently no-ops tar exchange because the bucket
# wasn't configured would fail confusingly deep inside a sandbox call, not here at startup.
GCS_BUCKET = os.environ["TRIAGENT_SANDBOX_GCS_BUCKET"]
_storage_client = storage.Client()
_bucket = _storage_client.bucket(GCS_BUCKET)


class DoRequest(BaseModel):
    command: list[str]
    cwd: str = "/root/repo"
    write: bool = False
    allow_egress: bool = False
    env: dict[str, str] = {}
    export: bool = False
    import_tar_gcs: str | None = None  # a bare object name within GCS_BUCKET, not a full gs:// URI
    timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS
    # Fixed, triagent-controlled setup step (e.g. writing sitecustomize.py), run before `command`
    # in the same sandbox call. Never agent-composed, so it bypasses the agent-side shell-operator
    # guard by design -- the guard exists for agent-authored commands, not this.
    setup_command: list[str] | None = None


class DoResponse(BaseModel):
    stdout: str
    stderr: str
    returncode: int
    export_tar_gcs: str | None = None  # a bare object name within GCS_BUCKET


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/do", response_model=DoResponse)
async def do(req: DoRequest) -> DoResponse:
    """Restores req.import_tar_gcs (an object in GCS_BUCKET, if given) into a fresh sandbox, runs
    req.command there (in req.cwd -- wrapped in `sh -c 'cd ... && exec ...'` since `sandbox do`
    itself has no --cwd flag, per Task 42/43's own confirmed real invocation shape), optionally
    exports the resulting writable overlay back out to a fresh GCS object. Never raises on the
    sandboxed command's own failure or timeout -- both come back as a normal nonzero returncode,
    matching agents/sandbox/process.py's local run_subprocess contract, so a calling agent can
    react instead of the whole run crashing."""
    with tempfile.TemporaryDirectory(prefix="triagent-do-", dir="/tmp") as workdir:
        args = ["sandbox", "do"]
        if req.write:
            args.append("--write")
        if req.allow_egress:
            args.append("--allow-egress")
        for k, v in {**SANDBOX_DEFAULT_ENV, **req.env}.items():
            args += ["--env", f"{k}={v}"]

        import_tar_path = os.path.join(workdir, "import.tar")
        if req.import_tar_gcs:
            _bucket.blob(req.import_tar_gcs).download_to_filename(import_tar_path)
            args.append(f"--import-tar={import_tar_path}")

        export_tar_path = os.path.join(workdir, "export.tar")
        if req.export:
            args.append(f"--export-tar={export_tar_path}")

        steps = [f"cd {shlex.quote(req.cwd)}"]
        if req.setup_command:
            steps.append(shlex.join(req.setup_command))
        steps.append(f"exec {shlex.join(req.command)}")
        args += ["--", "/bin/sh", "-c", " && ".join(steps)]

        try:
            result = subprocess.run(
                args, capture_output=True, text=True, errors="replace", timeout=req.timeout_seconds
            )
        except subprocess.TimeoutExpired:
            return DoResponse(
                stdout="", stderr=f"command timed out after {req.timeout_seconds}s", returncode=-1
            )
        except OSError as e:
            return DoResponse(stdout="", stderr=f"could not invoke sandbox launcher: {e}", returncode=-1)

        export_tar_object = None
        if req.export and os.path.exists(export_tar_path):
            export_tar_object = f"exports/{uuid.uuid4().hex}.tar"
            _bucket.blob(export_tar_object).upload_from_filename(export_tar_path)

        return DoResponse(
            stdout=result.stdout,
            stderr=result.stderr,
            returncode=result.returncode,
            export_tar_gcs=export_tar_object,
        )
