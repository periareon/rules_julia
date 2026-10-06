"""Rules for generating Julia manifests from Project.toml"""

load("//julia/pkg/private:julia_pkg_compile_info.bzl", "JuliaPkgCompileInfo")
load("//julia/pkg/private:julia_runtime.bzl", "JuliaRuntimeInfo")
load("//julia/pkg/private:julia_version.bzl", "MANIFESTS_ATTR_DOC", "julia_versions_split")
load("//julia/private:julia_common.bzl", "julia_common")
load("//julia/private:providers.bzl", "JuliaInfo")

def _manifest_entries(ctx):
    """Pair every manifest with its declared version and a matching runtime."""
    runtimes = {}
    for version, target in ctx.split_attr._runtime.items():
        runtimes[version] = target[JuliaRuntimeInfo]

    entries = []
    for target, version in ctx.attr.manifests.items():
        files = target.files.to_list()
        if len(files) != 1:
            fail("`manifests` keys must be single files, got {} for {}".format(target.label, ctx.label))
        manifest = files[0]
        if not manifest.is_source:
            fail("`{}` cannot be generated. Please update it to be a source file for {}".format(manifest.short_path, ctx.label))
        if version not in runtimes:
            fail("No Julia runtime was configured for version `{}` of {}".format(version, ctx.label))
        entries.append(struct(
            file = manifest,
            version = version,
            runtime = runtimes[version],
        ))
    return sorted(entries, key = lambda entry: entry.version)

def _julia_pkg_compiler_impl(ctx):
    project_toml = ctx.file.project_toml
    if not project_toml.is_source:
        fail("`project_toml` cannot be generated. Please update it to be a source file for {}".format(ctx.label))

    entries = _manifest_entries(ctx)

    manifest_bazel_json = ctx.file.manifest_bazel_json
    if manifest_bazel_json:
        if not manifest_bazel_json.is_source:
            fail("`manifest_bazel_json` cannot be generated. Please update it to be a source file for {}".format(ctx.label))
        if len(entries) != 1:
            fail("`manifest_bazel_json` is only supported with a single manifest; {} declares {}".format(ctx.label, len(entries)))

    workspace_name = ctx.workspace_name
    env = {
        "RULES_JULIA_PKG_COMPILER_MANIFESTS": ";".join([
            "|".join([
                entry.version,
                entry.file.short_path,
                julia_common.rlocationpath(entry.runtime.julia, workspace_name),
            ])
            for entry in entries
        ]),
        "RULES_JULIA_PKG_COMPILER_PROJECT_TOML": project_toml.short_path,
        "RULES_JULIA_PKG_COMPILER_SCRIPT": julia_common.rlocationpath(ctx.file._compiler_script, workspace_name),
    }
    if manifest_bazel_json:
        env["RULES_JULIA_PKG_COMPILER_MANIFEST_BAZEL_JSON"] = manifest_bazel_json.short_path

    data_files = [ctx.file._compiler_script]
    data_targets = [target for target in ctx.split_attr._runtime.values()]

    providers = julia_common.create_julia_binary_impl(
        ctx = ctx,
        srcs = [ctx.file._driver_main],
        deps = [ctx.attr._runfiles_lib],
        data_files = data_files,
        data_targets = data_targets,
        env = env,
        main = ctx.file._driver_main,
    )

    return providers + [
        JuliaPkgCompileInfo(
            manifest_bazel_json = manifest_bazel_json,
            manifests = entries,
            project_toml = project_toml,
        ),
    ]

julia_pkg_compiler = rule(
    doc = """\
A rule for resolving Julia manifests from `Project.toml` using Julia's Pkg manager.

Running the target resolves the project once per manifest listed in `manifests`,
each time with a Julia toolchain of the version the manifest is declared for, and
writes the results in place. Pkg resolves against one Julia version (its standard
libraries, compat bounds and manifest format), so a project supporting several
Julia minor versions carries one manifest per version, following Pkg's own
`Manifest-v<major>.<minor>.toml` convention. Pass the manifests to the `pkg`
module extension via `pkg.install(manifests = ...)`; no additional lockfile is
required.

Optionally, `manifest_bazel_json` may be set (with a single manifest) to also
write a `Manifest.bazel.json` containing package URLs, integrity values and
artifacts. Pass that file to `pkg.install(lockfile = ...)` for modules consumed
by other Bazel modules, since module extension facts are only persisted in the
root module's `MODULE.bazel.lock`.

Note that when setting this target up for the first time, empty manifest files
need to be created. If you specify `manifest_bazel_json`, that file should also
be created as an empty JSON object `{}`.

Example:

```python
julia_pkg_compiler(
    name = "pkg_update",
    project_toml = "Project.toml",
    manifests = {
        "Manifest-v1.10.toml": "1.10",
        "Manifest-v1.12.toml": "1.12",
    },
)
```

Then run:

```sh
bazel run //:pkg_update
```

Packages can be added to `Project.toml` at the same time:

```sh
bazel run //:pkg_update -- --add JSON
```
""",
    implementation = _julia_pkg_compiler_impl,
    attrs = {
        "manifest_bazel_json": attr.label(
            doc = "An optional `Manifest.bazel.json` lockfile to generate/update with package URLs, integrity values and artifacts. Only supported with a single manifest.",
            allow_single_file = [".json"],
            mandatory = False,
        ),
        "manifests": attr.label_keyed_string_dict(
            doc = MANIFESTS_ATTR_DOC,
            allow_files = [".toml"],
            mandatory = True,
        ),
        "project_toml": attr.label(
            doc = "The `Project.toml` file describing dependencies.",
            allow_single_file = ["Project.toml", ".toml"],
            mandatory = True,
        ),
        "_allowlist_function_transition": attr.label(
            default = Label("@bazel_tools//tools/allowlists/function_transition_allowlist"),
        ),
        "_compiler_script": attr.label(
            doc = "The resolver, run once per manifest with the matching Julia.",
            allow_single_file = [".jl"],
            default = Label("//julia/pkg/private:pkg_compiler.jl"),
        ),
        "_driver_main": attr.label(
            doc = "The driver launching the resolver per manifest.",
            allow_single_file = [".jl"],
            default = Label("//julia/pkg/private:pkg_compiler_driver.jl"),
        ),
        "_runfiles_lib": attr.label(
            providers = [JuliaInfo],
            default = Label("//julia/runfiles"),
        ),
        "_runtime": attr.label(
            doc = "A Julia interpreter per declared version.",
            cfg = julia_versions_split,
            providers = [JuliaRuntimeInfo],
            default = Label("//julia/pkg/private:julia_runtime"),
        ),
    } | julia_common.BINARY_ATTRS,
    executable = True,
    toolchains = [julia_common.TOOLCHAIN_TYPE],
)
