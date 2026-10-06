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

    # Every module's hubs are created. The root module is processed first so
    # its hubs are defined before any dependency's; a hub name declared by more
    # than one module is an error rather than a silent override.
    modules = sorted(module_ctx.modules, key = lambda mod: 0 if mod.is_root else 1)
    hub_owners = {}

    for mod in modules:
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
            owner = hub_owners.get(install_attrs.name)
            if owner != None:
                fail("The `pkg` hub `{}` is declared by both module `{}` and module `{}`. Hub names must be unique.".format(
                    install_attrs.name,
                    owner,
                    mod.name,
                ))
            hub_owners[install_attrs.name] = mod.name

            hub = install(
                module_ctx = module_ctx,
                attrs = install_attrs,
                annotations = annotations,
            )

            # Only the root module's hubs are reported as its direct deps. Hubs
            # from other modules (e.g. rules_julia's own) must not be reported or
            # every downstream root module would be told to `use_repo` them.
            if mod.is_root:
                if module_ctx.is_dev_dependency(install_attrs):
                    root_module_direct_dev_deps.append(hub)
                else:
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
