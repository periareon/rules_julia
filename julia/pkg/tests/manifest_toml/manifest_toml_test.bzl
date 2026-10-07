"""Unit tests for the Starlark `Manifest.toml` parser."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//julia/pkg/private:manifest_toml.bzl", "parse_manifest_toml")

_MANIFEST = """\
# This file is machine-generated - editing it directly is not advised

julia_version = "1.12.5"
manifest_format = "2.0"
project_hash = "f847120bcaa82ee658f012893bb6f1471266f52d"

[[deps.CommonMark]]
deps = ["PrecompileTools"]
git-tree-sha1 = "351d6f4eaf273b753001b2de4dffb8279b100769"
uuid = "a80b9123-70ca-4bc0-993e-6e3bcb318db6"
version = "0.9.1"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"
version = "1.11.0"

[[deps.Glob]]
git-tree-sha1 = "97285bbd5230dd766e9ef6749b80fc617126d496"
uuid = "c27321d9-0574-5035-807b-f59d2c89b15c"
version = "1.3.1"

[[deps.JuliaFormatter]]
deps = ["CommonMark", "Glob", "JuliaSyntax", "PrecompileTools", "TOML"]
git-tree-sha1 = "ca9470360f51697fc1bde747760b2d99936619ea"
uuid = "98e50ef6-434e-11e9-1051-2b60c6c9e899"
version = "2.2.0"
"""

def _basic_test_impl(ctx):
    env = unittest.begin(ctx)

    manifest = parse_manifest_toml(_MANIFEST)

    asserts.equals(env, "1.12.5", manifest.julia_version)
    asserts.equals(env, "2.0", manifest.manifest_format)
    asserts.equals(env, "f847120bcaa82ee658f012893bb6f1471266f52d", manifest.project_hash)
    asserts.equals(env, ["CommonMark", "Dates", "Glob", "JuliaFormatter"], sorted(manifest.packages.keys()))

    fmt = manifest.packages["JuliaFormatter"]
    asserts.equals(env, "98e50ef6-434e-11e9-1051-2b60c6c9e899", fmt["uuid"])
    asserts.equals(env, "2.2.0", fmt["version"])
    asserts.equals(env, "ca9470360f51697fc1bde747760b2d99936619ea", fmt["tree_hash"])
    asserts.equals(env, ["CommonMark", "Glob", "JuliaSyntax", "PrecompileTools", "TOML"], fmt["deps"])

    # Standard library packages have no tree hash.
    dates = manifest.packages["Dates"]
    asserts.equals(env, None, dates["tree_hash"])
    asserts.equals(env, ["Printf"], dates["deps"])

    # Packages without dependencies have an empty list.
    asserts.equals(env, [], manifest.packages["Glob"]["deps"])

    return unittest.end(env)

_basic_test = unittest.make(_basic_test_impl)

def manifest_toml_test_suite(name):
    """Define the test suite.

    Args:
        name (str): The name of the test suite.
    """
    unittest.suite(
        name,
        _basic_test,
    )
