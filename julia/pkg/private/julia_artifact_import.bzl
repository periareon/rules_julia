"""The `julia_artifact_import` rule."""

load("//julia/private:providers.bzl", "JuliaArtifactVariantInfo", "JuliaInfo")

def _julia_artifact_import_impl(ctx):
    # The repository root doubles as a depot: files live under
    # `artifacts/<tree_hash>/`, which is where Julia looks for them.
    depot = ctx.label.workspace_name
    if ctx.label.package:
        depot = "{}/{}".format(depot, ctx.label.package)

    files = depset(ctx.files.srcs)
    runfiles = ctx.runfiles(files = ctx.files.srcs)

    return [
        DefaultInfo(
            files = files,
            runfiles = runfiles,
        ),
        JuliaArtifactVariantInfo(
            artifact_name = ctx.attr.artifact_name,
            tags = ctx.attr.platform_tags,
        ),
        JuliaInfo(
            app_name = ctx.attr.artifact_name,
            srcs = depset(),
            transitive_srcs = depset(),
            include = "",
            includes = depset(),
            runfiles = runfiles,
            depots = depset(),
            artifact_depots = depset([depot]),
            entry = None,
        ),
    ]

julia_artifact_import = rule(
    doc = """\
A prebuilt Julia artifact, consumable as a dependency of Julia targets.

The rule contributes no sources. It adds the artifact's files to runfiles and
its directory to the depots Julia searches, so `artifact"name"` lookups and
JLL packages find the files at build and run time.
""",
    implementation = _julia_artifact_import_impl,
    attrs = {
        "artifact_name": attr.string(
            doc = "The name of the artifact in `Artifacts.toml`.",
            mandatory = True,
        ),
        "platform_tags": attr.string_dict(
            doc = (
                "ABI tags of this variant (`libgfortran_version` as a major version, `cxxstring_abi`). " +
                "When several variants of one artifact are dependencies of a target, the one matching " +
                "the Julia toolchain's ABI is used and the others are dropped."
            ),
            default = {},
        ),
        "srcs": attr.label_list(
            doc = "All files of the artifact, under `artifacts/<tree_hash>/`.",
            allow_files = True,
        ),
        "tree_hash": attr.string(
            doc = "The git tree hash identifying the artifact.",
            mandatory = True,
        ),
    },
    provides = [JuliaArtifactVariantInfo, JuliaInfo],
)
