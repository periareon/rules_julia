"""Tests for the `julia_toolchain` rule and the toolchain hub."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("//julia/private:toolchain_repo.bzl", "toolchain_hub_build_content")

def _julia_cfg_impl(ctx):
    env = analysistest.begin(ctx)
    julia = analysistest.target_under_test(env)[platform_common.ToolchainInfo].julia

    # Binaries and tests run the toolchain's Julia on the target platform, so
    # it must be built in the target configuration. Build-time actions resolve
    # the toolchain for the execution platform instead.
    asserts.equals(env, analysistest.target_bin_dir_path(env), julia.root.path)
    return analysistest.end(env)

julia_cfg_test = analysistest.make(_julia_cfg_impl)

def _hub_alias_impl(ctx):
    env = unittest.begin(ctx)
    name = "julia_1.12.5_x86_64_linux_gnu"
    content = toolchain_hub_build_content(
        toolchain_names = [name],
        toolchain_labels = {name: "@" + name},
        target_compatible_with = {name: ["@platforms//os:linux", "@platforms//cpu:x86_64"]},
        exec_compatible_with = {},
        target_settings = {name: ["@rules_julia//julia/settings:version_1.12.5"]},
    )

    # Each toolchain's implementation is reachable through the hub, so a
    # module can declare its own `toolchain()` for it.
    alias = """alias(
    name = "{name}_toolchain",
    actual = "@{name}",
    visibility = ["//visibility:public"],
)""".format(name = name)
    asserts.true(env, alias in content, "missing alias in:\n" + content)
    return unittest.end(env)

julia_hub_alias_test = unittest.make(_hub_alias_impl)
