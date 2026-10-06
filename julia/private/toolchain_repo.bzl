"""Julia toolchain repository configuration"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load(
    "//julia/private:versions.bzl",
    _JULIA_VERSIONS = "JULIA_VERSIONS",
)

TRIPLET_TO_CONSTRAINTS = {
    "aarch64-apple-darwin": ["@platforms//os:macos", "@platforms//cpu:aarch64"],
    "aarch64-linux-gnu": ["@platforms//os:linux", "@platforms//cpu:aarch64"],
    "i686-linux-gnu": ["@platforms//os:linux", "@platforms//cpu:i386"],
    "i686-w64-mingw32": ["@platforms//os:windows", "@platforms//cpu:i386"],
    "powerpc64le-linux-gnu": ["@platforms//os:linux", "@platforms//cpu:ppc64le"],
    "x86_64-apple-darwin": ["@platforms//os:macos", "@platforms//cpu:x86_64"],
    "x86_64-linux-gnu": ["@platforms//os:linux", "@platforms//cpu:x86_64"],
    "x86_64-unknown-freebsd": ["@platforms//os:freebsd", "@platforms//cpu:x86_64"],
    "x86_64-w64-mingw32": ["@platforms//os:windows", "@platforms//cpu:x86_64"],
}

JULIA_VERSIONS = _JULIA_VERSIONS

# Default `--cpu-target` per architecture. These match the multi-versioned
# targets used by Julia's release binaries and PackageCompiler apps, so a
# system image built on one machine runs on any machine of the architecture.
_CPU_TARGETS = {
    "aarch64": "generic",
    "i686": "pentium4;sandybridge,-xsaveopt,clone_all",
    "powerpc64le": "pwr8",
    "x86_64": "generic;sandybridge,-xsaveopt,clone_all;haswell,-rdrnd,base(1)",
}

_JULIA_TOOLCHAIN_BUILD_FILE_CONTENT = """\
load("@rules_julia//julia:julia_toolchain.bzl", "julia_toolchain")

# Everything needed to run `julia`: the executable, shared libraries, the
# system image, stdlib sources and their compiled caches, and certificates.
filegroup(
    name = "runtime_files",
    srcs = glob(
        include = [
            "bin/**",
            "etc/**",
            "lib/**",
            "libexec/**",
            "share/julia/**",
        ],
        exclude = [
            "share/julia/juliac/**",
            "share/julia/test/**",
        ],
    ),
    visibility = ["//visibility:public"],
)

filegroup(
    name = "julia_bin",
    srcs = ["{julia_bin}"],
    data = [":runtime_files"],
    visibility = ["//visibility:public"],
)

# The stock system image. Custom images are built on top of it.
filegroup(
    name = "sysimage",
    srcs = glob(
        include = [
            "lib/julia/sys.dll",
            "lib/julia/sys.dylib",
            "lib/julia/sys.so",
        ],
        allow_empty = True,
    ),
    visibility = ["//visibility:public"],
)

# The libraries a system image links against.
filegroup(
    name = "link_files",
    srcs = glob(
        include = [
            "bin/libjulia*.dll",
            "lib/julia/libjulia-internal*",
            "lib/libjulia*",
        ],
        allow_empty = True,
    ),
    visibility = ["//visibility:public"],
)

julia_toolchain(
    name = "toolchain",
    cpu_target = "{cpu_target}",
    julia = ":julia_bin",
    link_files = [":link_files"],
    linker = "{linker}",
    sysimage = ":sysimage",
    version = "{version}",
    visibility = ["//visibility:public"],
)

alias(
    name = "{name}",
    actual = ":toolchain",
    visibility = ["//visibility:public"],
)
"""

def julia_toolchain_repository(*, name, version, triplet, url, integrity, linker = "julia"):
    """Download a version of Julia and instantiate targets for it.

    Args:
        name (str): The name of the repository to create.
        version (str): The version of Julia (e.g., "1.11.2").
        triplet (str): The target platform triplet (e.g., "x86_64-linux-gnu").
        url (str): The URL to fetch Julia from.
        integrity (str): The integrity checksum of the Julia archive.
        linker (str): The default system image linker (`julia` or `cc`).

    Returns:
        str: Return `name` for convenience.
    """

    # Determine binary path: Windows uses .exe, others don't
    if "mingw" in triplet or "w64" in triplet:
        julia_bin = "bin/julia.exe"
    else:
        julia_bin = "bin/julia"

    # Julia archives unpack to julia-{version}/ directory
    strip_prefix = "julia-{}".format(version)

    http_archive(
        name = name,
        urls = [url],
        integrity = integrity,
        strip_prefix = strip_prefix,
        build_file_content = _JULIA_TOOLCHAIN_BUILD_FILE_CONTENT.format(
            cpu_target = _CPU_TARGETS.get(triplet.split("-")[0], "generic"),
            linker = linker,
            name = name,
            julia_bin = julia_bin,
            version = version,
        ),
    )

    return name

_BUILD_FILE_FOR_TOOLCHAIN_HUB_TEMPLATE = """
toolchain(
    name = "{name}",
    exec_compatible_with = {exec_constraint_sets_serialized},
    target_compatible_with = {target_constraint_sets_serialized},
    target_settings = {target_settings_serialized},
    toolchain = "{toolchain}",
    toolchain_type = "@rules_julia//julia:toolchain_type",
    visibility = ["//visibility:public"],
)
"""

def _BUILD_for_toolchain_hub(
        toolchain_names,
        toolchain_labels,
        target_compatible_with,
        exec_compatible_with,
        target_settings):
    return "\n".join([_BUILD_FILE_FOR_TOOLCHAIN_HUB_TEMPLATE.format(
        name = toolchain_name,
        exec_constraint_sets_serialized = json.encode(exec_compatible_with.get(toolchain_name, [])),
        target_constraint_sets_serialized = json.encode(target_compatible_with.get(toolchain_name, [])),
        target_settings_serialized = repr(target_settings.get(toolchain_name, None)),
        toolchain = toolchain_labels[toolchain_name],
    ) for toolchain_name in toolchain_names])

def _julia_toolchain_repository_hub_impl(repository_ctx):
    repository_ctx.file("WORKSPACE.bazel", """workspace(name = "{}")""".format(
        repository_ctx.name,
    ))

    repository_ctx.file("BUILD.bazel", _BUILD_for_toolchain_hub(
        toolchain_names = repository_ctx.attr.toolchain_names,
        toolchain_labels = repository_ctx.attr.toolchain_labels,
        target_compatible_with = repository_ctx.attr.target_compatible_with,
        exec_compatible_with = repository_ctx.attr.exec_compatible_with,
        target_settings = repository_ctx.attr.target_settings,
    ))

julia_toolchain_repository_hub = repository_rule(
    doc = (
        "Generates a toolchain-bearing repository that declares a set of Julia toolchains from other " +
        "repositories. This exists to allow registering a set of toolchains in one go with the `:all` target."
    ),
    attrs = {
        "exec_compatible_with": attr.string_list_dict(
            doc = "A list of constraints for the execution platform for this toolchain, keyed by toolchain name.",
            mandatory = True,
        ),
        "target_compatible_with": attr.string_list_dict(
            doc = "A list of constraints for the target platform for this toolchain, keyed by toolchain name.",
            mandatory = True,
        ),
        "target_settings": attr.string_list_dict(
            doc = "A list of constraints settings for the target platform for this toolchain, keyed by toolchain name.",
            mandatory = True,
        ),
        "toolchain_labels": attr.string_dict(
            doc = "The name of the toolchain implementation target, keyed by toolchain name.",
            mandatory = True,
        ),
        "toolchain_names": attr.string_list(
            mandatory = True,
        ),
    },
    implementation = _julia_toolchain_repository_hub_impl,
)
