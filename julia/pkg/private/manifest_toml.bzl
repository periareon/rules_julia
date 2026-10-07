"""Reading Julia `Manifest.toml` files.

Only `manifest_format = "2.0"` manifests (written by Julia 1.7 and newer) are
supported:

```toml
julia_version = "1.12.5"
manifest_format = "2.0"
project_hash = "f847120bcaa82ee658f012893bb6f1471266f52d"

[[deps.JuliaFormatter]]
deps = ["CommonMark", "Glob"]
git-tree-sha1 = "ca9470360f51697fc1bde747760b2d99936619ea"
uuid = "98e50ef6-434e-11e9-1051-2b60c6c9e899"
version = "2.2.0"
```
"""

load(":toml.bzl", "parse_toml")

def _package_entry(name, table, label):
    deps = table.get("deps", [])

    # When package names are ambiguous `Pkg` writes dependencies as an
    # inline table of `name = "uuid"`. Only the names are needed here.
    if type(deps) == "dict":
        deps = deps.keys()
    elif type(deps) != "list":
        fail("{}: unexpected value for `deps` of `{}`: `{}`".format(label, name, deps))

    uuid = table.get("uuid")
    if not uuid:
        fail("{}: package `{}` is missing a `uuid`".format(label, name))

    return {
        "deps": sorted(deps),
        "name": name,
        "path": table.get("path"),
        "repo_url": table.get("repo-url"),
        "tree_hash": table.get("git-tree-sha1"),
        "uuid": uuid,
        "version": table.get("version"),
    }

def parse_manifest_toml(content, label = "Manifest.toml"):
    """Parse the content of a Julia `Manifest.toml` file.

    Args:
        content (str): The text of the manifest.
        label (str): A human readable name for the manifest used in error messages.

    Returns:
        struct: With the following fields:
            - `julia_version` (str|None): The `julia_version` header.
            - `manifest_format` (str): The `manifest_format` header.
            - `project_hash` (str|None): The `project_hash` header.
            - `packages` (dict): A mapping of package name to a dict with keys
              `name`, `uuid`, `version`, `tree_hash`, `deps`, `path` and
              `repo_url`. `tree_hash` is `None` for standard library packages.
    """
    toml = parse_toml(content, label)

    manifest_format = str(toml.get("manifest_format", ""))
    if not manifest_format.startswith("2."):
        fail((
            "{}: unsupported `manifest_format = \"{}\"`. Only format 2.0 manifests " +
            "(written by Julia 1.7 and newer) are supported. Re-resolve the project with " +
            "a supported Julia to upgrade the manifest."
        ).format(label, manifest_format))

    deps = toml.get("deps", {})
    if type(deps) != "dict":
        fail("{}: `deps` is not a table".format(label))

    packages = {}
    for name, entries in deps.items():
        if type(entries) != "list":
            fail("{}: `deps.{}` is not an array of tables".format(label, name))
        if len(entries) != 1:
            fail((
                "{}: `{}` appears more than once. rules_julia identifies " +
                "packages by name so manifests with duplicate package names " +
                "are not supported."
            ).format(label, name))
        packages[name] = _package_entry(name, entries[0], label)

    return struct(
        julia_version = toml.get("julia_version"),
        manifest_format = manifest_format,
        packages = packages,
        project_hash = toml.get("project_hash"),
    )
