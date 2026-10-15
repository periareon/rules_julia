"""Julia providers"""

JuliaInfo = provider(
    doc = "Information about a Julia library or binary target.",
    fields = {
        "app_name": "str: The Julia project app name.",
        "artifact_depots": "depset[str]: Runfiles-relative directories holding Julia artifacts (`artifacts/<git-tree-sha1>/`) of this target and its dependencies. Added to `DEPOT_PATH` alongside `depots`.",
        "depots": "depset[File]: Depot directories holding build-time precompile caches of this target and its dependencies.",
        "entry": "Optional[File]: The package entry point `<include>/<name>.jl`, if the target has one.",
        "include": "str: The primary include path of the current target (the package directory when it has a `Project.toml`, otherwise the directory holding the entry point).",
        "includes": "depset[str]: of include paths",
        "runfiles": "depset[File]: runfiles for this target",
        "srcs": "depset[File]: of Julia source files",
        "transitive_srcs": "depset[File]: of all Julia source files including transitive deps",
    },
)

JuliaArtifactVariantInfo = provider(
    doc = (
        "One build of a Julia artifact. Several variants of the same artifact may be " +
        "listed as dependencies; the one matching the toolchain's ABI is used."
    ),
    fields = {
        "artifact_name": "str: The artifact's name in `Artifacts.toml`.",
        "tags": "dict[str, str]: The variant's ABI tags (`libgfortran_version`, `cxxstring_abi`); empty when it fits any ABI.",
    },
)
