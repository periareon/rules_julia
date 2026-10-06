"""
A JLL package installed from a plain `Manifest.toml` must find its artifact.
"""

using Bzip2_jll
using Libdl
using Test

@testset "Bzip2_jll artifact" begin
    @test isfile(Bzip2_jll.libbzip2_path)
    @test occursin("artifacts", Bzip2_jll.artifact_dir)

    handle = Libdl.dlopen(Bzip2_jll.libbzip2)
    @test handle != C_NULL
    version = unsafe_string(ccall(Libdl.dlsym(handle, :BZ2_bzlibVersion), Cstring, ()))
    @test startswith(version, "1.0")
end
