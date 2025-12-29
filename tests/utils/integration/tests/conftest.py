import os
import subprocess
import sys
import pytest


@pytest.fixture
def run_openwrt_test():
    def _run(target_name: str):
        role_path = os.path.abspath(f"tests/integration/targets/{target_name}/test")
        os.environ["TEST_TARGET_ROLE"] = role_path

        verbosity = os.environ.get("CLI_VERBOSITY", "")
        cmd = (
            [sys.executable, "-m", "molecule"]
            + verbosity.split()
            + ["test", "--scenario-name", "integration_test"]
        )
        proc = subprocess.run(cmd)
        if proc.returncode != 0:
            raise AssertionError(f"molecule test failed with code {proc.returncode}")

    return _run
