"""julia_binary_wrapper"""

BashRunfilesInfo = provider(
    doc = "The provider for the `_bash_runfiles_finder` aspect.",
    fields = {
        "file": "File: The bash runfiles source file.",
    },
)

def _bash_runfiles_finder_impl(target, ctx):
    for target in getattr(ctx.rule.attr, "data", []):
        if BashRunfilesInfo in target:
            return target[BashRunfilesInfo]

    for target in getattr(ctx.rule.attr, "root_symlinks", {}).keys():
        if BashRunfilesInfo in target:
            return target[BashRunfilesInfo]

        files = target[DefaultInfo].files.to_list()
        if len(files) != 1:
            continue
        if files[0].basename == "runfiles.bash":
            return BashRunfilesInfo(
                file = files[0],
            )

    return []

_bash_runfiles_finder = aspect(
    doc = """\
An aspect used to locate the `runfiles.bash` source file.

The way the `@rules_shell//shell/runfiles` library is configured is a bit complicated and atypical
of what I would expect from a standard `sh_library` and the actual source file which represents the
runfiles interface is generally not accessible. This aspect traverses the known path to the file
so we can access it at all. Ideally there would be some `ShInfo` provider that exposed this or
the source would be easily accessible from `DefaultInfo`. Unfortunately that is not the case today.
""",
    implementation = _bash_runfiles_finder_impl,
    attr_aspects = ["data", "root_symlinks"],
)

def _find_bash_runfiles(target):
    if BashRunfilesInfo in target:
        return target[BashRunfilesInfo].file

    info = target[DefaultInfo]
    for file in info.files.to_list():
        if file.basename == "runfiles.bash":
            return file

    fail("Unable to find bash runfiles in: {}".format(target.label))

def _julia_binary_wrapper_impl(ctx):
    julia_toolchain = ctx.attr._julia_toolchain_exec[platform_common.ToolchainInfo]

    inputs = [ctx.file.template]

    substitutions = {}
    file_substitutions = {}

    is_windows = ctx.file.template.basename.endswith(".bat.tpl")
    if is_windows:
        output = ctx.actions.declare_file("{}.bat".format(ctx.label.name))
        batch_runfiles = ctx.file._batch_runfiles
        file_substitutions["@REM {RUNFILES_API}"] = batch_runfiles.path
        inputs.append(batch_runfiles)
    else:
        sh_toolchain = ctx.toolchains["@rules_shell//shell:toolchain_type"]
        if sh_toolchain:
            shebang = "#!{}".format(sh_toolchain.path)
            substitutions["#!/usr/bin/env bash"] = shebang

        output = ctx.actions.declare_file("{}.sh".format(ctx.label.name))
        bash_runfiles = _find_bash_runfiles(ctx.attr._bash_runfiles)
        file_substitutions["# {RUNFILES_API}"] = bash_runfiles.path
        inputs.append(bash_runfiles)

    args = ctx.actions.args()
    args.add(ctx.file._maker)
    args.add("--output", output)
    args.add("--template", ctx.file.template)
    for old, new in substitutions.items():
        args.add("--substitution")
        args.add(old)
        args.add(new)

    for marker, path in file_substitutions.items():
        args.add("--file_substitution")
        args.add(marker)
        args.add(path)

    ctx.actions.run(
        mnemonic = "JuliaBinaryWrapperTemplate",
        progress_message = "JuliaBinaryWrapperTemplate %{label}",
        executable = julia_toolchain.julia,
        arguments = [args],
        inputs = inputs,
        tools = depset([ctx.file._maker], transitive = [julia_toolchain.all_files]),
        outputs = [output],
    )

    return [DefaultInfo(files = depset([output]))]

julia_binary_wrapper = rule(
    doc = "A rule for rendering the wrapper for julia entrypoints.",
    implementation = _julia_binary_wrapper_impl,
    attrs = {
        "template": attr.label(
            doc = "The template file to resolve.",
            mandatory = True,
            cfg = "target",
            allow_single_file = [".sh.tpl", ".bat.tpl"],
        ),
        "_bash_runfiles": attr.label(
            doc = "The runfiles library for bash.",
            cfg = "target",
            aspects = [_bash_runfiles_finder],
            default = Label("@rules_shell//shell/runfiles"),
        ),
        "_batch_runfiles": attr.label(
            doc = "The runfiles library for batch.",
            cfg = "target",
            allow_single_file = [".bat"],
            default = Label("@rules_batch//batch/runfiles:runfiles.bat"),
        ),
        "_julia_toolchain_exec": attr.label(
            cfg = "exec",
            default = Label("//julia:current_julia_toolchain"),
            providers = [platform_common.ToolchainInfo],
        ),
        "_maker": attr.label(
            doc = "The script used to render the entrypoint.",
            cfg = "exec",
            allow_single_file = True,
            default = Label("//julia/private:binary_wrapper_maker.jl"),
        ),
    },
    toolchains = [
        config_common.toolchain_type("@rules_shell//shell:toolchain_type", mandatory = False),
    ],
)
