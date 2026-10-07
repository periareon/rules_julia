"""
Julia Package Manifest Generator for Bazel

This script uses Julia's Pkg manager to resolve dependencies from Project.toml
and generate/update the Manifest.toml lockfile. Optionally it also writes a
Manifest.bazel.json with package URLs and integrity values.
"""

using Artifacts
using Pkg
using SHA
using Base64
using Downloads

function parse_args()
    """Parse command-line arguments from environment variables and command line flags."""
    args = Dict{String,Any}()

    # Required environment variables set by the Bazel rule
    required_vars =
        ["RULES_JULIA_PKG_COMPILER_PROJECT_TOML", "RULES_JULIA_PKG_COMPILER_MANIFEST_TOML"]

    for var in required_vars
        if !haskey(ENV, var)
            error("Environment variable $var is not set")
        end
        # Convert to absolute path
        key = lowercase(replace(var, "RULES_JULIA_PKG_COMPILER_" => ""))
        args[key] = abspath(ENV[var])
    end

    # Optional: Manifest.bazel.json path. When unset only Manifest.toml is
    # written and the `pkg` module extension derives everything else from it.
    if haskey(ENV, "RULES_JULIA_PKG_COMPILER_MANIFEST_BAZEL_JSON")
        args["manifest_bazel_json"] =
            abspath(ENV["RULES_JULIA_PKG_COMPILER_MANIFEST_BAZEL_JSON"])
    else
        args["manifest_bazel_json"] = nothing
    end

    # Parse --add {NAME} flags from command line arguments
    packages_to_add = String[]
    i = 1
    while i <= length(ARGS)
        if ARGS[i] == "--add" && i + 1 <= length(ARGS)
            push!(packages_to_add, ARGS[i+1])
            i += 2
        else
            i += 1
        end
    end

    args["add"] = packages_to_add

    return args
end

function parse_manifest_toml(manifest_path::String)
    """Parse Manifest.toml and extract package information."""
    manifest_content = read(manifest_path, String)
    manifest = Pkg.Types.read_manifest(manifest_path)

    packages = Dict{String,Any}()

    for (uuid, pkg_entry) in manifest
        # Skip Julia stdlib packages (they don't have a tree hash)
        # Check if tree_hash field exists and is not nothing
        if !isdefined(pkg_entry, :tree_hash) || isnothing(pkg_entry.tree_hash)
            continue
        end

        name = pkg_entry.name
        tree_hash = string(pkg_entry.tree_hash)
        version = string(pkg_entry.version)
        uuid_str = string(uuid)

        # Get dependencies
        deps = String[]
        if isdefined(pkg_entry, :deps) && !isnothing(pkg_entry.deps)
            deps = collect(String, keys(pkg_entry.deps))
        end

        packages[name] = Dict(
            "uuid" => uuid_str,
            "version" => version,
            "git-tree-sha1" => tree_hash,
            "deps" => deps,
        )
    end

    return packages
end

function compute_integrity(url::String)
    """Download a package and compute its Bazel integrity value (sha256-<base64>)."""
    # Download to a temporary file
    temp_file = tempname()
    try
        Downloads.download(url, temp_file)
        # Compute SHA256 as bytes
        hash_bytes = open(SHA.sha256, temp_file)
        # Convert to base64 and prepend "sha256-"
        hash_base64 = base64encode(hash_bytes)
        return "sha256-" * hash_base64
    finally
        rm(temp_file, force = true)
    end
end

function escape_json_string(s::String)
    """Escape a string for JSON output."""
    result = IOBuffer()
    for c in s
        if c == '"'
            write(result, "\\\"")
        elseif c == '\\'
            write(result, "\\\\")
        elseif c == '\b'
            write(result, "\\b")
        elseif c == '\f'
            write(result, "\\f")
        elseif c == '\n'
            write(result, "\\n")
        elseif c == '\r'
            write(result, "\\r")
        elseif c == '\t'
            write(result, "\\t")
        elseif c < '\x20'
            write(result, "\\u$(string(Int(c), base=16, pad=4))")
        else
            write(result, c)
        end
    end
    return String(take!(result))
end

function write_json_value(io::IO, value, indent::String = "")
    """Write a JSON value. Dict keys are sorted for deterministic output."""
    if value isa AbstractString
        write(io, "\"", escape_json_string(String(value)), "\"")
    elseif value isa Bool
        write(io, value ? "true" : "false")
    elseif value isa AbstractVector
        if isempty(value)
            write(io, "[]")
            return
        end
        write(io, "[\n")
        for (i, item) in enumerate(value)
            write(io, indent, "  ")
            write_json_value(io, item, indent * "  ")
            if i < length(value)
                write(io, ",")
            end
            write(io, "\n")
        end
        write(io, indent, "]")
    elseif value isa AbstractDict
        if isempty(value)
            write(io, "{}")
            return
        end
        write(io, "{\n")
        keys_list = sort(collect(String, keys(value)))
        for (i, key) in enumerate(keys_list)
            write(io, indent, "  \"", escape_json_string(key), "\": ")
            write_json_value(io, value[key], indent * "  ")
            if i < length(keys_list)
                write(io, ",")
            end
            write(io, "\n")
        end
        write(io, indent, "}")
    else
        error("Unsupported type: $(typeof(value))")
    end
end

function write_json_object(io::IO, obj::Dict{String,Any}, indent::String = "")
    """Write a JSON object."""
    write_json_value(io, obj, indent)
end

const ARTIFACT_NON_TAG_KEYS = ("git-tree-sha1", "download", "lazy")

function package_artifacts(name::String, uuid::String)
    """Read the `Artifacts.toml` of an installed package.

    Returns a Dict mapping artifact names to a Vector of variants, each a Dict
    with `tags`, `tree_hash`, `urls`, `sha256` and `lazy`, or `nothing` when
    the package declares no artifacts.
    """
    pkg_id = Base.PkgId(Base.UUID(uuid), name)
    entry_point = Base.locate_package(pkg_id)
    if entry_point === nothing
        error("Unable to locate installed package $name [$uuid]")
    end
    package_dir = dirname(dirname(entry_point))

    artifacts_toml = nothing
    for candidate in ("Artifacts.toml", "JuliaArtifacts.toml")
        path = joinpath(package_dir, candidate)
        if isfile(path)
            artifacts_toml = path
            break
        end
    end
    artifacts_toml === nothing && return nothing

    artifacts = Dict{String,Any}()
    for (artifact_name, value) in Artifacts.load_artifacts_toml(artifacts_toml)
        variants = value isa AbstractVector ? value : [value]
        entries = Any[]
        for variant in variants
            downloads = get(variant, "download", Any[])
            downloads = downloads isa AbstractVector ? downloads : [downloads]
            urls = String[]
            sha256 = ""
            for download in downloads
                haskey(download, "url") && push!(urls, String(download["url"]))
                if isempty(sha256) && haskey(download, "sha256")
                    sha256 = String(download["sha256"])
                end
            end
            tags = Dict{String,Any}()
            for (key, tag_value) in variant
                key in ARTIFACT_NON_TAG_KEYS && continue
                tags[String(key)] = string(tag_value)
            end
            push!(
                entries,
                Dict{String,Any}(
                    "tags" => tags,
                    "tree_hash" => String(variant["git-tree-sha1"]),
                    "urls" => urls,
                    "sha256" => sha256,
                    "lazy" => get(variant, "lazy", false) === true,
                ),
            )
        end
        artifacts[String(artifact_name)] = entries
    end
    return artifacts
end

function generate_bazel_lockfile(packages::Dict{String,Any}, output_path::String)
    """Generate Manifest.bazel.json with integrity values for all packages."""

    lockfile = Dict{String,Any}()

    total = length(packages)
    current = 0

    for (name, pkg_data) in packages
        current += 1
        uuid = pkg_data["uuid"]
        tree_hash = pkg_data["git-tree-sha1"]
        version = pkg_data["version"]
        deps = pkg_data["deps"]

        # Construct the package server URL
        url = "https://pkg.julialang.org/package/$uuid/$tree_hash"

        print("[$current/$total] Computing integrity for $name@$version... ")
        flush(stdout)

        try
            integrity_value = compute_integrity(url)
            println("✓")

            entry = Dict{String,Any}(
                "urls" => [url],
                "integrity" => integrity_value,
                "deps" => sort(deps),  # Sort dependencies for deterministic output
                "version" => version,
                "uuid" => uuid,
            )
            artifacts = package_artifacts(name, uuid)
            if artifacts !== nothing && !isempty(artifacts)
                entry["artifacts"] = artifacts
            end
            lockfile[name] = entry
        catch e
            println("✗")
            println(stderr, "  Error downloading $name: $e")
            rethrow(e)
        end
    end

    # Write the lockfile manually (without JSON module)
    open(output_path, "w") do io
        write_json_object(io, lockfile)
        write(io, "\n")  # Add trailing newline
    end
end

function generate_manifest(
    project_toml_path::String,
    manifest_toml_path::String,
    manifest_bazel_json_path::Union{String,Nothing},
    packages_to_add::Vector{String} = String[],
)
    """Generate Manifest.toml (and optionally Manifest.bazel.json) from Project.toml using Pkg.

    This creates a temporary environment, copies the Project.toml,
    resolves dependencies, and generates Manifest.toml. When a
    Manifest.bazel.json path is given it is generated as well.

    Args:
        project_toml_path: Path to the Project.toml file
        manifest_toml_path: Path where Manifest.toml will be written
        manifest_bazel_json_path: Optional path where Manifest.bazel.json will be written
        packages_to_add: Optional list of package names to add before resolving dependencies
    """
    println("=" ^ 70)
    println("Julia Package Manifest Generator")
    println("=" ^ 70)
    println("Project.toml: $project_toml_path")
    println("Manifest.toml: $manifest_toml_path")
    if manifest_bazel_json_path !== nothing
        println("Manifest.bazel.json: $manifest_bazel_json_path")
    end
    println()

    # Verify Project.toml exists
    if !isfile(project_toml_path)
        error("Project.toml not found: $project_toml_path")
    end

    # Create a temporary directory for the environment
    temp_env = mktempdir(prefix = "rjlpc_", cleanup = true)

    # Copy Project.toml to temp directory
    temp_project = joinpath(temp_env, "Project.toml")
    cp(project_toml_path, temp_project)

    println("Resolving dependencies...")

    # Activate the temporary environment
    Pkg.activate(temp_env)

    # Ensure package registry is available and up-to-date
    # This is necessary when adding packages to a new environment
    if !isempty(packages_to_add)
        println("Updating package registry...")
        Pkg.update()
    end

    # Add any additional packages specified via --add flags
    if !isempty(packages_to_add)
        println("Adding packages: $(join(packages_to_add, ", "))")
        for pkg_name in packages_to_add
            Pkg.add(pkg_name)
        end
    end

    # Resolve and install dependencies
    # This creates a Manifest.toml with resolved versions
    Pkg.instantiate()
    Pkg.resolve()

    # Read the generated Manifest.toml
    temp_manifest = joinpath(temp_env, "Manifest.toml")
    if !isfile(temp_manifest)
        error("Failed to generate Manifest.toml")
    end


    # Optionally generate the Bazel lockfile with integrity values
    if manifest_bazel_json_path !== nothing
        packages = parse_manifest_toml(temp_manifest)

        println()
        println("Generating Bazel lockfile with integrity values...")
        println()
        generate_bazel_lockfile(packages, manifest_bazel_json_path)
    end

    # Copy the generated Manifest.toml to the output location
    cp(temp_project, project_toml_path, force = true)
    cp(temp_manifest, manifest_toml_path, force = true)

    println()
    println("=" ^ 70)
    println("All files generated successfully!")
    println("=" ^ 70)
end

function main()
    # Change to workspace directory if running from Bazel
    if haskey(ENV, "BUILD_WORKSPACE_DIRECTORY") && isdir(ENV["BUILD_WORKSPACE_DIRECTORY"])
        cd(ENV["BUILD_WORKSPACE_DIRECTORY"])
    end

    # Parse arguments
    args = parse_args()
    project_toml = args["project_toml"]
    manifest_toml = args["manifest_toml"]
    manifest_bazel_json = args["manifest_bazel_json"]
    packages_to_add = args["add"]

    # Generate Manifest.toml and, if requested, Manifest.bazel.json
    generate_manifest(project_toml, manifest_toml, manifest_bazel_json, packages_to_add)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
