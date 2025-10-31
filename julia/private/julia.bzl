"""Julia rules"""

load(":julia_common.bzl", "julia_common")
load(":providers.bzl", "JuliaInfo")
load(":toolchain.bzl", "TOOLCHAIN_TYPE")

def _julia_library_impl(ctx):
    """Implementation of julia_library rule.

    This is a pure metadata gathering rule - no actions are created.
    It collects source files and propagates information to binaries/tests.
    """
    srcs = depset(ctx.files.srcs)
    deps = ctx.attr.deps
    data = ctx.files.data

    # Collect transitive sources
    transitive_srcs = depset(
        direct = ctx.files.srcs,
        transitive = [julia_common.collect_transitive_srcs(deps)],
    )

    include = julia_common.get_include(ctx)

    includes = depset(
        [include],
        transitive = [julia_common.collect_includes(deps)],
    )

    # Create runfiles - no actions, just metadata
    runfiles = ctx.runfiles(files = ctx.files.srcs + data)
    for dep in deps:
        if JuliaInfo in dep:
            runfiles = runfiles.merge(dep[JuliaInfo].runfiles)
        if DefaultInfo in dep:
            runfiles = runfiles.merge(dep[DefaultInfo].default_runfiles)

    return [
        JuliaInfo(
            app_name = ctx.label.name,
            srcs = srcs,
            deps = depset(direct = deps),
            transitive_srcs = transitive_srcs,
            include = include,
            includes = includes,
            runfiles = runfiles,
        ),
        DefaultInfo(
            files = srcs,
            default_runfiles = runfiles,
        ),
    ]

julia_library = rule(
    doc = "A sharable Julia library or module.",
    implementation = _julia_library_impl,
    attrs = {
        "data": attr.label_list(
            doc = "Additional files needed at runtime",
            allow_files = True,
        ),
        "deps": attr.label_list(
            doc = "Other Julia libraries this target depends on",
            providers = [JuliaInfo],
        ),
        "srcs": attr.label_list(
            doc = "Julia source files (.jl files)",
            allow_files = [".jl"],
            mandatory = True,
        ),
    },
    provides = [JuliaInfo],
)

def _julia_binary_impl(ctx):
    """Implementation of julia_binary rule."""

    # Expand location references in env
    env = {}
    for key, value in ctx.attr.env.items():
        env[key] = ctx.expand_location(value, ctx.attr.data)

    return julia_common.create_julia_binary_impl(
        ctx = ctx,
        srcs = ctx.files.srcs,
        deps = ctx.attr.deps,
        data_files = ctx.files.data,
        data_targets = ctx.attr.data,
        env = env,
        main = ctx.file.main if hasattr(ctx.attr, "main") and ctx.attr.main else None,
    )

julia_binary = rule(
    doc = "A Julia executable.",
    implementation = _julia_binary_impl,
    attrs = {
        "data": attr.label_list(
            doc = "Additional files needed at runtime",
            allow_files = True,
        ),
        "deps": attr.label_list(
            doc = "Other Julia libraries this target depends on",
            providers = [JuliaInfo],
        ),
        "env": attr.string_dict(
            doc = "Environment variables to set when running the binary. Supports $(location) expansion.",
        ),
        "main": attr.label(
            doc = "The main entrypoint file. If not specified, defaults to the only file in srcs, or a file matching the target name.",
            allow_single_file = [".jl"],
        ),
        "srcs": attr.label_list(
            doc = "Julia source files (.jl files).",
            allow_files = [".jl"],
            mandatory = True,
        ),
        "_bash_runfiles": attr.label(
            default = Label("@bazel_tools//tools/bash/runfiles"),
        ),
        "_entrypoint": attr.label(
            default = Label("//julia/private:entrypoint.jl"),
            allow_single_file = True,
        ),
        "_wrapper_template": attr.label(
            default = Label("//julia/private:binary_wrapper.tpl"),
            allow_single_file = True,
        ),
    },
    provides = [JuliaInfo],
    executable = True,
    toolchains = [TOOLCHAIN_TYPE],
)

def _julia_test_impl(ctx):
    """Implementation of julia_test rule."""

    # Expand location references in env
    env = {}
    for key, value in ctx.attr.env.items():
        env[key] = ctx.expand_location(value, ctx.attr.data)

    return julia_common.create_julia_binary_impl(
        ctx = ctx,
        srcs = ctx.files.srcs,
        deps = ctx.attr.deps,
        data_files = ctx.files.data,
        data_targets = ctx.attr.data,
        env = env,
        main = ctx.file.main,
    )

julia_test = rule(
    doc = "A Julia test executable.",
    implementation = _julia_test_impl,
    attrs = {
        "data": attr.label_list(
            doc = "Additional files needed at runtime for the test",
            allow_files = True,
        ),
        "deps": attr.label_list(
            doc = "Other Julia libraries this target depends on",
            providers = [JuliaInfo],
        ),
        "env": attr.string_dict(
            doc = "Environment variables to set when running the test. Supports $(location) expansion.",
        ),
        "main": attr.label(
            doc = "The main test entrypoint file. If not specified, defaults to the only file in srcs, or a file matching the target name.",
            allow_single_file = [".jl"],
        ),
        "srcs": attr.label_list(
            doc = "Julia test source files (.jl files).",
            allow_files = [".jl"],
            mandatory = True,
        ),
        "_bash_runfiles": attr.label(
            default = Label("@bazel_tools//tools/bash/runfiles"),
        ),
        "_entrypoint": attr.label(
            default = Label("//julia/private:entrypoint.jl"),
            allow_single_file = True,
        ),
        "_wrapper_template": attr.label(
            default = Label("//julia/private:binary_wrapper.tpl"),
            allow_single_file = True,
        ),
    },
    provides = [JuliaInfo],
    test = True,
    toolchains = [TOOLCHAIN_TYPE],
)
