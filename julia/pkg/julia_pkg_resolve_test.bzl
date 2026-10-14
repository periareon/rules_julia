"""Rules for testing Julia Manifest synchronization"""

load("//julia/pkg/private:julia_pkg_resolve_info.bzl", "JuliaPkgResolveInfo")
load("//julia/private:julia_common.bzl", "julia_common")
load("//julia/private:providers.bzl", "JuliaInfo")

def _julia_pkg_resolve_test_impl(ctx):
    resolver_info = ctx.attr.resolver[JuliaPkgResolveInfo]
    project_toml = resolver_info.project_toml
    manifest_bazel_json = resolver_info.manifest_bazel_json
    workspace_name = ctx.workspace_name

    # Each manifest is verified by the Julia it is declared for. The runtimes
    # come from the resolver so the version list lives in one place.
    runtime_files = []
    entries = []
    for entry in resolver_info.manifests:
        runtime_files.append(entry.runtime.all_files)
        entries.append("|".join([
            entry.version,
            julia_common.rlocationpath(entry.file, workspace_name),
            julia_common.rlocationpath(entry.runtime.julia, workspace_name),
        ]))

    curated_data_files = [project_toml, ctx.file._core] + [entry.file for entry in resolver_info.manifests]
    curated_env = {
        "RULES_JULIA_PKG_TEST_CORE": julia_common.rlocationpath(ctx.file._core, workspace_name),
        "RULES_JULIA_PKG_TEST_MANIFESTS": ";".join(entries),
        "RULES_JULIA_PKG_TEST_PROJECT_TOML": julia_common.rlocationpath(project_toml, workspace_name),
        "RULES_JULIA_PKG_TEST_RESOLVER_LABEL": str(ctx.attr.resolver.label),
    }

    # The Bazel lockfile is optional. When tracked it is verified as well.
    if manifest_bazel_json:
        curated_data_files.append(manifest_bazel_json)
        curated_env["RULES_JULIA_PKG_TEST_MANIFEST_BAZEL_JSON"] = julia_common.rlocationpath(manifest_bazel_json, workspace_name)

    return julia_common.create_julia_binary_impl(
        ctx = ctx,
        srcs = [ctx.file._test_runner_main],
        deps = [ctx.attr._runfiles_lib],
        data_files = curated_data_files + depset(transitive = runtime_files).to_list(),
        data_targets = [],
        env = curated_env,
        main = ctx.file._test_runner_main,
    )

julia_pkg_resolve_test = rule(
    doc = """\
A test rule that verifies the manifests managed by `julia_pkg_resolve` are up to date.

Every manifest is checked under a Julia toolchain of the version it is declared
for, by comparing the manifest's recorded `project_hash` with the hash of the
current `Project.toml`. Pkg's hash algorithm differs between Julia minor versions,
which is why the resolver's declaration drives which Julia runs each check.
When the resolver also tracks a `Manifest.bazel.json`, that file is checked
against the manifest as well.

The test will fail if:
- A manifest is out of date with respect to `Project.toml`
- A manifest was resolved with a different Julia minor version than declared
- A package is missing from `Manifest.bazel.json`
- Versions or UUIDs don't match between the manifest and `Manifest.bazel.json`
- The git-tree-sha1 is not in the package URL
- Integrity values are missing

Example:

```python
julia_pkg_resolve(
    name = "pkg_update",
    project_toml = "Project.toml",
    manifests = {"Manifest.toml": "1.12"},
)

julia_pkg_resolve_test(
    name = "pkg_sync_test",
    resolver = ":pkg_update",
)
```

Then run:

```sh
bazel test //:pkg_sync_test
```

If the files are out of sync the test fails with details on what needs to be
regenerated.
""",
    implementation = _julia_pkg_resolve_test_impl,
    attrs = {
        "resolver": attr.label(
            doc = "The `julia_pkg_resolve` target whose manifests are checked.",
            providers = [JuliaPkgResolveInfo],
            mandatory = True,
        ),
        "_core": attr.label(
            doc = "The per-manifest check, run with the manifest's Julia.",
            allow_single_file = [".jl"],
            default = Label("//julia/pkg/private:pkg_tester_core.jl"),
        ),
        "_runfiles_lib": attr.label(
            providers = [JuliaInfo],
            default = Label("//julia/runfiles"),
        ),
        "_test_runner_main": attr.label(
            doc = "The test runner's main source file.",
            allow_single_file = [".jl"],
            default = Label("//julia/pkg/private:pkg_tester.jl"),
        ),
    } | julia_common.BINARY_ATTRS,
    test = True,
    toolchains = [julia_common.TOOLCHAIN_TYPE],
)
