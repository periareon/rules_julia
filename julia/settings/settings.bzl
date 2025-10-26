"""# Julia settings

Definitions for all `@rules_julia//julia` settings
"""

load(
    "@bazel_skylib//rules:common_settings.bzl",
    "bool_flag",
)

def experimental_entrypoint_use_include():
    """A flag to control whether or not `julia_binary` and `julia_test` should use \
    [`include`](https://docs.julialang.org/en/v1/base/base/#include) vs [`run`](https://docs.julialang.org/en/v1/base/base/#Base.run) \
    to launch `main`.
    """
    bool_flag(
        name = "experimental_entrypoint_use_include",
        build_setting_default = False,
    )

# buildifier: disable=unnamed-macro
def julia_formatter_config():
    """The [JuliaFormatter](https://domluna.github.io/JuliaFormatter.jl/stable/) config file to use in formatting rules.
    """
    native.label_flag(
        name = "julia_formatter_config",
        build_setting_default = ".JuliaFormatter.toml",
    )
