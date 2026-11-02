"""Run portable peripheral simulations in an isolated temporary working directory."""
from dataclasses import dataclass
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile
import time

from generate_fixtures import generate

ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class Case:
    name: str
    top: str
    files: tuple[str, ...]
    marker: str
    parameters: tuple[str, ...] = ()
    defines: tuple[str, ...] = ()
    compile_must_fail: bool = False


def cases() -> list[Case]:
    init = ("sim/tb_ov5640_init.sv", "sim/ov5640_sccb_model.sv",
            "src/rtl/sccb16_master.v", "src/rtl/ov5640_init.v")
    capture = ("src/rtl/ov5640_capture.v", "src/rtl/dvp_rgb565_rx.v",
               "src/rtl/async_event_fifo.v", "src/rtl/reset_sync.v")
    result = [Case(f"init_mode_{mode}", "tb_ov5640_init", init, "OV5640_INIT_PASS",
                   (f"tb_ov5640_init.MODE={mode}",)) for mode in range(7)]
    result += [
        Case("fifo", "tb_async_event_fifo", ("sim/tb_async_event_fifo.sv", "src/rtl/async_event_fifo.v"), "ASYNC_EVENT_FIFO_PASS"),
        Case("prefetch", "tb_camera_frame_prefetch", ("sim/tb_camera_frame_prefetch.sv", "src/rtl/camera_frame_prefetch.v", "src/rtl/packed_bram.v"), "CAMERA_PREFETCH_PASS"),
        Case("capture", "tb_ov5640_capture", ("sim/tb_ov5640_capture.sv",) + capture, "OV5640_CAPTURE_PASS"),
        Case("configured_dvp", "tb_ov5640_configured_dvp", ("sim/tb_ov5640_configured_dvp.sv",) + init[1:] + capture, "OV5640_CONFIGURED_DVP_PASS"),
        Case("roi", "tb_public_roi", ("sim/tb_public_roi.sv", "src/rtl/roi_gray48.v"), "PUBLIC_ROI_PASS"),
        Case("loader", "tb_public_loader", ("sim/tb_public_loader.sv", "src/rtl/gray_frame_loader.v"), "PUBLIC_LOADER_PASS"),
        Case("controls", "tb_public_controls", ("sim/tb_public_controls.sv", "src/rtl/photo_controls.v"), "PUBLIC_CONTROLS_PASS"),
        Case("formatter", "tb_public_formatter", ("sim/tb_public_formatter.sv", "src/rtl/photo_formatter.v"), "PUBLIC_FORMATTER_PASS"),
        Case("publication", "tb_public_publication", ("sim/tb_public_publication.sv", "src/rtl/c1_dashboard_osd.v", "src/rtl/photo_formatter.v", "src/rtl/dashboard_metrics.v"), "PUBLIC_PUBLICATION_PASS"),
    ]
    pipeline_files = tuple(f"src/rtl/{name}.v" for name in (
        "photo_overlap_pipeline", "photo_stream_consumer", "camera_frame_prefetch",
        "packed_bram", "reset_sync", "roi_gray48", "gray_frame_loader",
        "dashboard_timing", "frame_buffer_cdc"))
    result.append(Case("pipeline", "tb_public_pipeline",
                       ("sim/tb_public_pipeline.sv", "sim/inference_core_interface_stub.sv") + pipeline_files,
                       "PUBLIC_PIPELINE_PASS", defines=("PUBLIC_PERIPHERAL_TEST",)))
    result += [
        Case("guard_no_test_define", "inference_core", ("sim/inference_core_interface_stub.sv",),
             "PRIVATE_CORE_REQUIRED__TEST_DOUBLE_IS_NOT_A_CORE", compile_must_fail=True),
        Case("guard_synthesis", "inference_core", ("sim/inference_core_interface_stub.sv",),
             "PRIVATE_CORE_REQUIRED__TEST_DOUBLE_MUST_NOT_BE_SYNTHESIZED",
             defines=("PUBLIC_PERIPHERAL_TEST", "SYNTHESIS"), compile_must_fail=True),
    ]
    return result


def run(command: list[str], cwd: Path, timeout: int, expect_failure: bool = False) -> str:
    completed = subprocess.run(command, cwd=cwd, capture_output=True, text=True,
                               encoding="utf-8", errors="replace", timeout=timeout)
    output = completed.stdout + completed.stderr
    if bool(completed.returncode) != expect_failure:
        raise RuntimeError(f"Command failed ({completed.returncode}): {command[0]}\n{output[-6000:]}")
    if not expect_failure and any(message in output for message in ("ERROR:", "FATAL:", "Unable to open", "Not enough words")):
        raise RuntimeError(output[-6000:])
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", action="append", help="Run named cases only; may be repeated")
    parser.add_argument("--timeout", type=int, default=180, help="Timeout in seconds per command")
    args = parser.parse_args()
    for tool in ("iverilog", "vvp"):
        if shutil.which(tool) is None:
            parser.error(f"{tool} is missing; install Icarus Verilog and add its bin directory to PATH")
    selected = [case for case in cases() if not args.case or case.name in args.case]
    unknown = set(args.case or ()) - {case.name for case in cases()}
    if unknown:
        parser.error(f"Unknown cases: {', '.join(sorted(unknown))}")
    failures = []
    with tempfile.TemporaryDirectory(prefix="ov5640-peripherals-") as temporary:
        work = Path(temporary)
        generate(work)
        for path in (ROOT / "src/assets").rglob("*.mem"):
            target = work / path.name
            if target.exists():
                raise RuntimeError(f"Duplicate fixture name: {path.name}")
            shutil.copyfile(path, target)
        for case in selected:
            started = time.monotonic()
            try:
                artifact = work / f"{case.name}.vvp"
                command = ["iverilog", "-g2012", "-I", str(ROOT / "src/rtl"), "-s", case.top, "-o", str(artifact)]
                for parameter in case.parameters:
                    command += ["-P", parameter]
                command += [f"-D{define}" for define in case.defines]
                command += [str(ROOT / name) for name in case.files]
                output = run(command, work, args.timeout, expect_failure=case.compile_must_fail)
                if not case.compile_must_fail:
                    output = run(["vvp", str(artifact)], work, args.timeout)
                if case.marker not in output:
                    raise RuntimeError(f"Missing success marker {case.marker}\n{output[-2000:]}")
                print(f"PASS {case.name} ({time.monotonic() - started:.1f}s)", flush=True)
            except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
                failures.append(case.name)
                print(f"FAIL {case.name}: {error}", flush=True)
    print(f"RESULT {len(selected) - len(failures)}/{len(selected)} passed; private core not used", flush=True)
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
