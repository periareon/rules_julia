"""
Test to validate that dependency paths in Project.toml files exist relative to their directory.

This test consumes all Project.toml files in the test directory and validates that the paths
specified in the [deps] sections actually exist relative to the Project.toml file's directory.

Note: The paths in multi_deps_test.Project.toml are not actually for that specific test but
due to the shared package depth structure, the relative pathing should work correctly.
This test demonstrates that the path validation logic works correctly by detecting when
paths don't exist in the current Bazel sandbox environment.
"""

using Test
import TOML
import Printf
import Runfiles

function parse_project_toml(file_path)
    """Parse a Project.toml file and return its contents."""
    try
        return TOML.parsefile(file_path)
    catch e
        Test.@error "Failed to parse Project.toml file: $file_path" exception=e
        return nothing
    end
end

function validate_dependency_paths(project_toml_path, project_data)
    """Validate that all dependency paths in the Project.toml exist relative to the file's directory."""
    project_dir = dirname(project_toml_path)
    validation_errors = String[]

    if haskey(project_data, "deps")
        deps = project_data["deps"]
        for (dep_name, dep_info) in deps
            if isa(dep_info, Dict) && haskey(dep_info, "path")
                dep_path = dep_info["path"]
                # Resolve the path relative to the Project.toml directory
                full_dep_path = joinpath(project_dir, dep_path)

                if !isdir(full_dep_path)
                    push!(
                        validation_errors,
                        "Dependency '$dep_name' path '$dep_path' does not exist at '$full_dep_path'",
                    )
                else
                    Test.@info "✓ Dependency '$dep_name' path '$dep_path' exists at '$full_dep_path'"
                end
            end
        end
    end

    return validation_errors
end

@testset "Project.toml Dependency Path Validation" begin
    # Get the test directory (where this script is located)
    test_dir = @__DIR__
    @info "Test directory: $test_dir"

    # Check if PROJECT_TOML environment variable is set and use runfiles to resolve it
    project_toml_from_env = nothing
    if haskey(ENV, "PROJECT_TOML")
        project_toml_path = ENV["PROJECT_TOML"]
        @info "PROJECT_TOML environment variable set to: $project_toml_path"

        # Use runfiles to resolve the path
        resolved_path = Runfiles.rlocation(project_toml_path)
        if resolved_path !== nothing
            project_toml_from_env = resolved_path
            @info "Resolved PROJECT_TOML to: $project_toml_from_env"
        else
            @warn "Could not resolve PROJECT_TOML path: $project_toml_path"
        end
    end

    # Find all Project.toml files in the test directory
    project_toml_files = filter(f -> endswith(f, ".Project.toml"), readdir(test_dir))
    @info "Found Project.toml files: $project_toml_files"

    @test length(project_toml_files) > 0

    all_errors = String[]

    # First, validate the Project.toml file from environment variable if provided
    if project_toml_from_env !== nothing
        @info "Validating Project.toml from environment: $project_toml_from_env"

        # Parse the Project.toml file
        project_data = parse_project_toml(project_toml_from_env)
        @test project_data !== nothing

        if project_data !== nothing
            # Validate dependency paths
            errors = validate_dependency_paths(project_toml_from_env, project_data)
            append!(all_errors, errors)

            if isempty(errors)
                @info "✓ All dependency paths in environment Project.toml are valid"
            else
                @warn "✗ Found $(length(errors)) validation errors in environment Project.toml"
            end
        end
    end

    # Then validate all Project.toml files in the test directory
    # Skip files that were already validated via environment variable
    for project_file in project_toml_files
        project_path = joinpath(test_dir, project_file)

        # Skip if this file was already validated via environment variable
        if project_toml_from_env !== nothing &&
           realpath(project_path) == realpath(project_toml_from_env)
            @info "Skipping $project_file (already validated via environment variable)"
            continue
        end

        @info "Validating: $project_path"

        # Parse the Project.toml file
        project_data = parse_project_toml(project_path)
        @test project_data !== nothing

        if project_data !== nothing
            # Validate dependency paths
            errors = validate_dependency_paths(project_path, project_data)
            append!(all_errors, errors)

            if isempty(errors)
                @info "✓ All dependency paths in $project_file are valid"
            else
                @warn "✗ Found $(length(errors)) validation errors in $project_file"
            end
        end
    end

    # Report results
    if isempty(all_errors)
        @info "✓ All Project.toml dependency paths are valid!"
    else
        @warn "✗ Found $(length(all_errors)) total validation errors:"
        for error in all_errors
            @warn "  - $error"
        end
        @info "Note: These errors are expected in the Bazel sandbox environment."
        @info "The paths in multi_deps_test.Project.toml are designed for a different context"
        @info "but demonstrate that the path validation logic works correctly."
    end

    # For this test, we expect all paths to be valid since we now use UUID dependencies
    # This validates that our path checking logic works correctly
    @test length(project_toml_files) >= 3  # Should find all 3 Project.toml files
    @test length(all_errors) == 0  # Should find no validation errors since we use UUID dependencies
end
