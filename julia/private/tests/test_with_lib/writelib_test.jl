"""
Test for user-defined library interactions
"""

using writelib
using Test

@testset "writelib Library" begin
    # Environment setup
    tmpdir = get(ENV, "TEST_TMPDIR", "")
    if isempty(tmpdir)
        error("TEST_TMPDIR environment variable must be set")
    end

    outfile = joinpath(tmpdir, "output.txt")

    # Write the string
    content = "La-Li-Lu-Le-Lo"
    write_output(outfile, content)

    # Read back the file
    actual = strip(read(outfile, String))

    # Assert the content matches
    @test actual == content
end
