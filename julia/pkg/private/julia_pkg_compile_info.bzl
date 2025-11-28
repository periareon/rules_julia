"""JuliaPkgCompileInfo"""

JuliaPkgCompileInfo = provider(
    doc = "Components of compiling Julia lock files.",
    fields = {
        "manifest_bazel_json": "File: The optional Bazel output file.",
        "manifest_toml": "File: The Julia `Manifest.toml` file.",
        "project_toml": "File: The Julia `Project.toml` file.",
    },
)
