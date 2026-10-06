"""JuliaPkgCompileInfo"""

JuliaPkgCompileInfo = provider(
    doc = "Components of compiling Julia lock files.",
    fields = {
        "manifest_bazel_json": "Optional[File]: The Bazel lockfile, when tracked.",
        "manifests": "list[struct]: One entry per manifest with fields `file` (File), `version` (str, the Julia version declared for it) and `runtime` (JuliaRuntimeInfo of a matching toolchain).",
        "project_toml": "File: The Julia `Project.toml` file.",
    },
)
