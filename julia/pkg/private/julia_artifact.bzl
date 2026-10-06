"""The `julia_artifact` rule."""

load("//julia/private:providers.bzl", "JuliaInfo")

def _julia_artifact_impl(ctx):
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

julia_artifact = rule(
    doc = """\
A prebuilt Julia artifact, consumable as a dependency of Julia targets.

The rule contributes no sources. It adds the artifact's files to runfiles and
its directory to the depots Julia searches, so `artifact"name"` lookups and
JLL packages find the files at build and run time.
""",
    implementation = _julia_artifact_impl,
    attrs = {
        "artifact_name": attr.string(
            doc = "The name of the artifact in `Artifacts.toml`.",
            mandatory = True,
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
    provides = [JuliaInfo],
)
