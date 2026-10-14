"""
Tests for `julia_sysimage`: Julia started with the image has the packages
preloaded and running code from them does not touch any compile cache.
"""

using Runfiles: rlocation
using Test

function image_path()
    path = rlocation(ENV["RULES_JULIA_SYSIMAGE"])
    path !== nothing && isfile(path) ||
        error("System image not found: $(ENV["RULES_JULIA_SYSIMAGE"])")
    return path
end

function run_with_image(code::String)
    # Reuse this process' interpreter and environment (load path, depots), but
    # swap in the image under test.
    pathsep = Sys.iswindows() ? ";" : ":"
    julia = Base.julia_cmd().exec[1]
    cmd = addenv(
        `$julia --startup-file=no --sysimage=$(image_path()) -e $code`,
        "JULIA_LOAD_PATH" => join(LOAD_PATH, pathsep),
        "JULIA_DEPOT_PATH" => join(DEPOT_PATH, pathsep),
    )
    out = IOBuffer()
    err = IOBuffer()
    process = run(pipeline(ignorestatus(cmd); stdout = out, stderr = err))
    return process.exitcode, String(take!(out)), String(take!(err))
end

@testset "julia_sysimage" begin
    @testset "image is in use" begin
        code, out, _ =
            run_with_image("print(basename(unsafe_string(Base.JLOptions().image_file)))")
        @test code == 0
        @test startswith(out, "sys.")
    end

    @testset "packages are preloaded" begin
        # Both packages are present before any `using`, i.e. they came from
        # the image rather than from a compile cache or source.
        code, out, _ = run_with_image(
            "print(haskey(Base.loaded_modules, Base.PkgId(\"greeter\")), \" \", haskey(Base.loaded_modules, Base.PkgId(\"farewell\")))",
        )
        @test code == 0
        @test out == "true true"
    end

    @testset "code runs" begin
        code, out, err = run_with_image("using farewell; print(farewell.goodbye())")
        @test code == 0
        @test out == "La-Li-Lu-Le-Lo, goodbye"
    end
end
