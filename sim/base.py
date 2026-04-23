import os
import subprocess
import json
from pathlib import Path
from cocotb_tools.runner import get_runner

RTL_DIRS = (
    "/foss/designs/obi-spi/rtl",
)
LANGUAGE = os.getenv("HDL_TOPLEVEL_LANG", "verilog").lower().strip()
WAVES = os.getenv("WAVES", default=False)
ASSERTIONS = os.getenv("ASSERTIONS", default=True)

def get_rtl_files():
    rtl_files = []
    sources = subprocess.run(
        "bender sources --flatten", 
        capture_output=True, 
        shell=True
    )
    sources = json.loads(sources.stdout)
    for src_pkg in sources:
        for file in src_pkg['files']:
            rtl_files.append(Path(file))
    return rtl_files

def get_test_runner(hdl_top):
    sim = os.getenv("SIM", default="verilator")
    build_args = ["-Wno-fatal", "--no-stop-fail"]
    if WAVES:
        build_args += ["--trace-fst"]
    if ASSERTIONS:
        build_args += [f"-DASSERTIONS"]
    runner = get_runner(sim)
    runner.build(
        sources=get_rtl_files(),
        includes=["/rvj1/rtl/inc"],
        build_args=build_args,
        hdl_toplevel=hdl_top,
        always=True,
        waves=False,
    )
    return runner
