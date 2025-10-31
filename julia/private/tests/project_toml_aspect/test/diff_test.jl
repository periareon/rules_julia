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

    # Split lines so that comparison works regardless of the newlines.
    # This handles Unix (\n) vs Windows (\r\n) line endings
    left_lines = split(left_content, '\n')
    right_lines = split(right_content, '\n')

    # Strip any remaining \r characters from line endings
    left_lines = [rstrip(line, '\r') for line in left_lines]
    right_lines = [rstrip(line, '\r') for line in right_lines]

    # Reconstruct the strings with pure `\n` newlines for comparison
    # This normalizes line endings across platforms
    left_normalized = join(left_lines, '\n')
    right_normalized = join(right_lines, '\n')

    # Compare normalized contents
    if left_normalized != right_normalized
        println(stderr, "Files differ!")
        println(stderr, "=" ^ 80)
        println(stderr, "LEFT_FILE ($left_path):")
        println(stderr, "-" ^ 80)
        println(stderr, left_normalized)
        println(stderr, "=" ^ 80)
        println(stderr, "RIGHT_FILE ($right_path):")
        println(stderr, "-" ^ 80)
        println(stderr, right_normalized)
        println(stderr, "=" ^ 80)

        # Show line-by-line differences
        println(stderr, "Line differences:")
        println(stderr, "-" ^ 80)
        max_lines = max(length(left_lines), length(right_lines))
        for i = 1:max_lines
            left_line = i <= length(left_lines) ? left_lines[i] : "<missing>"
            right_line = i <= length(right_lines) ? right_lines[i] : "<missing>"
            if left_line != right_line
                println(stderr, "Line $i:")
                println(stderr, "  LEFT:  $(repr(left_line))")
                println(stderr, "  RIGHT: $(repr(right_line))")
            end
        end
    end

    @test left_normalized == right_normalized
end
