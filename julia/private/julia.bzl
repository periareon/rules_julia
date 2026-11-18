"""Julia rules"""

load(":julia_common.bzl", "julia_common")
load(":providers.bzl", "JuliaInfo")
load(":toolchain.bzl", "TOOLCHAIN_TYPE")

def _julia_library_impl(ctx):
    """Implementation of julia_library rule.

    Collects source files and propagates information to binaries/tests.
    """
    srcs = depset(ctx.files.srcs)
    toolchain_info = ctx.toolchains[TOOLCHAIN_TYPE]
    deps = julia_common.select_artifacts(ctx, ctx.attr.deps, toolchain_info)
    data = ctx.files.data

    transitive_srcs = depset(
        direct = ctx.files.srcs,
        transitive = [julia_common.collect_transitive_srcs(deps)],
    )

    root = ctx.file.entry
    if root and root not in ctx.files.srcs:
        fail("`entry` was not found in `srcs`. Please add `{}` to `srcs` for {}".format(
            root.short_path,
            ctx.label,
        ))

    layout = julia_common.package_layout(ctx, ctx.files.srcs, data, root = root)
    if root and layout.entry == None:
        fail("`entry` of {} must be `{name}.jl` next to the BUILD file or `src/{name}.jl`, got `{}`".format(
            ctx.label,
            root.short_path,
            name = layout.name,
        ))

    includes = depset(
        layout.includes,
        transitive = [julia_common.collect_includes(deps)],
    )

    runfiles = ctx.runfiles(files = ctx.files.srcs + data)
    for dep in deps:
        if JuliaInfo in dep:
            runfiles = runfiles.merge(dep[JuliaInfo].runfiles)
        if DefaultInfo in dep:
            runfiles = runfiles.merge(dep[DefaultInfo].default_runfiles)

    dep_depots = julia_common.collect_depots(deps)
    artifact_depots = julia_common.collect_artifact_depots(deps)
    depots = dep_depots
    if _is_precompilable(ctx, layout):
        depot = julia_common.precompile(
            ctx,
            name = layout.name,
            includes = includes,
            runfiles = runfiles,
            dep_depots = dep_depots,
            toolchain_info = toolchain_info,
            exec_toolchain_info = ctx.attr._julia_toolchain_exec[platform_common.ToolchainInfo],
            artifact_depots = artifact_depots,
        )
        depots = depset([depot], transitive = [dep_depots])
        runfiles = runfiles.merge(ctx.runfiles(files = [depot]))

    return [
        JuliaInfo(
            srcs = srcs,
            transitive_srcs = transitive_srcs,
            include = layout.include,
            includes = includes,
            runfiles = runfiles,
            depots = depots,
            artifact_depots = artifact_depots,
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
            entry point, the toolchain supports relocatable
            (`@depot`-relative) caches, which requires Julia 1.11, and the
            execution platform's Julia is the target platform's Julia.
    """
    toolchain_info = ctx.toolchains[TOOLCHAIN_TYPE]
    exec_toolchain_info = ctx.attr._julia_toolchain_exec[platform_common.ToolchainInfo]
    return (
        ctx.attr.precompile and
        layout.entry != None and
        julia_common.version_gte(toolchain_info.version, "1.11.0") and
        # A package image is native code for the Julia that built it, so a
        # cache built by another platform's Julia cannot be loaded on the
        # target. `short_path` drops the configuration, so equal paths mean
        # the same Julia distribution.
        exec_toolchain_info.julia.short_path == toolchain_info.julia.short_path
    )

julia_library = rule(
    doc = (
        "A sharable Julia library or module.\n\n" +
        "A library is one Julia package: a root file `<name>.jl` or `src/<name>.jl` defining " +
        "`module <name>` (see `entry`), from which every other source is reached with " +
        "`include`. Nested modules are fine. A second source defining its own top-level " +
        "module is another package and belongs in its own `julia_library`: left in `srcs` " +
        "it can be loaded but is never precompiled, and precompiling this library fails " +
        "if the root module `using`s it."
    ),
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
        "entry": attr.label(
            doc = (
                "The package's root file, `<name>.jl` or `src/<name>.jl`, defining `module <name>`. " +
                "Defaults to the source named after the target. Set it when the target name " +
                "differs from the package name: `entry = \"src/Greeter.jl\"` on a target named " +
                "`greeter_lib` makes the library `Greeter`. Must be one of `srcs`."
            ),
            allow_single_file = [".jl"],
        ),
        "precompile": attr.bool(
            doc = (
                "Precompile the library at build time. The resulting cache is placed on " +
                "`DEPOT_PATH` for every binary and test that depends on this library. " +
                "Requires the package root file (see `entry`), Julia 1.11+ and the same " +
                "Julia on the execution and target platforms; otherwise no cache is produced."
            ),
            default = True,
        ),
        "srcs": attr.label_list(
            doc = "Julia source files (.jl files)",
            allow_files = [".jl"],
            mandatory = True,
        ),
        "_julia_toolchain_exec": attr.label(
            doc = "The Julia toolchain of the execution platform, which runs the precompile step.",
            cfg = "exec",
            default = Label("//julia:current_julia_toolchain"),
            providers = [platform_common.ToolchainInfo],
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
        julia_flags = ctx.attr.julia_flags,
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
        "julia_flags": attr.string_list(
            doc = (
                "Flags for the `julia` interpreter itself, such as `--color=yes` or `--threads=auto`; " +
                "program arguments go in `args`. Flags that affect code generation (`-O`, " +
                "`--check-bounds`, `-g`) are rejected here because build-time compile caches must be " +
                "built with the same values: they follow `--compilation_mode` through the toolchain's " +
                "`opt_level`, `check_bounds` and `debug_info` attributes instead. " +
                "Flags the rules manage (`--compiled-modules`, `--sysimage`, `--project`) are rejected too."
            ),
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
        julia_flags = ctx.attr.julia_flags,
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
        "julia_flags": attr.string_list(
            doc = (
                "Flags for the `julia` interpreter itself, such as `--color=yes` or `--threads=auto`; " +
                "program arguments go in `args`. Flags that affect code generation (`-O`, " +
                "`--check-bounds`, `-g`) are rejected here because build-time compile caches must be " +
                "built with the same values: they follow `--compilation_mode` through the toolchain's " +
                "`opt_level`, `check_bounds` and `debug_info` attributes instead. " +
                "Flags the rules manage (`--compiled-modules`, `--sysimage`, `--project`) are rejected too."
            ),
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
