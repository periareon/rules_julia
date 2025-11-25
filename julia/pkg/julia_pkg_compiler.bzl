"""Rules for generating Julia Manifest.toml from Project.toml"""

load("//julia/pkg/private:julia_pkg_compile_info.bzl", "JuliaPkgCompileInfo")

def _julia_pkg_compiler_impl(ctx):
    project_toml = ctx.file.project_toml
    manifest_toml = ctx.file.manifest_toml

    if not project_toml.is_source:
        fail("`project_toml` cannot be generated. Please update it to be a source file for {}".format(ctx.label))
    if not manifest_toml.is_source:
        fail("`manifest_toml` cannot be generated. Please update it to be a source file for {}".format(ctx.label))

    compiler = ctx.executable._compiler
    executable = ctx.actions.declare_file("{}.{}".format(ctx.label.name, compiler.extension).rstrip("."))
    ctx.actions.symlink(
        output = executable,
        target_file = compiler,
        is_executable = True,
    )

    env = {
        "RULES_JULIA_PKG_COMPILER_MANIFEST_TOML": manifest_toml.short_path,
        "RULES_JULIA_PKG_COMPILER_PROJECT_TOML": project_toml.short_path,
    }

    manifest_bazel_json = ctx.file.manifest_bazel_json
    if manifest_bazel_json:
        if not manifest_bazel_json.is_source:
            fail("`manifest_bazel_json` cannot be generated. Please update it to be a source file for {}".format(ctx.label))
        env["RULES_JULIA_PKG_COMPILER_MANIFEST_BAZEL_JSON"] = manifest_bazel_json.short_path

    runfiles = ctx.runfiles(files = [project_toml]).merge(ctx.attr._compiler[DefaultInfo].default_runfiles)

    return [
        JuliaPkgCompileInfo(
            manifest_bazel_json = manifest_bazel_json,
            manifest_toml = manifest_toml,
            project_toml = project_toml,
        ),
        DefaultInfo(
            executable = executable,
            runfiles = runfiles,
        ),
        RunEnvironmentInfo(
            environment = env,
        ),
    ]

julia_pkg_compiler = rule(
    doc = """\
A rule for generating Manifest.toml and Manifest.bazel.json from Project.toml using Julia's Pkg manager.

This rule uses Julia's native package manager to resolve dependencies and generate
a Manifest.toml lockfile and a Manifest.bazel.json file with SHA256 hashes. The
Manifest.bazel.json can then be used with the `pkg` module extension to fetch and
build Julia packages hermetically with cryptographic verification.

The `manifest_bazel_json` attribute is optional. If not specified, the Manifest.bazel.json
file will be written next to the Manifest.toml file.

Note that when setting this target up for the first time, an empty Manifest.toml file
will need to be created. If you specify `manifest_bazel_json`, that file should also be
created as an empty JSON object `{}`.

Example:

```python
julia_pkg_compiler(
    name = "pkg_update",
    project_toml = "Project.toml",
    manifest_toml = "Manifest.toml",
    # manifest_bazel_json is optional - defaults to Manifest.bazel.json next to Manifest.toml
)
```

Then run:

```sh
bazel run //:pkg_update
```

This will update Manifest.toml with resolved package versions and Manifest.bazel.json
with SHA256 hashes for all packages and their dependency graph.
""",
    implementation = _julia_pkg_compiler_impl,
    attrs = {
        "manifest_bazel_json": attr.label(
            doc = "The location of the Manifest.bazel.json lockfile to generate/update with SHA256 hashes. If not specified, defaults to Manifest.bazel.json next to the manifest_toml file.",
            allow_single_file = [".json"],
            mandatory = False,
        ),
        "manifest_toml": attr.label(
            doc = "The location of the Manifest.toml lockfile to generate/update.",
            allow_single_file = ["Manifest.toml", ".toml"],
            mandatory = True,
        ),
        "project_toml": attr.label(
            doc = "The `Project.toml` file describing dependencies.",
            allow_single_file = ["Project.toml", ".toml"],
            mandatory = True,
        ),
        "_compiler": attr.label(
            executable = True,
            cfg = "target",
            default = Label("//julia/pkg/private:pkg_compiler"),
        ),
    },
    executable = True,
)
