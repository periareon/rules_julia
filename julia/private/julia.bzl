"""Julia rules"""

load(":toolchain.bzl", "TOOLCHAIN_TYPE")

JuliaInfo = provider(
    doc = "Information about a Julia library or binary target.",
    fields = {
        "app_name": "str: The Julia project app name.",
        "deps": "depset[JuliaInfo]: of Julia dependencies",
        "include": "str: The include path of the current target.",
        "includes": "depset[str]: of include paths",
        "runfiles": "depset[File]: runfiles for this target",
        "srcs": "depset[File]: of Julia source files",
        "transitive_srcs": "depset[File]: of all Julia source files including transitive deps",
    },
)

def compute_main(owner, srcs, main = None):
    """Determine the main entrypoint for executable rules.

    Args:
        owner (Label): The target owning the attributes.
        srcs (list): A list of File objects.
        main (File, optional): An explicit contender for the main entrypoint.

    Returns:
        File: The file to use for the main entrypoint.
    """
    if main:
        if main not in srcs:
            fail("`main` was not found in `srcs`. Please add `{}` to `srcs` for {}".format(
                main.path,
                owner,
            ))
        return main

    if len(srcs) == 1:
        return srcs[0]

    # Look for a file matching the target name
    main_candidate = None
    for src in srcs:
        basename = src.basename[:-len(".jl")] if src.basename.endswith(".jl") else src.basename
        if basename == owner.name:
            if main_candidate:
                fail("Multiple files match candidates for `main`. Please explicitly specify which to use for {}".format(
                    owner,
                ))
            main_candidate = src

    if not main_candidate:
        fail("`main` was not explicitly specified and no source file matches target name. Please update {}".format(
            owner,
        ))

    return main_candidate

def _rlocationpath(file, workspace_name):
    """Convert a file to its runfiles location path."""
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]
    return "{}/{}".format(workspace_name, file.short_path)

def _collect_transitive_srcs(deps):
    """Collect all transitive source files from dependencies."""
    return depset(
        transitive = [dep[JuliaInfo].transitive_srcs for dep in deps if JuliaInfo in dep],
    )

def _collect_includes(deps):
    """Collect all include paths from dependencies."""
    return depset(
        transitive = [dep[JuliaInfo].includes for dep in deps if JuliaInfo in dep],
    )

def _get_include(ctx, srcs = []):
    workspace_name = ctx.label.workspace_name
    if not workspace_name:
        workspace_name = ctx.workspace_name

    uses_srcs = True
    for src in srcs:
        if not src.owner.name.startswith("src/"):
            uses_srcs = False
            break

    path = "{}/{}".format(workspace_name, ctx.label.package).rstrip("/")
    if uses_srcs:
        path = path + "/src"

    return path

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
        transitive = [_collect_transitive_srcs(deps)],
    )

    include = _get_include(ctx)

    includes = depset(
        [include],
        transitive = [_collect_includes(deps)],
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

def _create_config_file(ctx, includes):
    """Create a configuration file for Julia execution."""
    config = ctx.actions.declare_file("{}_config.txt".format(ctx.label.name))

    # Build include list - one per line
    include_list = includes.to_list() if includes else []
    content = "\n".join(include_list)

    # Write config file
    ctx.actions.write(
        output = config,
        content = content,
    )

    return config

def _create_julia_wrapper(ctx, main_file, config, toolchain_info):
    """Create a wrapper script to run Julia with proper environment."""

    # Template content for wrapper script
    template_file = ctx.file._wrapper_template

    is_windows = template_file.basename.endswith(".bat.tpl")
    wrapper = ctx.actions.declare_file("{}{}".format(ctx.label.name, ".bat" if is_windows else ".sh"))

    julia_bin = toolchain_info.julia
    entrypoint = ctx.file._entrypoint

    # Get runfiles locations
    julia_rloc = _rlocationpath(julia_bin, ctx.workspace_name)
    entrypoint_rloc = _rlocationpath(entrypoint, ctx.workspace_name)
    config_rloc = _rlocationpath(config, ctx.workspace_name)
    main_rloc = _rlocationpath(main_file, ctx.workspace_name)

    # Expand template
    ctx.actions.expand_template(
        template = template_file,
        output = wrapper,
        substitutions = {
            "{config}": config_rloc,
            "{entrypoint}": entrypoint_rloc,
            "{experimental_entrypoint_use_include}": str(toolchain_info._experimental_entrypoint_use_include),
            "{interpreter}": julia_rloc,
            "{main}": main_rloc,
        },
        is_executable = True,
    )

    return wrapper

def _julia_binary_impl(ctx):
    """Implementation of julia_binary rule."""
    toolchain_info = ctx.toolchains[TOOLCHAIN_TYPE]

    # Get the main source file
    if not ctx.files.srcs:
        fail("julia_binary requires at least one source file")
    main_file = compute_main(ctx.label, ctx.files.srcs, ctx.file.main if hasattr(ctx.attr, "main") and ctx.attr.main else None)

    # Collect transitive sources and includes
    transitive_srcs = depset(
        direct = ctx.files.srcs,
        transitive = [_collect_transitive_srcs(ctx.attr.deps)],
    )

    include = _get_include(ctx, ctx.files.srcs)

    includes = depset(
        [include],
        transitive = [_collect_includes(ctx.attr.deps)],
    )

    # Create config file
    config = _create_config_file(ctx, includes)

    # Create wrapper script
    wrapper = _create_julia_wrapper(ctx, main_file, config, toolchain_info)

    # Create runfiles
    runfiles = ctx.runfiles(files = ctx.files.srcs + ctx.files.data)

    # Merge dependency runfiles
    for dep in ctx.attr.deps:
        info = dep[JuliaInfo]
        runfiles = runfiles.merge(info.runfiles)

    # Add data runfiles
    for data_target in ctx.attr.data:
        if DefaultInfo in data_target:
            runfiles = runfiles.merge(data_target[DefaultInfo].default_runfiles)

    # Handle env attribute - expand location references
    env = {}
    for key, value in ctx.attr.env.items():
        env[key] = ctx.expand_location(value, ctx.attr.data)

    return [
        JuliaInfo(
            app_name = ctx.label.name,
            srcs = depset(ctx.files.srcs),
            deps = depset(direct = ctx.attr.deps),
            transitive_srcs = transitive_srcs,
            include = include,
            includes = includes,
        ),
        DefaultInfo(
            executable = wrapper,
            files = depset([wrapper]),
            runfiles = ctx.runfiles(
                files = [
                    config,
                    ctx.file._entrypoint,
                ],
                transitive_files = toolchain_info.all_files,
            ).merge_all([
                runfiles,
                ctx.attr._bash_runfiles[DefaultInfo].default_runfiles,
            ]),
        ),
        RunEnvironmentInfo(
            environment = env,
        ),
    ]

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
    toolchain_info = ctx.toolchains[TOOLCHAIN_TYPE]

    # Get the main source file
    if not ctx.files.srcs:
        fail("julia_test requires at least one source file")
    main_file = compute_main(ctx.label, ctx.files.srcs, ctx.file.main)

    # Collect transitive sources and includes
    transitive_srcs = depset(
        direct = ctx.files.srcs,
        transitive = [_collect_transitive_srcs(ctx.attr.deps)],
    )

    include = _get_include(ctx, ctx.files.srcs)

    includes = depset(
        [include],
        transitive = [_collect_includes(ctx.attr.deps)],
    )

    # Create config file
    config = _create_config_file(ctx, includes)

    # Create wrapper script
    wrapper = _create_julia_wrapper(ctx, main_file, config, toolchain_info)

    # Create runfiles
    runfiles = ctx.runfiles(files = ctx.files.srcs + ctx.files.data)

    # Merge dependency runfiles
    for dep in ctx.attr.deps:
        info = dep[JuliaInfo]
        runfiles = runfiles.merge(info.runfiles)

    # Add data runfiles
    for data_target in ctx.attr.data:
        if DefaultInfo in data_target:
            runfiles = runfiles.merge(data_target[DefaultInfo].default_runfiles)

    # Handle env attribute - expand location references
    env = {}
    for key, value in ctx.attr.env.items():
        env[key] = ctx.expand_location(value, ctx.attr.data)

    return [
        JuliaInfo(
            app_name = ctx.label.name,
            srcs = depset(ctx.files.srcs),
            deps = depset(direct = ctx.attr.deps),
            transitive_srcs = transitive_srcs,
            include = include,
            includes = includes,
        ),
        DefaultInfo(
            executable = wrapper,
            files = depset([wrapper]),
            runfiles = ctx.runfiles(
                files = [
                    config,
                    ctx.file._entrypoint,
                ],
                transitive_files = toolchain_info.all_files,
            ).merge_all([
                runfiles,
                ctx.attr._bash_runfiles[DefaultInfo].default_runfiles,
            ]),
        ),
        RunEnvironmentInfo(
            environment = env,
        ),
    ]

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
