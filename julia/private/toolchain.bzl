"""Julia toolchain rules"""

load(":rlocation.bzl", "rlocationpath")

TOOLCHAIN_TYPE = str(Label("//julia:toolchain_type"))

_rlocationpath = rlocationpath

_COMPILATION_MODES = ["dbg", "fastbuild", "opt"]

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

    for name, values, allowed in [
        ("opt_level", ctx.attr.opt_level, ["0", "1", "2", "3"]),
        ("check_bounds", ctx.attr.check_bounds, ["auto", "yes", "no"]),
        ("debug_info", ctx.attr.debug_info, ["0", "1", "2"]),
    ]:
        for mode in _COMPILATION_MODES:
            if mode not in values:
                fail("{}: `{}` has no entry for compilation mode `{}`".format(ctx.label, name, mode))
            if values[mode] not in allowed:
                fail("{}: `{}` for `{}` must be one of {}, got `{}`".format(ctx.label, name, mode, allowed, values[mode]))

    if ctx.attr.libgfortran_version not in ["3", "4", "5"]:
        fail("{}: `libgfortran_version` must be one of 3, 4, 5; got `{}`".format(ctx.label, ctx.attr.libgfortran_version))
    if ctx.attr.cxxstring_abi not in ["cxx03", "cxx11"]:
        fail("{}: `cxxstring_abi` must be `cxx03` or `cxx11`; got `{}`".format(ctx.label, ctx.attr.cxxstring_abi))

    return [
        platform_common.ToolchainInfo(
            make_variable_info = make_variable_info,
            julia = ctx.executable.julia,
            all_files = all_files,
            sysimage = ctx.file.sysimage,
            link_files = depset(ctx.files.link_files),
            linker = ctx.attr.linker,
            cpu_target = ctx.attr.cpu_target,
            version = ctx.attr.version,
            opt_level = ctx.attr.opt_level,
            check_bounds = ctx.attr.check_bounds,
            debug_info = ctx.attr.debug_info,
            libgfortran_version = ctx.attr.libgfortran_version,
            cxxstring_abi = ctx.attr.cxxstring_abi,
        ),
        make_variable_info,
    ]

julia_toolchain = rule(
    doc = "A toolchain for building Julia targets.",
    implementation = _julia_toolchain_impl,
    attrs = {
        "check_bounds": attr.string_dict(
            doc = (
                "The bounds checking mode (`julia --check-bounds=<mode>`) per `--compilation_mode`. " +
                "`auto` honours `@inbounds`, `yes` always checks, `no` never does. Julia rejects " +
                "compile caches built with a different mode, so the same value is used for build-time " +
                "precompilation, system images and the binaries that load them. Values other than " +
                "Julia's default (`auto`) make Julia compile its bundled standard library at run time."
            ),
            default = {
                "dbg": "yes",
                "fastbuild": "auto",
                "opt": "auto",
            },
        ),
        "cpu_target": attr.string(
            doc = (
                "The default `--cpu-target` for system images built with this toolchain. " +
                "Should be portable across machines of the toolchain's architecture."
            ),
            default = "generic",
        ),
        "cxxstring_abi": attr.string(
            doc = (
                "The C++ `std::string` ABI (`cxx03` or `cxx11`) of the C++ runtime bundled with this " +
                "Julia. Prebuilt artifacts with C++ code are published for both and the variant " +
                "matching the toolchain is selected. Official Julia binaries use `cxx11`."
            ),
            default = "cxx11",
        ),
        "debug_info": attr.string_dict(
            doc = (
                "The debug info level (`julia -g<n>`) per `--compilation_mode`. Part of Julia's " +
                "compile cache key, so applied uniformly like `opt_level`. Julia's default is `1`."
            ),
            default = {
                "dbg": "2",
                "fastbuild": "1",
                "opt": "1",
            },
        ),
        "julia": attr.label(
            doc = "The path to the Julia binary (julia or julia.exe).",
            cfg = "exec",
            executable = True,
            mandatory = True,
        ),
        "libgfortran_version": attr.string(
            doc = (
                "The major version (`3`, `4` or `5`) of the `libgfortran` bundled with this Julia. " +
                "Prebuilt artifacts with Fortran code are published per `libgfortran` ABI and the " +
                "variant matching the toolchain is selected. Official Julia binaries bundle `5`."
            ),
            default = "5",
        ),
        "link_files": attr.label_list(
            doc = "The `libjulia` libraries needed to link a system image.",
            allow_files = True,
        ),
        "linker": attr.string(
            doc = (
                "The linker used for system images built with this toolchain unless " +
                "overridden by `--@rules_julia//julia/settings:linker`. `julia` uses the " +
                "`lld` bundled with Julia; `cc` uses the C++ toolchain."
            ),
            values = ["julia", "cc"],
            default = "julia",
        ),
        "opt_level": attr.string_dict(
            doc = (
                "The optimization level (`julia -O<n>`) per `--compilation_mode`. Julia rejects " +
                "compile caches built with a different level, so the same value is used for " +
                "build-time precompilation, system images and the binaries that load them. Julia's " +
                "default, `2`, is also its performance setting, and the standard library caches bundled " +
                "with Julia are built at it; other values make Julia compile the standard library at " +
                "run time. `opt` therefore keeps `2` by default and only `dbg` deviates."
            ),
            default = {
                "dbg": "0",
                "fastbuild": "2",
                "opt": "2",
            },
        ),
        "sysimage": attr.label(
            doc = "The stock system image (`sys.so`, `sys.dylib` or `sys.dll`).",
            allow_single_file = True,
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
