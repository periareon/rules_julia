"""Bazel rules for JuliaFormatter"""

load(":julia_common.bzl", "julia_common")
load(":providers.bzl", "JuliaInfo")

def _julia_format_aspect_impl(target, ctx):
    """Implementation of julia_format_aspect."""
    ignore_tags = [
        "no_julia_format",
        "no_juliafmt",
        "no_format",
        "nojuliafmt",
        "noformat",
    ]
    for tag in ctx.rule.attr.tags:
        sanitized = tag.replace("-", "_").lower()
        if sanitized in ignore_tags:
            return []

    if JuliaInfo not in target:
        return []

    julia_info = target[JuliaInfo]

    # Get all non-generated sources
    srcs = [src for src in julia_info.srcs.to_list() if src.is_source]
    if not srcs:
        return []

    marker = ctx.actions.declare_file("{}.julia_format.ok".format(target.label.name))

    args = ctx.actions.args()
    args.add("--config", ctx.file._config)
    args.add("--marker", marker)
    args.add_all(srcs, format_each = "--src=%s")

    ctx.actions.run(
        mnemonic = "JuliaFormat",
        progress_message = "JuliaFormat %{label}",
        executable = ctx.executable._runner,
        inputs = depset([ctx.file._config] + srcs),
        outputs = [marker],
        arguments = [args],
    )

    return [OutputGroupInfo(
        julia_format_checks = depset([marker]),
    )]

julia_format_aspect = aspect(
    implementation = _julia_format_aspect_impl,
    doc = "An aspect for running JuliaFormatter on targets with Julia sources.",
    attrs = {
        "_config": attr.label(
            doc = "The config file (`.JuliaFormatter.toml`) containing JuliaFormatter settings.",
            cfg = "target",
            allow_single_file = True,
            default = Label("//julia/settings:julia_formatter_config"),
        ),
        "_runner": attr.label(
            doc = "The process wrapper for running JuliaFormatter.",
            cfg = "exec",
            executable = True,
            default = Label("//julia/private/format:format_checker"),
        ),
    },
    required_providers = [JuliaInfo],
)

def _julia_format_test_impl(ctx):
    """Implementation of julia_format_test rule."""
    target_info = ctx.attr.target[JuliaInfo]

    # External repos always fall into the `../` branch of `julia_common.rlocationpath`.
    workspace_name = ctx.workspace_name

    # Get all non-generated sources
    srcs = [src for src in target_info.srcs.to_list() if src.is_source]

    def _srcs_map(file):
        return "--src={}".format(julia_common.rlocationpath(file, workspace_name))

    args = ctx.actions.args()
    args.set_param_file_format("multiline")
    args.add("--config", julia_common.rlocationpath(ctx.file.config, ctx.workspace_name))
    args.add_all(srcs, map_each = _srcs_map, allow_closure = True)

    args_file = ctx.actions.declare_file("{}.julia_format_args.txt".format(ctx.label.name))
    ctx.actions.write(
        output = args_file,
        content = args,
    )

    # Curate values for the common implementation
    # Use the runner's main source file as srcs
    curated_srcs = [ctx.file._runner_main]

    # Include the runner binary as a dependency
    curated_deps = [ctx.attr._runner]

    # Include args_file, config, and target srcs as data
    curated_data_files = [args_file, ctx.file.config] + srcs
    curated_data_targets = []

    # Set environment variable for args file location
    curated_env = {
        "RULES_JULIA_FORMAT_ARGS_FILE": julia_common.rlocationpath(args_file, ctx.workspace_name),
    }

    # Call the common implementation with curated values
    return julia_common.create_julia_binary_impl(
        ctx = ctx,
        srcs = curated_srcs,
        deps = curated_deps,
        data_files = curated_data_files,
        data_targets = curated_data_targets,
        env = curated_env,
        main = ctx.file._runner_main,
    )

julia_format_test = rule(
    implementation = _julia_format_test_impl,
    doc = "A rule for running JuliaFormatter on a Julia target.",
    attrs = {
        "config": attr.label(
            doc = "The config file (`.JuliaFormatter.toml`) containing JuliaFormatter settings.",
            cfg = "target",
            allow_single_file = True,
            default = Label("//julia/settings:julia_formatter_config"),
        ),
        "target": attr.label(
            doc = "The target to run JuliaFormatter on.",
            providers = [JuliaInfo],
            mandatory = True,
        ),
        "_bash_runfiles": attr.label(
            default = Label("@bazel_tools//tools/bash/runfiles"),
        ),
        "_entrypoint": attr.label(
            default = Label("//julia/private:entrypoint.jl"),
            allow_single_file = True,
        ),
        "_runner": attr.label(
            doc = "The format checker binary.",
            cfg = "target",
            providers = [JuliaInfo],
            default = Label("//julia/private/format:format_checker"),
        ),
        "_runner_main": attr.label(
            doc = "The runner's main source file.",
            allow_single_file = [".jl"],
            default = Label("//julia/private/format:src/format_checker.jl"),
        ),
        "_wrapper_template": attr.label(
            default = Label("//julia/private:binary_wrapper.tpl"),
            allow_single_file = True,
        ),
    },
    test = True,
    toolchains = [julia_common.TOOLCHAIN_TYPE],
)
