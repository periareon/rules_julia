"""Analysis test for how `julia_binary` renders its wrapper script."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

def _wrapper_action_impl(ctx):
    env = analysistest.begin(ctx)
    actions = analysistest.target_actions(env)
    mnemonics = [a.mnemonic for a in actions]
    asserts.true(env, "JuliaWrapper" in mnemonics, "no JuliaWrapper action, got: " + ", ".join(mnemonics))
    asserts.false(env, "TemplateExpand" in mnemonics, "wrapper template expanded during analysis: " + ", ".join(mnemonics))
    return analysistest.end(env)

wrapper_action_test = analysistest.make(_wrapper_action_impl)
