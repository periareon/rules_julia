"""Unit tests for Julia version resolution."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//julia/pkg/private:julia_version.bzl", "resolve_julia_version")
load("//julia/private:versions.bzl", "JULIA_DEFAULT_VERSION", "JULIA_VERSIONS")

def _resolve_test_impl(ctx):
    env = unittest.begin(ctx)

    # Known versions resolve to themselves.
    asserts.equals(env, JULIA_DEFAULT_VERSION, resolve_julia_version(JULIA_DEFAULT_VERSION))

    # Unknown patch releases and bare minors resolve to the newest known patch.
    major, minor = JULIA_DEFAULT_VERSION.split(".")[:2]
    newest = sorted(
        [v for v in JULIA_VERSIONS.keys() if v.startswith("{}.{}.".format(major, minor))],
        key = lambda v: [int(p) for p in v.split(".")],
    )[-1]
    asserts.equals(env, newest, resolve_julia_version("{}.{}.999".format(major, minor)))
    asserts.equals(env, newest, resolve_julia_version("{}.{}".format(major, minor)))

    return unittest.end(env)

_resolve_test = unittest.make(_resolve_test_impl)

def julia_version_test_suite(name):
    """Define the test suite.

    Args:
        name (str): The name of the test suite.
    """
    unittest.suite(name, _resolve_test)
