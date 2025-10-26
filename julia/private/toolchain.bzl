"""Julia toolchain rules"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

TOOLCHAIN_TYPE = str(Label("//julia:toolchain_type"))

def _rlocationpath(file, workspace_name):
    """Convert a file to its runfiles location path."""
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]
    return "{}/{}".format(workspace_name, file.short_path)

def _julia_toolchain_impl(ctx):
    """Implementation of the julia_toolchain rule."""

    # Create template variable for Julia binary
    make_variable_info = platform_common.TemplateVariableInfo({
        "JULIA": ctx.executable.julia.path,
        "JULIA_RLOCATIONPATH": _rlocationpath(ctx.executable.julia, ctx.workspace_name),
    })

    # Collect all files needed for the toolchain
    all_files = depset(transitive = [
        ctx.attr.julia[DefaultInfo].default_runfiles.files if ctx.attr.julia[DefaultInfo].default_runfiles else depset(),
        ctx.attr.julia[DefaultInfo].files,
    ])

    experimental_entrypoint_use_include = ctx.attr._experimental_entrypoint_use_include[BuildSettingInfo].value

    return [
        platform_common.ToolchainInfo(
            make_variable_info = make_variable_info,
            julia = ctx.executable.julia,
            all_files = all_files,
            _experimental_entrypoint_use_include = experimental_entrypoint_use_include,
        ),
        make_variable_info,
    ]

julia_toolchain = rule(
    doc = "A toolchain for building Julia targets.",
    implementation = _julia_toolchain_impl,
    attrs = {
        "julia": attr.label(
            doc = "The path to the Julia binary (julia or julia.exe).",
            cfg = "exec",
            executable = True,
            mandatory = True,
        ),
        "_experimental_entrypoint_use_include": attr.label(
            default = Label("//julia/settings:experimental_entrypoint_use_include"),
        ),
    },
)

def _current_julia_toolchain_impl(ctx):
    toolchain = ctx.toolchains[TOOLCHAIN_TYPE]

    return [
        DefaultInfo(
            files = toolchain.all_files,
            runfiles = ctx.runfiles(transitive_files = toolchain.all_files),
        ),
        toolchain,
        toolchain.make_variable_info,
    ]

current_julia_toolchain = rule(
    doc = "Access the `julia_toolchain` for the current configuration.",
    implementation = _current_julia_toolchain_impl,
    toolchains = [TOOLCHAIN_TYPE],
)
