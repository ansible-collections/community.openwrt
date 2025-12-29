import os


def test_target(run_openwrt_test):
    target = os.environ.get("TEST_TARGET_NAME")
    if not target:
        raise AssertionError("TEST_TARGET_NAME must be set by the test entrypoint")
    run_openwrt_test(target)
