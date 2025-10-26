"""Julia bzlmod extensions"""

load(
    "//julia/private:toolchain_repo.bzl",
    "JULIA_DEFAULT_VERSION",
    "JULIA_VERSIONS",
    "TRIPLET_TO_CONSTRAINTS",
    "julia_toolchain_repository",
    "julia_toolchain_repository_hub",
)

def _find_modules(module_ctx):
    root = None
    for mod in module_ctx.modules:
        if mod.is_root:
            return mod

    return root

def _julia_impl(module_ctx):
    root = _find_modules(module_ctx)
    reproducible = True

    for attrs in root.tags.toolchain:
        if attrs.version not in JULIA_VERSIONS:
            fail("Julia toolchain hub `{}` was given unsupported version `{}`. Try: {}".format(
                attrs.name,
                attrs.version,
                JULIA_VERSIONS.keys(),
            ))
        available = JULIA_VERSIONS[attrs.version]
        toolchain_names = []
        toolchain_labels = {}
        exec_compatible_with = {}
        for triplet, info in available.items():
            tool_name = julia_toolchain_repository(
                name = "{}_{}".format(attrs.name, triplet.replace("-", "_")),
                version = attrs.version,
                triplet = triplet,
                url = info["url"],
                integrity = info["integrity"],
            )

            toolchain_names.append(tool_name)
            toolchain_labels[tool_name] = "@{}".format(tool_name)
            exec_compatible_with[tool_name] = TRIPLET_TO_CONSTRAINTS[triplet]

        julia_toolchain_repository_hub(
            name = attrs.name,
            toolchain_labels = toolchain_labels,
            toolchain_names = toolchain_names,
            exec_compatible_with = exec_compatible_with,
            target_compatible_with = {},
        )

    return module_ctx.extension_metadata(
        reproducible = reproducible,
    )

_TOOLCHAIN_TAG = tag_class(
    doc = "An extension for defining a `julia_toolchain` from a download archive.",
    attrs = {
        "name": attr.string(
            doc = "The name of the toolchain hub.",
            mandatory = True,
        ),
        "version": attr.string(
            doc = "The version of Julia to download.",
            default = JULIA_DEFAULT_VERSION,
        ),
    },
)

julia = module_extension(
    doc = "Bzlmod extensions for Julia",
    implementation = _julia_impl,
    tag_classes = {
        "toolchain": _TOOLCHAIN_TAG,
    },
)
