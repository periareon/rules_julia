"""
Test suite for Julia runfiles support
"""

using Test
import Runfiles

# Get expected data file locations from environment
data_rlocationpath = ENV["DATA_RLOCATIONPATH"]
generated_data_rlocationpath = ENV["GENERATED_DATA_RLOCATIONPATH"]

@testset "Runfiles" begin
    # Test rlocation for regular data file
    data_path = Runfiles.rlocation(data_rlocationpath)
    @test data_path !== nothing
    @test isfile(data_path)

    data_content = read(data_path, String)
    @test occursin("La-Li-Lu-Le-Lo", data_content)

    # Test rlocation for generated data file
    generated_data_path = Runfiles.rlocation(generated_data_rlocationpath)
    @test generated_data_path !== nothing
    @test isfile(generated_data_path)

    generated_content = read(generated_data_path, String)
    @test occursin("La-Li-Lu-Le-Lo", generated_content)

    # Test that create() returns a valid runfiles instance
    rf = Runfiles.create()
    @test rf !== nothing

    # Test that we can use the runfiles instance directly
    data_path2 = Runfiles.rlocation(rf, data_rlocationpath)
    @test data_path2 !== nothing
    @test data_path2 == data_path

    # Test runfiles_dir (not exported, must use module prefix)
    rfdir = Runfiles.runfiles_dir()
    @test rfdir !== nothing
    @test isdir(rfdir)

    println("✓ All runfiles tests passed!")
end
