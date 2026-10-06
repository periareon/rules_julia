"""Julia rules"""

load(":julia_common.bzl", "julia_common")
load(":providers.bzl", "JuliaInfo")
load(":toolchain.bzl", "TOOLCHAIN_TYPE")

def _julia_library_impl(ctx):
    """Implementation of julia_library rule.

    Collects source files and propagates information to binaries/tests.
    """
    srcs = depset(ctx.files.srcs)
    deps = ctx.attr.deps
    data = ctx.files.data

    transitive_srcs = depset(
        direct = ctx.files.srcs,
        transitive = [julia_common.collect_transitive_srcs(deps)],
    )

    layout = julia_common.package_layout(ctx, ctx.files.srcs)

    includes = depset(
        [layout.include],
        transitive = [julia_common.collect_includes(deps)],
    )

    runfiles = ctx.runfiles(files = ctx.files.srcs + data)
    for dep in deps:
        if JuliaInfo in dep:
            runfiles = runfiles.merge(dep[JuliaInfo].runfiles)
        if DefaultInfo in dep:
            runfiles = runfiles.merge(dep[DefaultInfo].default_runfiles)

    dep_depots = julia_common.collect_depots(deps)
    depots = dep_depots
    if _is_precompilable(ctx, layout):
        toolchain_info = ctx.toolchains[TOOLCHAIN_TYPE]
        depot = julia_common.precompile(
            ctx,
            name = ctx.label.name,
            includes = includes,
            runfiles = runfiles,
            dep_depots = dep_depots,
            toolchain_info = toolchain_info,
        )
        depots = depset([depot], transitive = [dep_depots])
        runfiles = runfiles.merge(ctx.runfiles(files = [depot]))

    return [
        JuliaInfo(
            app_name = ctx.label.name,
            srcs = srcs,
            transitive_srcs = transitive_srcs,
            include = layout.include,
            includes = includes,
            runfiles = runfiles,
            depots = depots,
            entry = layout.entry,
        ),
        DefaultInfo(
            files = srcs,
            default_runfiles = runfiles,
        ),
    ]

def _is_precompilable(ctx, layout):
    """Whether a `julia_library` can be precompiled.

    Args:
        ctx: Rule context.
        layout (struct): The library's package layout.

    Returns:
        bool: True if precompilation is enabled, the library has a package
            entry point, and the toolchain supports relocatable
            (`@depot`-relative) caches, which requires Julia 1.11.
    """
    return (
        ctx.attr.precompile and
        layout.entry != None and
        julia_common.version_gte(ctx.toolchains[TOOLCHAIN_TYPE].version, "1.11.0")
    )

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
        "precompile": attr.bool(
            doc = (
                "Precompile the library at build time. The resulting cache is placed on " +
                "`DEPOT_PATH` for every binary and test that depends on this library. " +
                "Requires the module entry point `<name>.jl` (typically `src/<name>.jl`) " +
                "and Julia 1.11+; otherwise no cache is produced."
            ),
            default = True,
        ),
        "srcs": attr.label_list(
            doc = "Julia source files (.jl files)",
            allow_files = [".jl"],
            mandatory = True,
        ),
        "_precompiler": attr.label(
            default = Label("//julia/private:precompile.jl"),
            allow_single_file = True,
        ),
    } | julia_common.DRIVER_ATTRS,
    provides = [JuliaInfo],
    toolchains = [TOOLCHAIN_TYPE],
)

def _julia_binary_impl(ctx):
    """Implementation of julia_binary rule."""
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
    } | julia_common.BINARY_ATTRS,
    provides = [JuliaInfo],
    executable = True,
    toolchains = [TOOLCHAIN_TYPE],
)

def _julia_test_impl(ctx):
    """Implementation of julia_test rule."""
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
    } | julia_common.BINARY_ATTRS,
    provides = [JuliaInfo],
    test = True,
    toolchains = [TOOLCHAIN_TYPE],
)
