"""# Julia settings

Definitions for all `@rules_julia//julia` settings
"""

load(
    "@bazel_skylib//rules:common_settings.bzl",
    "string_flag",
)
load("//julia/private:versions.bzl", "JULIA_DEFAULT_VERSION", "JULIA_VERSIONS")

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
    """The version of julia to use"""
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
