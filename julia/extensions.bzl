"""Julia bzlmod extensions"""

load(
    "//julia/private:toolchain_repo.bzl",
    "JULIA_VERSIONS",
    "TRIPLET_TO_CONSTRAINTS",
    "julia_toolchain_repository",
    "julia_toolchain_repository_hub",
)

def _julia_impl(module_ctx):
    reproducible = True

    toolchain_names = []
    toolchain_labels = {}
    target_settings = {}
    exec_compatible_with = {}
    target_compatible_with = {}
    for version, available in JULIA_VERSIONS.items():
        for triplet, info in available.items():
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
)
