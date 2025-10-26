"""
Ensure `MODULE.bazel` versions match `version.bzl`
"""

using Runfiles
using Test

@testset "Version Consistency" begin
    # Get the expected version from environment
    expected_version = get(ENV, "VERSION", nothing)
    @test !isnothing(expected_version)
    @test !isempty(expected_version)

    # Get path to MODULE.bazel
    module_bazel_path = get(ENV, "MODULE_BAZEL", nothing)
    @test !isnothing(module_bazel_path)

    # Resolve the runfiles path
    module_path = rlocation(module_bazel_path)
    @test isfile(module_path)

    # Read MODULE.bazel content
    content = read(module_path, String)

    # Extract version using regex
    version_pattern = r"version\s*=\s*\"([^\"]+)\""i
    m = match(version_pattern, content)
    @test !isnothing(m)

    found_version = m.captures[1]

    # Compare versions
    @test found_version == expected_version
end
