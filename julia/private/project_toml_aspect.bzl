"""Aspect for generating Project.toml files from Julia targets."""

load(":julia.bzl", "JuliaInfo", "compute_main")

BASE_UUID = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"

JuliaProjectTomlInfo = provider(
    doc = "Information about Project.toml files for Julia targets.",
    fields = {
        "dep_manifests": "Dict[str, File]: A mapping of app name to `Project.toml` file.",
        "dep_projects": "Dict[str, File]: A mapping of app name to `Manifest.toml` file.",
        "direct_deps": "List[str]: The app names of direct dependencies.",
        "main": "Optional[File]: The `main` entrypoint for binary files.",
        "root_manifest": "File: The root Manifest.toml file for this target",
        "root_project": "File: The root Project.toml file for this target",
    },
)

def _extract_tag_value(tags, prefix):
    """Extract value from tags with given prefix."""
    for tag in tags:
        if tag.startswith(prefix):
            return tag[len(prefix):]
    return None

def get_project_include(julia_info):
    include = julia_info.include
    if include.endswith("/src"):
        return include[:-len("/src")]
    return include

def _rlocationpath(file, workspace_name):
    """Convert a file to its runfiles location path."""
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]
    return "{}/{}".format(workspace_name, file.short_path)

def _julia_project_toml_aspect_impl(target, ctx):
    """Aspect implementation for generating Project.toml files."""

    # Only process Julia targets
    if JuliaInfo not in target:
        fail("JuliaInfo not present in {}".format(target.label))

    julia_info = target[JuliaInfo]

    # Create Project.toml file
    project_toml = ctx.actions.declare_file(target.label.name + ".Project.toml")
    manifest_toml = ctx.actions.declare_file(target.label.name + ".Manifest.toml")

    # Build arguments for the project_toml_generator
    args = ctx.actions.args()
    args.add("--label", str(target.label))
    args.add("--name", target.label.name)

    # Extract version and UUID from tags
    version = _extract_tag_value(ctx.rule.attr.tags, "julia_pkg_version=")
    if not version:
        version = "0.1.0"

    args.add("--version", version)

    uuid = _extract_tag_value(ctx.rule.attr.tags, "julia_pkg_uuid=")
    if uuid:
        args.add("--uuid", uuid)
    else:
        args.add("--base-uuid", BASE_UUID)

    args.add("--include", get_project_include(julia_info))
    args.add("--output", project_toml)
    args.add("--output-manifest", manifest_toml)

    # Collect Project.toml files from dependencies
    dep_projects = {}
    dep_manifests = {}
    direct_deps = []
    all_dep_files = []

    for dep in ctx.rule.attr.deps:
        dep_info = dep[JuliaInfo]
        args.add("--dep", "{}={}".format(dep_info.app_name, get_project_include(dep_info)))

        toml_info = dep[JuliaProjectTomlInfo]

        # Add direct dependency
        dep_projects[dep_info.app_name] = toml_info.root_project
        dep_manifests[dep_info.app_name] = toml_info.root_manifest
        direct_deps.append(dep_info.app_name)

        # Add all transitive dependencies from this dependency
        dep_projects.update(toml_info.dep_projects)
        dep_manifests.update(toml_info.dep_manifests)

        # Collect all files for inputs
        all_dep_files.extend([toml_info.root_project, toml_info.root_manifest])
        all_dep_files.extend(toml_info.dep_projects.values())
        all_dep_files.extend(toml_info.dep_manifests.values())

    for dep in dep_projects.values():
        dep_path, _, _ = _rlocationpath(dep, ctx.workspace_name).rpartition("/")
        args.add("--project", "{}={}".format(dep_path, dep.path))

    # Run the project_toml_generator
    ctx.actions.run(
        executable = ctx.executable._project_toml_generator,
        arguments = [args],
        outputs = [project_toml, manifest_toml],
        inputs = depset(all_dep_files),
        mnemonic = "JuliaGenProjectToml",
        progress_message = "Julia Project.toml %{label}",
        env = {
            "JULIA_PKG_OFFLINE": "true",
        },
    )

    expected = "src/{}.jl".format(target.label.name)

    main_file = None
    if hasattr(ctx.rule.attr, "main"):
        main_file = compute_main(target.label, ctx.rule.files.srcs, ctx.rule.file.main)
        if main_file.owner.name != expected:
            fail("`{}` is not a proper Julia project. `main` must be located at `{}` but was `{}`".format(
                target.label,
                expected,
                main_file.owner.name,
            ))
    else:
        found = False
        for src in ctx.rule.files.srcs:
            if src.owner.name == expected:
                found = True
                break
        if not found:
            fail("`{}` is not a proper Julia project. A src must be located at `{}`".format(
                target.label,
                expected,
            ))

    return [
        JuliaProjectTomlInfo(
            root_project = project_toml,
            root_manifest = manifest_toml,
            main = main_file,
            dep_projects = dep_projects,
            dep_manifests = dep_manifests,
            direct_deps = direct_deps,
        ),
        OutputGroupInfo(
            julia_project_toml = depset([project_toml]),
            julia_manifest_toml = depset([manifest_toml]),
        ),
    ]

julia_project_toml_aspect = aspect(
    doc = "Aspect that generates Project.toml files for Julia targets.",
    implementation = _julia_project_toml_aspect_impl,
    attr_aspects = ["deps"],
    attrs = {
        "_project_toml_generator": attr.label(
            default = Label("//julia/private/project_toml_generator"),
            executable = True,
            cfg = "exec",
        ),
    },
    provides = [JuliaProjectTomlInfo, OutputGroupInfo],
)
