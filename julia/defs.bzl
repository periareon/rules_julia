"""# Julia Bazel rules"""

load(":extensions.bzl", _julia = "julia")
load(":julia_binary.bzl", _julia_binary = "julia_binary")
load(":julia_format_aspect.bzl", _julia_format_aspect = "julia_format_aspect")
load(":julia_format_test.bzl", _julia_format_test = "julia_format_test")
load(":julia_library.bzl", _julia_library = "julia_library")
load(":julia_standalone_binary.bzl", _julia_standalone_binary = "julia_standalone_binary")
load(":julia_test.bzl", _julia_test = "julia_test")
load(":julia_toolchain.bzl", _julia_toolchain = "julia_toolchain")

julia = _julia
julia_binary = _julia_binary
julia_format_aspect = _julia_format_aspect
julia_format_test = _julia_format_test
julia_library = _julia_library
julia_standalone_binary = _julia_standalone_binary
julia_test = _julia_test
julia_toolchain = _julia_toolchain
