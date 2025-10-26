"""Julia toolchain repository configuration"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("//julia/private:versions.bzl", _JULIA_VERSIONS = "JULIA_VERSIONS")

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

# TODO: Going beyond this will break `julia_standalone_binary`
# https://github.com/JuliaLang/PackageCompiler.jl/issues/1066
JULIA_DEFAULT_VERSION = "1.11.7"

JULIA_VERSIONS = _JULIA_VERSIONS

_JULIA_TOOLCHAIN_BUILD_FILE_CONTENT = """\
load("@rules_julia//julia:julia_toolchain.bzl", "julia_toolchain")

filegroup(
    name = "julia_bin",
    srcs = ["{julia_bin}"],
    data = glob(
        include = ["**"],
        exclude = ["WORKSPACE", "BUILD", "*.bazel"],
    ),
    visibility = ["//visibility:public"],
)

julia_toolchain(
    name = "toolchain",
    julia = ":julia_bin",
    visibility = ["//visibility:public"],
)

alias(
    name = "{name}",
    actual = ":toolchain",
    visibility = ["//visibility:public"],
)
"""

def julia_toolchain_repository(*, name, version, triplet, url, integrity):
    """Download a version of Julia and instantiate targets for it.

    Args:
        name (str): The name of the repository to create.
        version (str): The version of Julia (e.g., "1.11.2").
        triplet (str): The target platform triplet (e.g., "x86_64-linux-gnu").
        url (str): The URL to fetch Julia from.
        integrity (str): The integrity checksum of the Julia archive.

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
            name = name,
            julia_bin = julia_bin,
        ),
    )

    return name

_BUILD_FILE_FOR_TOOLCHAIN_HUB_TEMPLATE = """
toolchain(
    name = "{name}",
    exec_compatible_with = {exec_constraint_sets_serialized},
    target_compatible_with = {target_constraint_sets_serialized},
    toolchain = "{toolchain}",
    toolchain_type = "@rules_julia//julia:toolchain_type",
    visibility = ["//visibility:public"],
)
"""

def _BUILD_for_toolchain_hub(
        toolchain_names,
        toolchain_labels,
        target_compatible_with,
        exec_compatible_with):
    return "\n".join([_BUILD_FILE_FOR_TOOLCHAIN_HUB_TEMPLATE.format(
        name = toolchain_name,
        exec_constraint_sets_serialized = json.encode(exec_compatible_with[toolchain_name]),
        target_constraint_sets_serialized = json.encode(target_compatible_with.get(toolchain_name, [])),
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
