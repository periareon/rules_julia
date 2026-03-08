"""Julia toolchain rules"""

load(":rlocation.bzl", "rlocationpath")

TOOLCHAIN_TYPE = str(Label("//julia:toolchain_type"))

_rlocationpath = rlocationpath

def _julia_toolchain_impl(ctx):
    """Implementation of the julia_toolchain rule."""

    make_variable_info = platform_common.TemplateVariableInfo({
        "JULIA": ctx.executable.julia.path,
        "JULIA_RLOCATIONPATH": _rlocationpath(ctx.executable.julia, ctx.workspace_name),
    })

    all_files = depset(transitive = [
        ctx.attr.julia[DefaultInfo].default_runfiles.files if ctx.attr.julia[DefaultInfo].default_runfiles else depset(),
        ctx.attr.julia[DefaultInfo].files,
    ])

    return [
        platform_common.ToolchainInfo(
            make_variable_info = make_variable_info,
            julia = ctx.executable.julia,
            all_files = all_files,
            version = ctx.attr.version,
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
        "version": attr.string(
            doc = "The Julia version string (e.g., '1.12.5').",
            mandatory = True,
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
