"""
Test that a package installed from a plain `Manifest.toml` is usable.
"""

using Glob
using Test

@testset "Glob from Manifest.toml" begin
    dir = mktempdir()
    touch(joinpath(dir, "a.jl"))
    touch(joinpath(dir, "b.jl"))
    touch(joinpath(dir, "c.txt"))

    matches = sort(basename.(glob("*.jl", dir)))
    @test matches == ["a.jl", "b.jl"]
end
