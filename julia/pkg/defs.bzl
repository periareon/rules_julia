"""# Julia Pkg rules"""

load(
    ":extensions.bzl",
    _pkg = "pkg",
)
load(
    ":julia_pkg_compiler.bzl",
    _julia_pkg_compiler = "julia_pkg_compiler",
)
load(
    ":julia_pkg_test.bzl",
    _julia_pkg_test = "julia_pkg_test",
)

julia_pkg_compiler = _julia_pkg_compiler
julia_pkg_test = _julia_pkg_test
pkg = _pkg
