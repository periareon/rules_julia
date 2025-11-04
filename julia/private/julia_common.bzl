"""Common utilities for Julia rules."""

load(":providers.bzl", "JuliaInfo")
load(":toolchain.bzl", "TOOLCHAIN_TYPE")

def _rlocationpath(file, workspace_name):
    """Convert a file to its runfiles location path.

    Args:
        file: A File object.
        workspace_name: The workspace name.

    Returns:
        str: The runfiles location path for the file.
    """
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]
    return "{}/{}".format(workspace_name, file.short_path)

def _compute_main(owner, srcs, main = None):
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

def _collect_transitive_srcs(deps):
    """Collect all transitive source files from dependencies.

    Args:
        deps: List of dependency targets.

    Returns:
        depset: Transitive source files.
    """
    return depset(
        transitive = [dep[JuliaInfo].transitive_srcs for dep in deps if JuliaInfo in dep],
    )

def _collect_includes(deps):
    """Collect all include paths from dependencies.

    Args:
        deps: List of dependency targets.

    Returns:
        depset: Include paths.
    """
    return depset(
        transitive = [dep[JuliaInfo].includes for dep in deps if JuliaInfo in dep],
    )

def _get_include(ctx, srcs = []):
    """Get the include path for the current target.

    Args:
        ctx: Rule context.
        srcs: List of source files.

    Returns:
        str: Include path.
    """
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

def _includes_map(include):
    """Map function for formatting include paths."""
    return "    \"{}\",".format(include)

def _create_config_file(ctx, includes, runfiles):
    """Create a configuration file for Julia execution.

    The config file contains two sections:
    1. [includes] - Include paths for LOAD_PATH
    2. [runfiles] - All runfiles paths (excluding toolchain files) for manifest mode

    Args:
        ctx: Rule context.
        includes: depset of include paths.
        runfiles: ctx.runfiles object.

    Returns:
        File: The config file.
    """
    config = ctx.actions.declare_file("{}_config.toml".format(ctx.label.name))
    args = ctx.actions.args()
    args.set_param_file_format("multiline")

    workspace_name = ctx.workspace_name

    def runfiles_map(file):
        return "    \"{}\",".format(_rlocationpath(file, workspace_name))

    args.add("includes = [")
    args.add_all(includes, map_each = _includes_map)
    args.add("]")
    args.add("")
    args.add("runfiles = [")
    args.add_all(
        runfiles.files,
        map_each = runfiles_map,
        allow_closure = True,
        expand_directories = False,
    )
    args.add("]")
    args.add("")

    # Write config file
    ctx.actions.write(
        output = config,
        content = args,
    )

    return config

def _create_julia_wrapper(ctx, main_file, config, toolchain_info):
    """Create a wrapper script to run Julia with proper environment.

    Args:
        ctx: Rule context.
        main_file: The main Julia file to execute.
        config: The config file.
        toolchain_info: The Julia toolchain info.

    Returns:
        File: The wrapper executable.
    """

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

def _create_julia_binary_impl(
        ctx,
        srcs,
        deps,
        data_files,
        data_targets,
        env,
        main = None):
    """Common implementation for julia_binary and julia_test rules.

    Args:
        ctx: Rule context (for actions, label, toolchain, workspace_name).
        srcs: List of source File objects.
        deps: List of dependency targets with JuliaInfo.
        data_files: List of data File objects.
        data_targets: List of data targets (for runfiles merging).
        env: Dictionary of environment variables.
        main: Optional main File object.

    Returns:
        list: List of providers [JuliaInfo, DefaultInfo, RunEnvironmentInfo].
    """
    toolchain_info = ctx.toolchains[TOOLCHAIN_TYPE]

    # Get the main source file
    if not srcs:
        fail("At least one source is required.")
    main_file = _compute_main(ctx.label, srcs, main)

    # Collect transitive sources and includes
    transitive_srcs = depset(
        direct = srcs,
        transitive = [_collect_transitive_srcs(deps)],
    )

    include = _get_include(ctx, srcs)

    includes = depset(
        [include],
        transitive = [_collect_includes(deps)],
    )

    # Create runfiles first (needed for config file generation)
    runfiles = ctx.runfiles(files = srcs + data_files)

    # Merge dependency runfiles
    for dep in deps:
        # Get runfiles from JuliaInfo if available (julia_library provides this)
        if JuliaInfo in dep and hasattr(dep[JuliaInfo], "runfiles"):
            runfiles = runfiles.merge(dep[JuliaInfo].runfiles)
            # Otherwise get from DefaultInfo (julia_binary provides this)

        elif DefaultInfo in dep and hasattr(dep[DefaultInfo], "default_runfiles"):
            runfiles = runfiles.merge(dep[DefaultInfo].default_runfiles)

    # Add data runfiles
    for data_target in data_targets:
        if DefaultInfo in data_target:
            runfiles = runfiles.merge(data_target[DefaultInfo].default_runfiles)

    # Create config file (needs runfiles to list all paths)
    config = _create_config_file(ctx, includes, runfiles)

    # Create wrapper script
    wrapper = _create_julia_wrapper(ctx, main_file, config, toolchain_info)

    return [
        JuliaInfo(
            app_name = ctx.label.name,
            srcs = depset(srcs),
            deps = depset(direct = deps),
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

# Public struct exposing all common utilities
julia_common = struct(
    rlocationpath = _rlocationpath,
    compute_main = _compute_main,
    collect_transitive_srcs = _collect_transitive_srcs,
    collect_includes = _collect_includes,
    get_include = _get_include,
    create_config_file = _create_config_file,
    create_julia_wrapper = _create_julia_wrapper,
    create_julia_binary_impl = _create_julia_binary_impl,
    TOOLCHAIN_TYPE = TOOLCHAIN_TYPE,
)
