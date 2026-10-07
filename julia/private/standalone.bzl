"""Julia standalone binary rules"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load(":julia_common.bzl", "julia_common")
load(":providers.bzl", "JuliaInfo")
load(":toolchain.bzl", "TOOLCHAIN_TYPE")

# Resources declared for `JuliaSysimage`. Emitting the system image object
# (`julia --output-o`) regenerates native code for the whole image and is the
# irreducible step; it parallelizes via `JULIA_IMAGE_THREADS`, so the thread
# count and the declared CPUs are kept in sync. Memory was measured on Julia
# 1.12.5 / x86_64 Linux at 7.8 GB peak with four threads, with headroom added.
_IMAGE_THREADS = 4
_MEMORY_MB = 10240

def _sysimage_resource_set(_os_name, _inputs_size):
    return {"cpu": _IMAGE_THREADS, "memory": _MEMORY_MB}

def _emit_sysimage_object(ctx, *, julia_info, toolchain_info):
    """Run `julia --output-o` to emit the object archive of a system image.

    Args:
        ctx: Rule context.
        julia_info (JuliaInfo): Provider of the package to include.
        toolchain_info (ToolchainInfo): The Julia toolchain.

    Returns:
        File: The object archive.
    """
    name = ctx.label.name
    archive = ctx.actions.declare_file("{}.sysimage.a".format(name))
    config = julia_common.create_config_file(
        ctx,
        julia_info.includes,
        julia_info.runfiles,
        julia_info.depots,
        name = name + ".sysimage",
        artifact_depots = julia_info.artifact_depots,
    )
    manifest = julia_common.write_runfiles_manifest(
        ctx,
        "{}.sysimage_manifest".format(name),
        julia_info.runfiles.files,
    )

    args = ctx.actions.args()
    args.add("--config", config)
    args.add("--manifest", manifest)
    args.add("--package", julia_info.app_name)
    args.add_all(ctx.files.precompile_statements, before_each = "--precompile-statements")

    julia_flags = [
        "--history-file=no",
        "--threads=1",
        "--cpu-target=" + (ctx.attr.cpu_target or toolchain_info.cpu_target),
        "--sysimage=" + toolchain_info.sysimage.path,
        "--output-o=" + archive.path,
    ]

    julia_common.run_driver(
        ctx,
        toolchain_info = toolchain_info,
        driver = ctx.file._sysimage_driver,
        arguments = args,
        inputs = depset(
            [config, manifest] + ctx.files.precompile_statements,
            transitive = [julia_info.runfiles.files],
        ),
        outputs = [archive],
        mnemonic = "JuliaSysimage",
        julia_flags = julia_flags,
        env = {
            "JULIA_IMAGE_THREADS": str(_IMAGE_THREADS),
            "OPENBLAS_NUM_THREADS": "1",
        },
        resource_set = _sysimage_resource_set,
    )

    return archive

_CC_TOOLCHAIN_TYPE = "@rules_cc//cc:toolchain_type"

def _link_sysimage(ctx, *, archive, toolchain_info):
    """Link a system image object archive into a shared library.

    The linker is the toolchain's unless `//julia/settings:linker` overrides it.

    Args:
        ctx: Rule context.
        archive (File): The object archive from `julia --output-o`.
        toolchain_info (ToolchainInfo): The Julia toolchain.

    Returns:
        File: The shared library (the system image).
    """
    linker = ctx.attr._linker[BuildSettingInfo].value
    if linker == "toolchain":
        linker = toolchain_info.linker
    if linker == "julia":
        return _link_with_julia(ctx, archive = archive, toolchain_info = toolchain_info)
    if linker == "cc":
        return _link_with_cc(ctx, archive = archive, toolchain_info = toolchain_info)
    fail("Unknown linker `{}`".format(linker))

def _link_with_julia(ctx, *, archive, toolchain_info):
    """Link with the `lld` bundled with Julia, as Julia links its own package images."""
    sysimage = ctx.actions.declare_file("{}.sysimage/sys.{}".format(
        ctx.label.name,
        toolchain_info.sysimage.extension,
    ))

    args = ctx.actions.args()
    args.add("--archive", archive)
    args.add("--output", sysimage)

    julia_common.run_driver(
        ctx,
        toolchain_info = toolchain_info,
        driver = ctx.file._link_driver,
        arguments = args,
        inputs = depset([archive]),
        outputs = [sysimage],
        mnemonic = "JuliaLink",
    )

    return sysimage

def _link_with_cc(ctx, *, archive, toolchain_info):
    """Link with `cc_common.link` and the resolved C++ toolchain."""
    if not ctx.toolchains[_CC_TOOLCHAIN_TYPE]:
        fail((
            "{}: `--@rules_julia//julia/settings:linker=cc` requires a C++ toolchain " +
            "but none resolved for the target platform. Register one or use the " +
            "linker bundled with Julia (`linker=julia`)."
        ).format(ctx.label))

    cc_toolchain = find_cc_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    # Every object in the archive must end up in the image.
    library = cc_common.create_library_to_link(
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        static_library = archive,
        alwayslink = True,
    )

    libdirs = {lib.dirname: None for lib in toolchain_info.link_files.to_list()}
    linker_input = cc_common.create_linker_input(
        owner = ctx.label,
        libraries = depset([library]),
        user_link_flags = ["-L" + libdir for libdir in libdirs] + ["-ljulia", "-ljulia-internal"],
        additional_inputs = toolchain_info.link_files,
    )

    linking_outputs = cc_common.link(
        actions = ctx.actions,
        name = "{}.sysimage".format(ctx.label.name),
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        output_type = "dynamic_library",
        linking_contexts = [cc_common.create_linking_context(
            linker_inputs = depset([linker_input]),
        )],
    )

    return linking_outputs.library_to_link.dynamic_library

def _julia_standalone_binary_impl(ctx):
    toolchain_info = ctx.toolchains[TOOLCHAIN_TYPE]
    if not toolchain_info.sysimage:
        fail("The Julia toolchain for {} does not provide a stock system image.".format(ctx.label))

    binary = ctx.attr.binary
    julia_info = binary[JuliaInfo]
    package = julia_info.app_name
    if not julia_info.entry:
        fail((
            "{} must be a Julia package: its entry point must be `{}.jl` (or `src/{}.jl`) " +
            "under `{}` and define `module {}` with a `julia_main()::Cint` function."
        ).format(binary.label, package, package, julia_info.include, package))

    archive = _emit_sysimage_object(ctx, julia_info = julia_info, toolchain_info = toolchain_info)
    sysimage = _link_sysimage(ctx, archive = archive, toolchain_info = toolchain_info)

    main = ctx.actions.declare_file("{}.main.jl".format(ctx.label.name))
    ctx.actions.write(
        output = main,
        content = "import {pkg}\nexit({pkg}.julia_main())\n".format(pkg = package),
    )

    return julia_common.create_julia_binary_impl(
        ctx = ctx,
        srcs = [main],
        deps = [binary],
        data_files = [],
        data_targets = [],
        env = {},
        main = main,
        sysimage = sysimage,
    )

julia_standalone_binary = rule(
    doc = """\
Build a Julia package and its dependencies into a custom system image and
produce an executable that starts Julia with it.

The system image is produced in two actions: `julia --output-o` emits the
object archive of the image, which is then linked into a shared library.
By default the link uses the `lld` bundled with Julia, the same way Julia
links its own package images; `--@rules_julia//julia/settings:linker=cc`
selects the C++ toolchain instead. The executable is the regular Julia
wrapper started with `--sysimage`, so all code is loaded precompiled and
startup is immediate. No network access or host tools outside the Bazel
toolchains are involved.

The target in `binary` must be a Julia package: its entry point is
`src/<name>.jl` defining `module <name>` with a `julia_main()::Cint` function,
which is called with the command line arguments in `ARGS`.

Example:

```python
julia_binary(
    name = "my_app_bin",
    srcs = ["src/my_app_bin.jl"],
    deps = ["//my/lib"],
)

julia_standalone_binary(
    name = "my_app",
    binary = ":my_app_bin",
)
```
""",
    implementation = _julia_standalone_binary_impl,
    attrs = {
        "binary": attr.label(
            doc = "The `julia_binary` (or `julia_library`) package to build into the system image.",
            mandatory = True,
            providers = [JuliaInfo],
        ),
        "cpu_target": attr.string(
            doc = (
                "The `--cpu-target` to compile the system image for. Defaults to the " +
                "toolchain's portable multi-versioned target for its architecture."
            ),
        ),
        "precompile_statements": attr.label_list(
            doc = (
                "Files of precompile statements (as produced by `julia --trace-compile`) " +
                "whose methods are compiled into the system image."
            ),
            allow_files = True,
        ),
        "_link_driver": attr.label(
            default = Label("//julia/private:link.jl"),
            allow_single_file = True,
        ),
        "_linker": attr.label(
            default = Label("//julia/settings:linker"),
        ),
        "_sysimage_driver": attr.label(
            default = Label("//julia/private:sysimage.jl"),
            allow_single_file = True,
        ),
    } | julia_common.BINARY_ATTRS,
    executable = True,
    toolchains = [
        TOOLCHAIN_TYPE,
        # Only used (and only required) when `//julia/settings:linker=cc`.
        config_common.toolchain_type(_CC_TOOLCHAIN_TYPE, mandatory = False),
    ],
    fragments = ["cpp"],
)
