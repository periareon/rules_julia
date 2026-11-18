"""Unit tests for `pkg_annotation` lookup."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//julia/pkg/private:pkg.bzl", "package_annotations")

_ANY = {"patches": ["any.patch"]}
_PINNED = {"patches": ["pinned.patch"]}

def _lookup_test_impl(ctx):
    env = unittest.begin(ctx)

    # A plain name applies to every version.
    asserts.equals(env, _ANY, package_annotations({"Foo": _ANY}, "Foo", "1.2.3"))

    # A versioned key applies only to that version.
    asserts.equals(env, _PINNED, package_annotations({"Foo@1.2.3": _PINNED}, "Foo", "1.2.3"))
    asserts.equals(env, None, package_annotations({"Foo@1.2.3": _PINNED}, "Foo", "1.2.4"))

    # A versioned key wins over a plain name.
    both = {"Foo": _ANY, "Foo@1.2.3": _PINNED}
    asserts.equals(env, _PINNED, package_annotations(both, "Foo", "1.2.3"))
    asserts.equals(env, _ANY, package_annotations(both, "Foo", "2.0.0"))

    # Other packages are unaffected.
    asserts.equals(env, None, package_annotations(both, "Bar", "1.2.3"))

    return unittest.end(env)

_lookup_test = unittest.make(_lookup_test_impl)

def annotations_test_suite(name):
    """Define the test suite.

    Args:
        name (str): The name of the test suite.
    """
    unittest.suite(name, _lookup_test)
