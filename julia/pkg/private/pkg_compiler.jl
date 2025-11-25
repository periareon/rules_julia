"""
Julia Package Manifest Generator for Bazel

This script uses Julia's Pkg manager to resolve dependencies from Project.toml
and generate/update the Manifest.toml lockfile and Manifest.bazel.json with integrity values.
"""

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

    # Optional: Manifest.bazel.json path (defaults to Manifest.bazel.json next to Manifest.toml)
    if haskey(ENV, "RULES_JULIA_PKG_COMPILER_MANIFEST_BAZEL_JSON")
        args["manifest_bazel_json"] =
            abspath(ENV["RULES_JULIA_PKG_COMPILER_MANIFEST_BAZEL_JSON"])
    else
        # Derive from Manifest.toml path
        manifest_dir = dirname(args["manifest_toml"])
        args["manifest_bazel_json"] = joinpath(manifest_dir, "Manifest.bazel.json")
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

function write_json_array(io::IO, arr::Vector{String}, indent::String)
    """Write a JSON array of strings."""
    if isempty(arr)
        write(io, "[]")
        return
    end

    write(io, "[\n")
    for (i, item) in enumerate(arr)
        write(io, indent, "  \"", escape_json_string(item), "\"")
        if i < length(arr)
            write(io, ",")
        end
        write(io, "\n")
    end
    write(io, indent, "]")
end

function write_json_object(io::IO, obj::Dict{String,Any}, indent::String = "")
    """Write a JSON object manually."""
    write(io, "{\n")

    keys_list = sort(collect(keys(obj)))  # Sort for deterministic output
    for (i, key) in enumerate(keys_list)
        value = obj[key]
        write(io, indent, "  \"", escape_json_string(key), "\": ")

        if value isa String
            write(io, "\"", escape_json_string(value), "\"")
        elseif value isa Vector{String}
            write_json_array(io, value, indent * "  ")
        elseif value isa Dict
            write_json_object(io, value, indent * "  ")
        else
            error("Unsupported type: $(typeof(value))")
        end

        if i < length(keys_list)
            write(io, ",")
        end
        write(io, "\n")
    end

    write(io, indent, "}")
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

            lockfile[name] = Dict(
                "urls" => [url],
                "integrity" => integrity_value,
                "deps" => sort(deps),  # Sort dependencies for deterministic output
                "version" => version,
                "uuid" => uuid,
            )
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
    manifest_bazel_json_path::String,
    packages_to_add::Vector{String} = String[],
)
    """Generate Manifest.toml and Manifest.bazel.json from Project.toml using Pkg.

    This creates a temporary environment, copies the Project.toml,
    resolves dependencies, and generates both Manifest.toml and Manifest.bazel.json.

    Args:
        project_toml_path: Path to the Project.toml file
        manifest_toml_path: Path where Manifest.toml will be written
        manifest_bazel_json_path: Path where Manifest.bazel.json will be written
        packages_to_add: Optional list of package names to add before resolving dependencies
    """
    println("=" ^ 70)
    println("Julia Package Manifest Generator")
    println("=" ^ 70)
    println("Project.toml: $project_toml_path")
    println("Manifest.toml: $manifest_toml_path")
    println("Manifest.bazel.json: $manifest_bazel_json_path")
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


    # Parse the manifest and generate Bazel lockfile
    packages = parse_manifest_toml(temp_manifest)

    println()
    println("Generating Bazel lockfile with integrity values...")
    println()
    generate_bazel_lockfile(packages, manifest_bazel_json_path)

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

    # Generate Manifest.toml and Manifest.bazel.json
    generate_manifest(project_toml, manifest_toml, manifest_bazel_json, packages_to_add)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
