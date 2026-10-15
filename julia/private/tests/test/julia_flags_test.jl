"""
`julia_flags` reach the interpreter, and the code generation flags follow
`--compilation_mode` through the toolchain.
"""

using Test

@testset "julia_flags" begin
    # From `julia_flags = ["--threads=3"]` on the target.
    @test Threads.nthreads() == 3

    opts = Base.JLOptions()
    @test opts.opt_level == parse(Int, ENV["EXPECTED_OPT_LEVEL"])
    # 0 = auto, 1 = yes, 2 = no
    @test opts.check_bounds == parse(Int, ENV["EXPECTED_CHECK_BOUNDS"])
    @test opts.debug_level == parse(Int, ENV["EXPECTED_DEBUG_INFO"])
end
