"""Bazel rules for JuliaFormatter"""

load(":julia.bzl", "JuliaInfo")

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

def _rlocationpath(file, workspace_name):
    """Convert a file to its runfiles location path."""
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]
    return "{}/{}".format(workspace_name, file.short_path)

def _julia_format_test_impl(ctx):
    """Implementation of julia_format_test rule."""
    runner_info = ctx.attr._runner[DefaultInfo]

    target_info = ctx.attr.target[JuliaInfo]

    # External repos always fall into the `../` branch of `_rlocationpath`.
    workspace_name = ctx.workspace_name

    # Get all non-generated sources
    srcs = [src for src in target_info.srcs.to_list() if src.is_source]

    def _srcs_map(file):
        return "--src={}".format(_rlocationpath(file, workspace_name))

    args = ctx.actions.args()
    args.set_param_file_format("multiline")
    args.add("--config", _rlocationpath(ctx.file.config, ctx.workspace_name))
    args.add_all(srcs, map_each = _srcs_map, allow_closure = True)

    args_file = ctx.actions.declare_file("{}.julia_format_args.txt".format(ctx.label.name))
    ctx.actions.write(
        output = args_file,
        content = args,
    )

    is_windows = ctx.executable._runner.basename.endswith(".bat")
    executable = ctx.actions.declare_file("{}{}".format(ctx.label.name, ".bat" if is_windows else ".sh"))
    ctx.actions.symlink(
        target_file = ctx.executable._runner,
        output = executable,
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = [ctx.file.config, args_file] + srcs,
    ).merge(runner_info.default_runfiles)

    return [
        DefaultInfo(
            files = depset([executable]),
            runfiles = runfiles,
            executable = executable,
        ),
        RunEnvironmentInfo(
            environment = {
                "RULES_JULIA_FORMAT_ARGS_FILE": _rlocationpath(args_file, ctx.workspace_name),
            },
        ),
    ]

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
        "_runner": attr.label(
            doc = "The process wrapper for running JuliaFormatter.",
            cfg = "exec",
            executable = True,
            default = Label("//julia/private/format:format_checker"),
        ),
    },
    test = True,
)
