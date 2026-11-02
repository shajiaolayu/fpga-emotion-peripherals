"""Check an explicit public file manifest and all reachable Git history before publishing."""
from pathlib import Path, PurePosixPath
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = "release-manifest.json"
IGNORED_DIRECTORIES = {".git", "__pycache__", ".build"}
PROHIBITED_EXTENSIONS = {
    ".bit", ".bin", ".dcp", ".edf", ".edn", ".ngc", ".zip", ".7z", ".tar",
    ".gz", ".xpr", ".vvp", ".vcd", ".fst", ".pyc", ".log", ".jou",
    ".pt", ".pth", ".onnx", ".npy", ".npz", ".safetensors",
}
PUBLIC_MEM = {
    "src/assets/confidence/confidence_exp.mem",
    "src/assets/photo_dashboard/c1_static_map.mem",
    "src/assets/photo_dashboard/c1_static_masks.mem",
    "src/assets/photo_dashboard/class_aa.mem",
    "src/assets/photo_dashboard/glyph_rows.mem",
    "src/assets/photo_dashboard/percent_aa.mem",
}
TOKEN_PATTERNS = (
    re.compile(rb"gh[pousr]_[A-Za-z0-9]{20,}"),
    re.compile(rb"github_pat_[A-Za-z0-9_]{20,}"),
    re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(rb"(?i)[A-Z]:[\\/]+(?:Users[\\/]|AAA_ts_D[\\/])"),
)


def validate_name(name: str) -> None:
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or "\\" in name:
        raise ValueError(f"Invalid public path: {name}")
    lowered = name.lower()
    if any(part.lower() in {"engine", "optimized_weights", "generated_engine", "reports", "output"}
           for part in path.parts):
        raise ValueError(f"Private directory is not publishable: {name}")
    if path.suffix.lower() in PROHIBITED_EXTENSIONS:
        raise ValueError(f"Prohibited artifact: {name}")
    if path.name.lower() in {"optimized_weight_rom.v", "inference_core.v", "source_manifest.json",
                             "delivery_sha256.json", "deployment.json", "tb_trial_core.v"}:
        raise ValueError(f"Private source or original manifest: {name}")
    if path.suffix.lower() == ".mem" and name not in PUBLIC_MEM:
        raise ValueError(f"Memory initialization is not explicitly public: {name}")
    if ".runs" in lowered or ".cache" in lowered or ".sim/" in lowered or ".xil/" in lowered:
        raise ValueError(f"Build cache is not publishable: {name}")


def validate_content(name: str, content: bytes) -> None:
    if b"\x00" in content:
        raise ValueError(f"Unexpected binary file: {name}")
    for pattern in TOKEN_PATTERNS:
        if pattern.search(content):
            raise ValueError(f"Credential or private workstation path detected: {name}")
    if name.endswith((".v", ".sv")) and re.search(rb"\bmodule\s+inference_core\b", content):
        if name != "sim/inference_core_interface_stub.sv":
            raise ValueError(f"Unexpected inference implementation: {name}")
        if any(marker not in content for marker in
               (b"SIMULATION TEST DOUBLE ONLY", b"`ifndef PUBLIC_PERIPHERAL_TEST", b"`ifdef SYNTHESIS")):
            raise ValueError("Test double must retain both hardware-exclusion guards")


def git(*arguments: str) -> bytes:
    return subprocess.check_output(["git", *arguments], cwd=ROOT, stderr=subprocess.PIPE)


def audit_history(allowed: set[str]) -> tuple[int, int]:
    # A source ZIP has no Git metadata; the working tree check still applies.
    if not (ROOT / ".git").exists():
        return 0, 0
    if git("rev-parse", "--is-shallow-repository").strip() == b"true":
        raise ValueError("Fetch full history before auditing: git fetch --unshallow")
    refs = git("for-each-ref", "--format=%(refname)").splitlines()
    if not refs:
        return 0, 0
    commits = git("rev-list", "--all").decode("ascii").splitlines()
    blobs: dict[str, bytes] = {}
    for commit in commits:
        for entry in git("ls-tree", "-r", "-z", commit).split(b"\0"):
            if not entry:
                continue
            metadata, raw_name = entry.split(b"\t", 1)
            mode, kind, object_id = metadata.split()
            name = raw_name.decode("utf-8")
            if kind != b"blob" or mode not in {b"100644", b"100755"}:
                raise ValueError(f"Symlink or submodule is not allowed in public history: {name}")
            if name not in allowed:
                raise ValueError(f"Historical file is outside the reviewed manifest: {name}")
            validate_name(name)
            key = object_id.decode("ascii")
            if key not in blobs:
                blobs[key] = git("cat-file", "blob", key)
            validate_content(name, blobs[key])
    return len(commits), len(blobs)


def main() -> int:
    try:
        manifest = json.loads((ROOT / MANIFEST).read_text(encoding="utf-8"))
        entries = manifest["files"]
        allowed = set(entries) | {MANIFEST}
        actual = set()
        for path in ROOT.rglob("*"):
            relative = path.relative_to(ROOT)
            if set(relative.parts) & IGNORED_DIRECTORIES:
                continue
            if path.is_symlink():
                raise ValueError(f"Symlink is not publishable: {relative.as_posix()}")
            if path.is_file():
                actual.add(relative.as_posix())
        if actual != allowed:
            raise ValueError(f"Manifest mismatch; extra={sorted(actual - allowed)} missing={sorted(allowed - actual)}")
        for name in sorted(actual):
            validate_name(name)
            content = (ROOT / name).read_bytes()
            validate_content(name, content)
            if name != MANIFEST and hashlib.sha256(content).hexdigest() != entries[name]["sha256"]:
                raise ValueError(f"Content changed after review: {name}")
        commits, blobs = audit_history(allowed)
        print(f"PUBLIC_RELEASE_AUDIT_PASS files={len(actual)} commits={commits} historical_blobs={blobs}")
        return 0
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print(f"PUBLIC_RELEASE_AUDIT_FAIL: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
