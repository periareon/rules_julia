"""Exposing a Julia toolchain as a target.

Pkg rules need to run Julia of several versions from one target. Toolchains
cannot be enumerated at analysis time, but a rule can be configured for each
version through a split transition. `julia_runtime` resolves the toolchain in
its configuration and hands the interpreter and its files to whoever depends
on it, producing no files of its own so that several configurations of it
can share one set of runfiles.
"""

load("//julia/private:toolchain.bzl", "TOOLCHAIN_TYPE")

JuliaRuntimeInfo = provider(
    doc = "A Julia interpreter resolved from the toolchain of the current configuration.",
    fields = {
        "files": "depset[File]: Everything needed to run the interpreter.",
        "julia": "File: The `julia` executable.",
        "version": "str: The toolchain's Julia version.",
    },
)

def _julia_runtime_impl(ctx):
    toolchain_info = ctx.toolchains[TOOLCHAIN_TYPE]
    return [
        DefaultInfo(
            files = toolchain_info.all_files,
            runfiles = ctx.runfiles(transitive_files = toolchain_info.all_files),
        ),
        JuliaRuntimeInfo(
            files = toolchain_info.all_files,
            julia = toolchain_info.julia,
            version = toolchain_info.version,
        ),
    ]

julia_runtime = rule(
    doc = "The Julia interpreter of the resolved toolchain, as a target.",
    implementation = _julia_runtime_impl,
    toolchains = [TOOLCHAIN_TYPE],
)
