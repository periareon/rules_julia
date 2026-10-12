"""# Julia Pkg rules"""

load(
    ":extensions.bzl",
    _pkg = "pkg",
)

# buildifier: disable=deprecated-function
load(
    ":julia_pkg_compiler.bzl",
    _julia_pkg_compiler = "julia_pkg_compiler",
)
load(
    ":julia_pkg_resolve.bzl",
    _julia_pkg_resolve = "julia_pkg_resolve",
)
load(
    ":julia_pkg_resolve_test.bzl",
    _julia_pkg_resolve_test = "julia_pkg_resolve_test",
)

# buildifier: disable=deprecated-function
load(
    ":julia_pkg_test.bzl",
    _julia_pkg_test = "julia_pkg_test",
)

julia_pkg_resolve = _julia_pkg_resolve
julia_pkg_resolve_test = _julia_pkg_resolve_test
pkg = _pkg

# Deprecated aliases, kept for one release.
julia_pkg_compiler = _julia_pkg_compiler
julia_pkg_test = _julia_pkg_test
