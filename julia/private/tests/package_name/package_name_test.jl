using Greeter
using Test

@testset "package_name" begin
    @test greet() == "hello"
end
