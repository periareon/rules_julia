"""Rule for testing Project.toml generation with aspects."""

load("//julia/private:julia.bzl", "julia_test")
load("//julia/private:project_toml_aspect.bzl", "JuliaProjectTomlInfo", "julia_project_toml_aspect")

def _julia_project_toml_test_rule_impl(ctx):
    """Implementation of julia_project_toml_test_rule."""

    # Create output groups for each consumer
    output_groups = {}

    # For each consumer target, create an output group
    for target in ctx.attr.targets:
        project_output_group_name = "julia_project_toml_test_{}".format(target.label.name)
        manifest_output_group_name = "julia_manifest_toml_test_{}".format(target.label.name)

        # Get the Project.toml and Manifest.toml files from the aspect
        aspect_info = target[JuliaProjectTomlInfo]
        output_groups[project_output_group_name] = depset([aspect_info.root_project])
        output_groups[manifest_output_group_name] = depset([aspect_info.root_manifest])

    return [
        OutputGroupInfo(**output_groups),
    ]

julia_project_toml_test_rule = rule(
    doc = "Rule that runs the julia_project_toml_aspect on consumer targets and provides output groups for testing.",
    implementation = _julia_project_toml_test_rule_impl,
    attrs = {
        "targets": attr.label_list(
            doc = "List of consumer targets to run the aspect on",
            aspects = [julia_project_toml_aspect],
            providers = [JuliaProjectTomlInfo],
            mandatory = True,
        ),
    },
)

def diff_test(*, name, file1, file2, **kwargs):
    """Compare two files and assert the content is identical.

    Args:
        name (str): The name of the test.
        file1 (Label): The left file in the comparison.
        file2 (Label): The right file in the comparison.
        **kwargs (dict): Additional keyword arguments.
    """
    julia_test(
        name = name,
        data = [file1, file2],
        srcs = [Label("//julia/private/tests/project_toml_aspect/test:diff_test.jl")],
        deps = ["//julia/runfiles"],
        main = Label("//julia/private/tests/project_toml_aspect/test:diff_test.jl"),
        env = {
            "LEFT_FILE": "$(rlocationpath {})".format(file1),
            "RIGHT_FILE": "$(rlocationpath {})".format(file2),
        },
        **kwargs
    )
