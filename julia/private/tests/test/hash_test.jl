"""
Test for SHA256 hashing functionality
"""

using SHA
using Test

@testset "SHA256 Hashing" begin
    # The input string
    input = "La-Li-Lu-Le-Lo"

    # Expected hash (SHA-256 of the input string)
    # Computed with: bytes2hex(sha256("La-Li-Lu-Le-Lo"))
    expected = "ec1411d0fb75590958a22ea09767beaeeee311af796007ea7536d0e5dd22cfac"

    # Compute actual hash
    actual = bytes2hex(sha256(input))

    # Test that hashes match
    @test actual == expected
end
