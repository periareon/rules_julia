using Greeter
using Test

@testset "library entry" begin
    @test greet() == "hello"

    # The target is `greeter_lib` and the package `Greeter`. Tests only load
    # caches that already exist (Julia 1.11+), so a cache path proves the
    # library was precompiled under its package name rather than evaluated
    # from source.
    if VERSION >= v"1.11"
        origin = Base.pkgorigins[Base.PkgId(Greeter)]
        @test origin.cachepath !== nothing
    end
end
