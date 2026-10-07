"""Running Pkg rules under the Julia versions manifests are resolved with.

`Pkg` resolves a project against one Julia and records that version in the
manifest; the project hash it writes is only comparable under the same minor
version. Rules that resolve or verify manifests therefore run Julia of the
matching version, whatever `--@rules_julia//julia/settings:version` selects
elsewhere in the build.
"""

load("//julia/private:versions.bzl", "JULIA_VERSIONS")
load("//julia/settings:settings.bzl", "julia_minor_version", "julia_minor_versions")

_VERSION_FLAG = str(Label("//julia/settings:version"))

def _version_key(version):
    return [int(part) if part.isdigit() else -1 for part in version.split(".")]

def resolve_julia_version(version):
    """Map a Julia version onto one with a known toolchain.

    Args:
        version (str): A Julia version such as `1.12.5` or `1.12`.

    Returns:
        str: `version` itself when a toolchain for it is known, otherwise the
            newest known patch release of the same minor version. Pkg's
            project hash is stable within a minor version, so any patch
            release verifies a manifest resolved by another.
    """
    if version in JULIA_VERSIONS:
        return version

    parts = version.split(".")
    if len(parts) < 2 or not parts[0].isdigit() or not parts[1].isdigit():
        fail("`{}` is not a Julia version of the form `<major>.<minor>[.<patch>]`".format(version))
    minor = julia_minor_version(version)
    candidates = sorted(
        [known for known in JULIA_VERSIONS.keys() if julia_minor_version(known) == minor],
        key = _version_key,
    )
    if not candidates:
        fail("No Julia toolchain is known for version `{}`. Known minor versions: {}".format(
            version,
            ", ".join(julia_minor_versions()),
        ))
    return candidates[-1]

def _manifest_versions(attr):
    """The distinct Julia versions requested by a rule's `manifests` attribute."""
    versions = {}
    for version in attr.manifests.values():
        versions[version] = True
    return sorted(versions.keys(), key = _version_key)

def _julia_versions_split_impl(_settings, attr):
    return {
        version: {_VERSION_FLAG: resolve_julia_version(version)}
        for version in _manifest_versions(attr)
    }

julia_versions_split = transition(
    implementation = _julia_versions_split_impl,
    inputs = [],
    outputs = [_VERSION_FLAG],
)

MANIFESTS_ATTR_DOC = (
    "Julia manifests keyed by the Julia version each is resolved with, e.g. " +
    "`{\"Manifest-v1.10.toml\": \"1.10\", \"Manifest-v1.12.toml\": \"1.12\"}`. A project " +
    "supporting a single Julia version lists one `Manifest.toml`. Each manifest is " +
    "resolved and verified under a registered toolchain of that version (the newest " +
    "known patch release when only a minor version is given), regardless of " +
    "`--@rules_julia//julia/settings:version`."
)
