"""Analysis tests for the `julia_library` precompile action."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

def _precompile_actions(env):
    return [a for a in analysistest.target_actions(env) if a.mnemonic == "JuliaPrecompile"]

def _precompile_cpu_target_impl(ctx):
    env = analysistest.begin(ctx)
    actions = _precompile_actions(env)
    asserts.equals(env, 1, len(actions), "expected one JuliaPrecompile action")
    target = actions[0].env.get("JULIA_CPU_TARGET", "")
    asserts.true(env, target, "JuliaPrecompile does not set JULIA_CPU_TARGET")
    asserts.false(env, target == "native", "package images must not target the host CPU")
    return analysistest.end(env)

precompile_cpu_target_test = analysistest.make(_precompile_cpu_target_impl)

def _precompile_cross_platform_impl(ctx):
    env = analysistest.begin(ctx)

    # The execution platform's Julia cannot build package images for another
    # platform's Julia, and the target's Julia cannot run on the execution
    # platform, so a cross build must not precompile.
    asserts.equals(env, 0, len(_precompile_actions(env)), "cross build must not precompile")
    return analysistest.end(env)

precompile_cross_platform_test = analysistest.make(
    _precompile_cross_platform_impl,
    config_settings = {
        "//command_line_option:platforms": [str(Label("//julia/private/tests:freebsd_x86_64"))],
    },
)
