"""JuliaPkgResolveInfo"""

JuliaPkgResolveInfo = provider(
    doc = "Components of resolving Julia manifests.",
    fields = {
        "manifest_bazel_json": "Optional[File]: The Bazel lockfile, when tracked.",
        "manifests": "list[struct]: One entry per manifest with fields `file` (File), `version` (str, the Julia version declared for it) and `runtime` (`ToolchainInfo` of a matching Julia toolchain).",
        "project_toml": "File: The Julia `Project.toml` file.",
    },
)
