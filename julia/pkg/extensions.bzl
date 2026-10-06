"""Julia Package Extensions"""

load("//julia/pkg/private:pkg.bzl", "install")

_DEFAULT_PKG_SERVER = "https://pkg.julialang.org"

_install_tag = tag_class(
    doc = """\
Fetch the Julia packages recorded in one or more `Manifest.toml` files, or in a
`Manifest.bazel.json`.

Exactly one of `manifests` (or the single-file alias `manifest`) or `lockfile`
must be set.

With `manifests`, the stock `Manifest.toml` files written by `Pkg` are the only
lockfiles. Each manifest records the Julia version that resolved it; its packages
are built for that Julia minor version and marked incompatible with others, and the
hub selects among manifests with `@rules_julia//julia/settings:version`. A project
supporting several Julia versions lists one manifest per minor version (Pkg's
`Manifest-v<major>.<minor>.toml` convention); `julia_pkg_compiler` resolves them all.
Package tarballs are fetched from `pkg_server` using the UUID and git tree hash
recorded for each package. On Bazel 9 and newer the integrity value of every tarball
and the artifacts each package declares are persisted in the `facts` section of
`MODULE.bazel.lock`, so after the first evaluation no network access is needed to
evaluate the extension. On older Bazel versions the generated repositories are
recorded in `MODULE.bazel.lock` instead.

With `lockfile`, a `Manifest.bazel.json` produced by `julia_pkg_compiler` provides
URLs, integrity values and artifacts up front and the extension never touches the
network. The lockfile carries no Julia version, so its packages are available under
every version. Prefer this for modules consumed by others, since facts are only
persisted in the root module's lockfile.
""",
    attrs = {
        "lockfile": attr.label(
            doc = "A `Manifest.bazel.json` lockfile produced by `julia_pkg_compiler`. Mutually exclusive with `manifests`.",
            allow_files = ["Manifest.bazel.json", ".json"],
            mandatory = False,
        ),
        "manifest": attr.label(
            doc = "A single `Manifest.toml`; shorthand for `manifests = [...]`.",
            allow_files = ["Manifest.toml", ".toml"],
            mandatory = False,
        ),
        "manifests": attr.label_list(
            doc = "`Manifest.toml` files, one per supported Julia minor version. Mutually exclusive with `lockfile`.",
            allow_files = [".toml"],
            mandatory = False,
        ),
        "name": attr.string(
            doc = "The name of the hub repository to create.",
            mandatory = True,
        ),
        "pkg_server": attr.string(
            doc = "The Julia package server to fetch tarballs from when `manifests` is set.",
            default = _DEFAULT_PKG_SERVER,
        ),
    },
)

_pkg_annotation_tag = tag_class(
    attrs = {
        "dep": attr.string(
            doc = "The name of the package to annotate",
            mandatory = True,
        ),
        "patch_args": attr.string_list(
            doc = "Arguments to pass to the patch tool. See `http_archive.patch_args`",
            mandatory = False,
        ),
        "patch_tool": attr.string(
            doc = "The patch tool to use. See `http_archive.patch_tool`",
            mandatory = False,
        ),
        "patches": attr.label_list(
            doc = "List of patch files to apply to the package. See `http_archive.patches`",
            allow_files = [".patch", ".diff"],
            mandatory = False,
        ),
    },
)

def _pkg_impl(module_ctx):
    root_module_direct_deps = []
    root_module_direct_dev_deps = []

    # Facts (Bazel 9+) persist package integrity values in `MODULE.bazel.lock`
    # so `Manifest.toml` alone is enough to reproduce a build.
    supports_facts = hasattr(module_ctx, "facts")
    facts = module_ctx.facts if supports_facts else {}
    new_facts = {}
    from_manifest = False

    for mod in module_ctx.modules:
        # Collect annotations from pkg_annotation tags in this module
        # Annotations apply to all install tags in the same module
        annotations = {}
        for annotation_attrs in mod.tags.pkg_annotation:
            package_name = annotation_attrs.dep

            annotation_data = {}
            if annotation_attrs.patches:
                annotation_data["patches"] = annotation_attrs.patches
            if annotation_attrs.patch_args:
                annotation_data["patch_args"] = annotation_attrs.patch_args
            if annotation_attrs.patch_tool:
                annotation_data["patch_tool"] = annotation_attrs.patch_tool

            annotations[package_name] = annotation_data

        # Process install tags with their annotations
        for install_attrs in mod.tags.install:
            result = install(
                module_ctx = module_ctx,
                attrs = install_attrs,
                annotations = annotations,
                facts = facts,
            )
            new_facts.update(result.facts)
            from_manifest = from_manifest or result.from_manifest
            if mod.is_root:
                if module_ctx.is_dev_dependency(install_attrs):
                    root_module_direct_dev_deps.append(result.hub)
                else:
                    root_module_direct_deps.append(result.hub)

    metadata_kwargs = {
        "root_module_direct_deps": root_module_direct_deps,
        "root_module_direct_dev_deps": root_module_direct_dev_deps,
    }

    if supports_facts:
        # Integrity values are universally true for a given URL, so the
        # extension stays reproducible as long as they are persisted.
        metadata_kwargs["facts"] = new_facts
        metadata_kwargs["reproducible"] = True
    else:
        # Without facts, let Bazel record the generated repositories (and
        # their integrity values) in the lockfile instead of re-downloading.
        metadata_kwargs["reproducible"] = not from_manifest

    return module_ctx.extension_metadata(**metadata_kwargs)

pkg = module_extension(
    doc = """\
A module extension for defining Julia package dependencies.

```python
pkg = use_extension("@rules_julia//julia/pkg:extensions.bzl", "pkg")
pkg.install(
    name = "my_deps",
    manifests = ["//:Manifest.toml"],
)
use_repo(pkg, "my_deps")
```

Each package in the manifests becomes a `julia_library` target available as
`@my_deps//:<PackageName>`. See the `install` tag for how integrity values and
multiple Julia versions are handled.
""",
    implementation = _pkg_impl,
    tag_classes = {
        "install": _install_tag,
        "pkg_annotation": _pkg_annotation_tag,
    },
)
