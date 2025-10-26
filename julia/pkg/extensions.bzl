"""Julia Package Extensions"""

load("//julia/pkg/private:pkg.bzl", "install")

_install_tag = tag_class(
    attrs = {
        "lockfile": attr.label(
            doc = "The Manifest.bazel.json lockfile with SHA256 hashes for all packages.",
            allow_files = ["Manifest.bazel.json", ".json"],
            mandatory = True,
        ),
        "manifest": attr.label(
            doc = "The Manifest.toml lockfile associated with Project.toml (deprecated, use lockfile instead).",
            allow_files = ["Manifest.toml", ".toml"],
            mandatory = False,
        ),
        "name": attr.string(
            doc = "The name of the module to create",
            mandatory = True,
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
            doc = "Arguments to pass to the patch tool. See http_archive.patch_args",
            mandatory = False,
        ),
        "patch_tool": attr.string(
            doc = "The patch tool to use. See http_archive.patch_tool",
            mandatory = False,
        ),
        "patches": attr.label_list(
            doc = "List of patch files to apply to the package. See http_archive.patches",
            allow_files = [".patch"],
            mandatory = False,
        ),
    },
)

def _pkg_impl(module_ctx):
    root_module_direct_deps = []
    root_module_direct_dev_deps = []

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
            hub = install(
                module_ctx = module_ctx,
                attrs = install_attrs,
                annotations = annotations,
            )
            root_module_direct_deps.append(hub)

    return module_ctx.extension_metadata(
        reproducible = True,
        root_module_direct_deps = root_module_direct_deps,
        root_module_direct_dev_deps = root_module_direct_dev_deps,
    )

pkg = module_extension(
    doc = "A module for defining Julia package dependencies.",
    implementation = _pkg_impl,
    tag_classes = {
        "install": _install_tag,
        "pkg_annotation": _pkg_annotation_tag,
    },
)
