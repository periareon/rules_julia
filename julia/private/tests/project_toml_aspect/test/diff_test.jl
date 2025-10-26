"""
Diff test that compares two files using the runfiles API.

This test reads LEFT_FILE and RIGHT_FILE from environment variables,
loads both files, and compares their contents using the Test framework.
"""

using Test
import Runfiles

@testset "File Diff Test" begin
    # Check that required environment variables are set
    @test haskey(ENV, "LEFT_FILE")
    @test haskey(ENV, "RIGHT_FILE")

    # Get rlocation paths from environment
    left_rlocation = ENV["LEFT_FILE"]
    right_rlocation = ENV["RIGHT_FILE"]

    # Resolve files using runfiles API
    left_path = Runfiles.rlocation(left_rlocation)
    @test left_path !== nothing
    @test isfile(left_path)

    right_path = Runfiles.rlocation(right_rlocation)
    @test right_path !== nothing
    @test isfile(right_path)

    # Read both files
    left_content = read(left_path, String)
    right_content = read(right_path, String)

    # Compare contents
    if left_content != right_content
        println(stderr, "Files differ!")
        println(stderr, "=" ^ 80)
        println(stderr, "LEFT_FILE ($left_path):")
        println(stderr, "-" ^ 80)
        println(stderr, left_content)
        println(stderr, "=" ^ 80)
        println(stderr, "RIGHT_FILE ($right_path):")
        println(stderr, "-" ^ 80)
        println(stderr, right_content)
        println(stderr, "=" ^ 80)
    end

    @test left_content == right_content
end
