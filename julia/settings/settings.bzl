"""# Julia settings

Definitions for all `@rules_julia//julia` settings
"""

load(
    "@bazel_skylib//rules:common_settings.bzl",
    "string_flag",
)
load("//julia/private:versions.bzl", "JULIA_DEFAULT_VERISON", "JULIA_VERSIONS")

def formatter_config(name = "formatter_config"):
    """The [JuliaFormatter](https://domluna.github.io/JuliaFormatter.jl/stable/) config file to use in formatting rules.
    """
    native.label_flag(
        name = name,
        build_setting_default = ".JuliaFormatter.toml",
    )

def version(name = "version"):
    """The version of julia to use"""
    string_flag(
        name = name,
        values = JULIA_VERSIONS.keys(),
        build_setting_default = JULIA_DEFAULT_VERISON,
    )

    for ver in JULIA_VERSIONS.keys():
        native.config_setting(
            name = "{}_{}".format(name, ver),
            flag_values = {str(Label("//julia/settings:{}".format(name))): ver},
        )
