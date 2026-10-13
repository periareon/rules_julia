# rules_julia artifact tarball driver
#
# Packs files into a Julia artifact: a gzipped tarball whose contents are
# identified by their git tree hash, as `Pkg.Artifacts` expects, plus the
# `Artifacts.toml` entry describing it. Everything is produced with what Julia
# ships (`Tar`, `SHA` and the `7z` bundled for Pkg), so the tarball and hashes
# are what `ArtifactUtils.add_artifact!` would create for the same tree.

include(joinpath(@__DIR__, "rules_julia_common.jl"))

# Load Pkg from the caches bundled with Julia, never from the user's depot.
empty!(DEPOT_PATH)
append_bundled_depots!(DEPOT_PATH)

import Pkg
import SHA
import TOML

"""
    stage(manifest, root)

Copy the inputs listed in `manifest` (`destination<TAB>source` lines) into
`root`. A destination of `.` copies a directory's contents to the root.
"""
function stage(manifest::String, root::String)
    for line in eachline(manifest)
        isempty(strip(line)) && continue
        parts = split(line, "\t"; limit = 2)
        length(parts) == 2 || error("Malformed manifest line: $line")
        dest, src = String(parts[1]), String(parts[2])
        ispath(src) || error("Missing input: $src")
        if dest == "."
            isdir(src) || error("Only a directory can be placed at the artifact root: $src")
            for child in readdir(src)
                cp(joinpath(src, child), joinpath(root, child); follow_symlinks = true)
            end
        else
            path = joinpath(root, dest)
            mkpath(dirname(path))
            cp(src, path; follow_symlinks = true)
        end
    end

    # Git records nothing about a file but whether it is executable. Normalize
    # modes so the tree hash does not depend on the umask of the machine that
    # produced the inputs.
    for (dir, _, files) in walkdir(root)
        chmod(dir, 0o755)
        for file in files
            path = joinpath(dir, file)
            islink(path) && continue
            executable = filemode(path) & 0o111 != 0
            chmod(path, executable ? 0o755 : 0o644)
        end
    end
end

"""
    normalize_gzip_header!(path)

`7z` stamps the time of compression and the host OS into the gzip header,
which would make the tarball's SHA-256 depend on when and where the action
ran. Zero the timestamp and record Unix as the OS, as BinaryBuilder tarballs
do; the tar stream inside carries no timestamps to begin with.
"""
function normalize_gzip_header!(path::String)
    open(path, "r+") do io
        header = read(io, 10)
        length(header) == 10 && header[1:2] == [0x1f, 0x8b] ||
            error("Not a gzip file: $path")
        header[4] & 0x08 == 0 || error("Unexpected file name in gzip header: $path")
        seek(io, 4)
        write(io, zeros(UInt8, 4))
        seek(io, 9)
        write(io, UInt8(0x03))
    end
end

function main()
    flags = parse_flags(
        ARGS;
        scalars = ["--output", "--toml", "--name", "--manifest", "--lazy", "--url"],
        lists = ["--tag"],
    )
    output = abspath(require_flag(flags, "--output"))
    toml = abspath(require_flag(flags, "--toml"))
    name = require_flag(flags, "--name")
    manifest = require_flag(flags, "--manifest")

    root = mktempdir(prefix = "rules_julia_artifact_")
    stage(manifest, root)

    # The tree hash identifies the artifact; Pkg recomputes it after extracting
    # a download and rejects anything that does not match.
    tree_hash = bytes2hex(Pkg.GitTools.tree_hash(root))
    Pkg.PlatformEngines.package(root, output)
    normalize_gzip_header!(output)
    sha256 = bytes2hex(open(SHA.sha256, output))

    entry = Dict{String,Any}("git-tree-sha1" => tree_hash)
    if get(flags, "--lazy", "false") == "true"
        entry["lazy"] = true
    end
    tags = Dict{String,String}()
    for tag in flags["--tag"]
        key, value = split(tag, "="; limit = 2)
        tags[String(key)] = String(value)
    end
    merge!(entry, tags)
    if haskey(flags, "--url")
        entry["download"] = [Dict{String,Any}("sha256" => sha256, "url" => flags["--url"])]
    end

    # Platform specific artifacts are arrays of tables so that one name can
    # carry an entry per platform; platform independent ones are a single table.
    document = Dict{String,Any}(name => isempty(tags) ? entry : [entry])
    open(toml, "w") do io
        TOML.print(io, document; sorted = true)
    end
end

main()
