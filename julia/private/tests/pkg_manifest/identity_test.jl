"""
Packages installed from a manifest must keep their identity.

Julia only assigns a UUID to a package when it is loaded through its
`Project.toml`. `Preferences` (used by `JLLWrappers` at top level) refuses to
work on modules without one, so this guards the load path layout.
"""

using Glob
using JLLWrappers
using Test

@testset "Package identity" begin
    @test Base.PkgId(Glob).uuid == Base.UUID("c27321d9-0574-5035-807b-f59d2c89b15c")
    @test Base.PkgId(JLLWrappers).uuid == Base.UUID("692b3bcd-3c85-4b1f-b108-f13ce0eb3210")

    # Read through `Preferences`, which requires the module's UUID.
    @test JLLWrappers.disable_optimization === true
end
