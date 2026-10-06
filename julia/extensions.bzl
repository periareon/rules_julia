"""Julia bzlmod extensions"""

load(
    "//julia/private:toolchain_repo.bzl",
    "JULIA_VERSIONS",
    "TRIPLET_TO_CONSTRAINTS",
    "julia_toolchain_repository",
    "julia_toolchain_repository_hub",
)
load("//julia/private:versions.bzl", "JULIA_DEFAULT_VERSION")

_toolchain_tag = tag_class(
    doc = "Request that a Julia version be made available via `@julia_toolchains`.",
    attrs = {
        "version": attr.string(
            doc = "A Julia version (e.g. `1.12.5`). Select it with `--@rules_julia//julia/settings:version`.",
            mandatory = True,
        ),
    },
)

def _julia_impl(module_ctx):
    reproducible = True

    # The default version is always registered. Additional versions are only
    # registered when requested so toolchain resolution stays cheap.
    versions = {JULIA_DEFAULT_VERSION: None}
    for mod in module_ctx.modules:
        for tag in mod.tags.toolchain:
            if tag.version not in JULIA_VERSIONS:
                fail("Module `{}` requested unknown Julia version `{}`. Known versions: {}".format(
                    mod.name,
                    tag.version,
                    ", ".join(JULIA_VERSIONS.keys()),
                ))
            versions[tag.version] = None

    toolchain_names = []
    toolchain_labels = {}
    target_settings = {}
    exec_compatible_with = {}
    target_compatible_with = {}
    for version in versions:
        for triplet, info in JULIA_VERSIONS[version].items():
            tool_name = julia_toolchain_repository(
                name = "julia_{}_{}".format(version, triplet.replace("-", "_")),
                version = version,
                triplet = triplet,
                url = info["url"],
                integrity = info["integrity"],
            )

            toolchain_names.append(tool_name)
            toolchain_labels[tool_name] = "@{}".format(tool_name)
            target_compatible_with[tool_name] = TRIPLET_TO_CONSTRAINTS[triplet]
            target_settings[tool_name] = ["@rules_julia//julia/settings:version_{}".format(version)]

    julia_toolchain_repository_hub(
        name = "julia_toolchains",
        toolchain_labels = toolchain_labels,
        toolchain_names = toolchain_names,
        exec_compatible_with = exec_compatible_with,
        target_compatible_with = target_compatible_with,
        target_settings = target_settings,
    )

    return module_ctx.extension_metadata(
        reproducible = reproducible,
    )

julia = module_extension(
    doc = "Bzlmod extensions for Julia",
    implementation = _julia_impl,
    tag_classes = {
        "toolchain": _toolchain_tag,
    },
)
