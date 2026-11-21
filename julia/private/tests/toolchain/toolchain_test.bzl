"""Analysis tests for the `julia_toolchain` rule."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

def _julia_cfg_impl(ctx):
    env = analysistest.begin(ctx)
    julia = analysistest.target_under_test(env)[platform_common.ToolchainInfo].julia

    # Binaries and tests run the toolchain's Julia on the target platform, so
    # it must be built in the target configuration. Build-time actions resolve
    # the toolchain for the execution platform instead.
    asserts.equals(env, analysistest.target_bin_dir_path(env), julia.root.path)
    return analysistest.end(env)

julia_cfg_test = analysistest.make(_julia_cfg_impl)
