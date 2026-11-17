"""Analysis test for the `julia_library` precompile action."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

def _precompile_cpu_target_impl(ctx):
    env = analysistest.begin(ctx)
    actions = [a for a in analysistest.target_actions(env) if a.mnemonic == "JuliaPrecompile"]
    asserts.equals(env, 1, len(actions), "expected one JuliaPrecompile action")
    target = actions[0].env.get("JULIA_CPU_TARGET", "")
    asserts.true(env, target, "JuliaPrecompile does not set JULIA_CPU_TARGET")
    asserts.false(env, target == "native", "package images must not target the host CPU")
    return analysistest.end(env)

precompile_cpu_target_test = analysistest.make(_precompile_cpu_target_impl)
