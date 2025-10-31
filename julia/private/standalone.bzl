"""Julia standalone binary rules"""

load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")
load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load(
    ":project_toml_aspect.bzl",
    "JuliaProjectTomlInfo",
    "get_project_include",
    "julia_project_toml_aspect",
)
load(":providers.bzl", "JuliaInfo")
load(":toolchain.bzl", "TOOLCHAIN_TYPE")

def _rlocationpath(file, workspace_name):
    """Convert a file to its runfiles location path."""
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]
    return "{}/{}".format(workspace_name, file.short_path)

def _julia_standalone_binary_impl(ctx):
    # Get the binary target
    binary = ctx.attr.binary
    julia_info = binary[JuliaInfo]

    # Get all source files (direct and transitive)
    all_srcs = julia_info.transitive_srcs.to_list()

    # Get toolchain for Julia runtime
    toolchain_info = ctx.toolchains[TOOLCHAIN_TYPE]

    # Declare explicit outputs: app/, lib/, share/ directories and wrapper script
    is_windows = ctx.file._template.basename.endswith(".bat.tpl")
    script_ext = ".bat" if is_windows else ".sh"
    bin_ext = ".exe" if is_windows else ""

    output_bin_main = ctx.actions.declare_file("{}/bin/{}{}".format(ctx.label.name, julia_info.app_name, bin_ext))
    output_bin_julia = ctx.actions.declare_file("{}/bin/julia{}".format(ctx.label.name, bin_ext))
    output_lib_dir = ctx.actions.declare_directory("{}/lib".format(ctx.label.name))
    output_share_dir = ctx.actions.declare_directory("{}/share".format(ctx.label.name))
    output_wrapper = ctx.actions.declare_file("{}{}".format(ctx.label.name, script_ext))

    runfiles_manifest = ctx.attr.binary[DefaultInfo].files_to_run.runfiles_manifest

    project_toml_info = binary[JuliaProjectTomlInfo]
    if not project_toml_info.main:
        fail("{} did not produce `main`.", binary.label)

    # Build the arguments for the compiler
    # Point output to the parent directory so PackageCompiler creates app/, lib/, share/ subdirectories
    output_parent_dir = output_lib_dir.dirname
    args = ctx.actions.args()
    args.add("--app-name", julia_info.app_name)
    args.add("--project-root", get_project_include(julia_info))
    args.add("--project-bin", _rlocationpath(project_toml_info.main, ctx.workspace_name))
    args.add("--project-root-toml", project_toml_info.root_project)
    args.add("--output", output_parent_dir)
    args.add("--runfiles-manifest", runfiles_manifest)

    args.add("--project-toml", "{}={}".format(_rlocationpath(project_toml_info.root_project, ctx.workspace_name), project_toml_info.root_project.path))
    for dep_project_toml in project_toml_info.dep_projects.values():
        # Get the runfiles path for the Project.toml file
        toml_path = _rlocationpath(dep_project_toml, ctx.workspace_name)
        args.add("--project-toml", "{}={}".format(toml_path, dep_project_toml.path))

    # Get C++ toolchain for PackageCompiler's C compilation needs
    cc_toolchain = find_cc_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    # Create compile variables for the CC toolchain
    compile_variables = cc_common.create_compile_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
    )

    # Get CC compile arguments and environment
    cc_c_args = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.c_compile,
        variables = compile_variables,
    )
    cc_cxx_args = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.cpp_compile,
        variables = compile_variables,
    )
    cc_env = cc_common.get_environment_variables(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.c_compile,
        variables = compile_variables,
    )

    # Build environment for compilation
    env = {}

    # Set up CC toolchain environment variables for PackageCompiler
    # These paths will be resolved in standalone_compiler.jl
    env["CC"] = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.c_compile,
    )
    env["CXX"] = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.cpp_compile,
    )
    env["AR"] = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.cpp_link_static_library,
    )

    # Set compiler flags
    env["CFLAGS"] = " ".join(cc_c_args)
    env["CXXFLAGS"] = " ".join(cc_cxx_args)

    # Add any additional CC environment variables (e.g., INCLUDE on Windows)
    env.update(cc_env)

    # Add action env
    env.update(ctx.configuration.default_shell_env)

    # Collect Project.toml and Manifest.toml files from the aspect for build inputs
    project_toml_files = depset([project_toml_info.root_project], transitive = [depset(project_toml_info.dep_projects.values())])
    manifest_toml_files = depset([project_toml_info.root_manifest], transitive = [depset(project_toml_info.dep_manifests.values())])

    # Collect all inputs including C++ toolchain files for sandbox
    # Manifest files are needed as inputs since they're referenced by the compiler
    inputs = depset(
        direct = all_srcs + [runfiles_manifest],
        transitive = [binary[DefaultInfo].default_runfiles.files, project_toml_files, manifest_toml_files],
    )

    ctx.actions.run(
        mnemonic = "JuliaStandaloneCompile",
        executable = ctx.executable._compiler,
        arguments = [args],
        outputs = [output_bin_main, output_bin_julia, output_lib_dir, output_share_dir],
        inputs = inputs,
        progress_message = "Compiling Julia standalone app {}".format(julia_info.app_name),
        env = env | {
            "JULIA_PKG_OFFLINE": "true",
        },
        tools = depset(transitive = [toolchain_info.all_files, cc_toolchain.all_files]),
        # TODO: https://github.com/periareon/rules_julia/issues/2
        # This action should not need this.
        use_default_shell_env = True,
    )

    ctx.actions.expand_template(
        template = ctx.file._template,
        output = output_wrapper,
        substitutions = {
            "{rules_julia_standalone_app}": _rlocationpath(output_bin_main, ctx.workspace_name),
        },
        is_executable = True,
    )

    return [
        DefaultInfo(
            executable = output_wrapper,
            files = depset([
                output_bin_main,
                output_bin_julia,
                output_lib_dir,
                output_share_dir,
                output_wrapper,
            ]),
            runfiles = ctx.runfiles(files = [
                output_bin_main,
                output_bin_julia,
                output_lib_dir,
                output_share_dir,
                output_wrapper,
            ]).merge(ctx.attr._bash_runfiles[DefaultInfo].default_runfiles),
        ),
    ]

julia_standalone_binary = rule(
    doc = """A rule for converting a `julia_binary` to a standalone application.

    This rule uses PackageCompiler.jl to create a standalone executable that includes
    the Julia runtime and all dependencies. The resulting application can be
    distributed and run on machines without Julia installed.

    Dependencies are provided hermetically through Bazel - no network access required!
    PackageCompiler.jl and all Julia package dependencies are managed through the
    Bazel build system.

    Example:

    ```python
    julia_binary(
        name = "my_app_bin",
        srcs = ["my_app.jl"],
        deps = ["//my/lib"],
    )

    julia_standalone_binary(
        name = "my_app",
        binary = ":my_app_bin",
    )
    ```
    """,
    implementation = _julia_standalone_binary_impl,
    attrs = {
        "binary": attr.label(
            doc = "The julia_binary target to convert into a standalone application",
            mandatory = True,
            executable = True,
            cfg = "target",
            aspects = [julia_project_toml_aspect],
            providers = [JuliaInfo],
        ),
        "_bash_runfiles": attr.label(
            default = Label("@bazel_tools//tools/bash/runfiles"),
        ),
        "_cc_toolchain": attr.label(
            default = Label("@rules_cc//cc:current_cc_toolchain"),
        ),
        "_compiler": attr.label(
            doc = "The standalone compiler script.",
            executable = True,
            cfg = "exec",
            default = Label("//julia/private/standalone_compiler"),
        ),
        "_template": attr.label(
            cfg = "target",
            allow_single_file = True,
            default = Label("//julia/private/standalone_compiler:standalone_wrapper.tpl"),
        ),
    },
    executable = True,
    toolchains = [
        TOOLCHAIN_TYPE,
        "@rules_cc//cc:toolchain_type",
    ],
    fragments = ["cpp"],
)
