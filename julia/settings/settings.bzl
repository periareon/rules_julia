"""# Julia settings

Definitions for all `@rules_julia//julia` settings
"""

load("@bazel_skylib//lib:selects.bzl", "selects")
load(
    "@bazel_skylib//rules:common_settings.bzl",
    "string_flag",
)
load("//julia/private:versions.bzl", "JULIA_DEFAULT_VERSION", "JULIA_VERSIONS")

def julia_minor_version(version):
    """Return the `<major>.<minor>` prefix of a Julia version string.

    Args:
        version (str): A Julia version such as `1.12.5`.

    Returns:
        str: The minor version, e.g. `1.12`.
    """
    return ".".join(version.split(".")[:2])

def julia_minor_versions():
    """The minor versions (`1.10`, `1.12`, ...) with known toolchains.

    Returns:
        list[str]: Sorted minor versions.
    """
    minors = {}
    for version in JULIA_VERSIONS.keys():
        minors[julia_minor_version(version)] = True
    return sorted(minors.keys(), key = lambda v: [int(p) for p in v.split(".")])

def formatter_config(name = "formatter_config"):
    """The [JuliaFormatter](https://domluna.github.io/JuliaFormatter.jl/stable/) config file to use in formatting rules.
    """
    native.label_flag(
        name = name,
        build_setting_default = ".JuliaFormatter.toml",
    )

def linker(name = "linker"):
    """The linker used to turn a system image object archive into a shared library.

    - `toolchain` (default): whatever the resolved Julia toolchain's `linker` attribute
      says (`julia` for toolchains registered by the `julia` extension unless a
      `julia.toolchain(linker = ...)` tag says otherwise).
    - `julia`: the `lld` bundled with Julia, invoked through `Base.Linking` exactly as
      Julia links its own package images. Works on every platform Julia ships for and
      needs no C++ toolchain.
    - `cc`: `cc_common.link` with the resolved C++ toolchain. Requires a GNU-compatible
      toolchain; fails if no C++ toolchain resolves.
    """
    string_flag(
        name = name,
        values = ["toolchain", "julia", "cc"],
        build_setting_default = "toolchain",
    )

def version(name = "version"):
    """The version of julia to use.

    Besides the flag, a `config_setting` named `version_<major>.<minor>.<patch>`
    is defined per known release and a `version_<major>.<minor>` setting per
    minor version matching any of its releases. Package graphs resolved for a
    Julia minor version are selected with the latter.

    Args:
        name (str): The name of the flag.
    """
    string_flag(
        name = name,
        values = JULIA_VERSIONS.keys(),
        build_setting_default = JULIA_DEFAULT_VERSION,
    )

    for ver in JULIA_VERSIONS.keys():
        native.config_setting(
            name = "{}_{}".format(name, ver),
            flag_values = {str(Label("//julia/settings:{}".format(name))): ver},
        )

    for minor in julia_minor_versions():
        selects.config_setting_group(
            name = "{}_{}".format(name, minor),
            match_any = [
                ":{}_{}".format(name, ver)
                for ver in JULIA_VERSIONS.keys()
                if julia_minor_version(ver) == minor
            ],
        )
