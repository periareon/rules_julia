using Test

import Pkg
import SHA
import TOML
using Base.BinaryPlatforms: HostPlatform, arch, os
using Runfiles: rlocation

function runfile(var::String)::String
    path = rlocation(ENV[var])
    (path !== nothing && isfile(path)) || error("Missing runfile for $var: $(ENV[var])")
    return path
end

function file_url(path::String)::String
    path = replace(abspath(path), '\\' => '/')
    return startswith(path, "/") ? "file://" * path : "file:///" * path
end

@testset "platform independent artifact" begin
    tarball = runfile("DATA_TARBALL")
    entry = TOML.parsefile(runfile("DATA_TOML"))["data"]

    # Platform independent artifacts are a single table.
    @test entry isa AbstractDict
    @test occursin(r"^[0-9a-f]{40}$", entry["git-tree-sha1"])
    @test !haskey(entry, "lazy")
    download = only(entry["download"])
    @test download["url"] == "https://example.com/artifacts/data.tar.gz"
    @test download["sha256"] == bytes2hex(open(SHA.sha256, tarball))

    # The gzip header must carry no timestamp, or the hash would change per build.
    header = read(tarball, 10)
    @test header[1:2] == [0x1f, 0x8b]
    @test header[5:8] == zeros(UInt8, 4)

    # The tree hash must be what Pkg computes after extracting the tarball.
    dir = mktempdir()
    Pkg.PlatformEngines.unpack(tarball, dir)
    @test bytes2hex(Pkg.GitTools.tree_hash(dir)) == entry["git-tree-sha1"]
    @test read(joinpath(dir, "hello.txt"), String) == "hello, artifact\n"
    @test read(joinpath(dir, "nested", "numbers.csv"), String) == "1,2,3\n4,5,6\n"
    @test isfile(joinpath(dir, "bin", "tool.sh"))
    if !Sys.iswindows()
        @test filemode(joinpath(dir, "bin", "tool.sh")) & 0o111 != 0
        @test filemode(joinpath(dir, "hello.txt")) & 0o111 == 0
    end
end

@testset "installs through Pkg.Artifacts" begin
    tarball = runfile("DATA_TARBALL")
    entry = TOML.parsefile(runfile("DATA_TOML"))["data"]
    entry["download"][1]["url"] = file_url(tarball)
    artifacts_toml = joinpath(mktempdir(), "Artifacts.toml")
    open(artifacts_toml, "w") do io
        TOML.print(io, Dict("data" => entry))
    end

    depot = mktempdir()
    pushfirst!(DEPOT_PATH, depot)
    Pkg.offline(false)
    path = Pkg.Artifacts.ensure_artifact_installed("data", artifacts_toml)
    @test startswith(path, depot)
    @test read(joinpath(path, "hello.txt"), String) == "hello, artifact\n"
end

@testset "platform specific artifact" begin
    toml = runfile("NATIVE_TOML")
    entries = TOML.parsefile(toml)["native"]

    # Platform specific artifacts are an array of tables.
    @test entries isa AbstractVector
    entry = only(entries)
    host = HostPlatform()
    @test entry["os"] == os(host)
    @test entry["arch"] == arch(host)
    @test entry["lazy"] == true
    @test entry["cxxstring_abi"] == "cxx11"
    @test entry["libgfortran_version"] == "5.0.0"
    if Sys.islinux()
        @test entry["libc"] == "glibc"
    else
        @test !haskey(entry, "libc")
    end
    @test !haskey(entry, "download")

    # Pkg must select the entry for the running Julia.
    meta = Pkg.Artifacts.artifact_meta("native", toml)
    @test meta !== nothing
    @test meta["git-tree-sha1"] == entry["git-tree-sha1"]
end
