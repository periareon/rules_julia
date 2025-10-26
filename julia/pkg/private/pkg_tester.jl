"""
Julia Package Lockfile Test

This script verifies that Manifest.bazel.json is in sync with Manifest.toml.
Since we can't use external JSON packages, we do basic validation checks.
"""

using Pkg
using Runfiles: rlocation

function parse_args()
    """Parse command-line arguments from environment variables."""
    args = Dict{String,Any}()

    # Required environment variables set by the Bazel rule
    required_vars =
        ["RULES_JULIA_PKG_TEST_MANIFEST_TOML", "RULES_JULIA_PKG_TEST_MANIFEST_BAZEL_JSON"]

    for var in required_vars
        if !haskey(ENV, var)
            error("Environment variable $var is not set")
        end
        # Convert to absolute path
        key = lowercase(replace(var, "RULES_JULIA_PKG_TEST_" => ""))
        args[key] = rlocation(ENV[var])
    end

    return args
end

function parse_manifest_toml(manifest_path::String)
    """Parse Manifest.toml and extract package information."""
    manifest = Pkg.Types.read_manifest(manifest_path)

    packages = Dict{String,Any}()

    for (uuid, pkg_entry) in manifest
        # Skip Julia stdlib packages (they don't have a tree hash)
        if !isdefined(pkg_entry, :tree_hash) || isnothing(pkg_entry.tree_hash)
            continue
        end

        name = pkg_entry.name
        tree_hash = string(pkg_entry.tree_hash)
        version = string(pkg_entry.version)
        uuid_str = string(uuid)

        packages[name] =
            Dict("uuid" => uuid_str, "version" => version, "git-tree-sha1" => tree_hash)
    end

    return packages
end

function check_lockfile_basic(lockfile_path::String, toml_packages::Dict)
    """Do basic validation checks on the lockfile."""
    errors = String[]
    content = read(lockfile_path, String)

    # Check that the file is valid JSON (basic check)
    if !startswith(strip(content), "{") || !endswith(strip(content), "}")
        push!(errors, "Manifest.bazel.json is not a valid JSON object")
        return errors
    end

    # Check that each package from TOML is mentioned in the JSON
    for (name, toml_data) in toml_packages
        # Check package name exists
        if !contains(content, "\"$name\"")
            push!(
                errors,
                "Package '$name' from Manifest.toml not found in Manifest.bazel.json",
            )
            continue
        end

        # Check version is mentioned
        version = toml_data["version"]
        if !contains(content, "\"version\": \"$version\"")
            push!(
                errors,
                "Package '$name': version '$version' from Manifest.toml not found in Manifest.bazel.json",
            )
        end

        # Check UUID is mentioned
        uuid = toml_data["uuid"]
        if !contains(content, "\"uuid\": \"$uuid\"")
            push!(
                errors,
                "Package '$name': UUID '$uuid' from Manifest.toml not found in Manifest.bazel.json",
            )
        end

        # Check git-tree-sha1 is in a URL
        tree_hash = toml_data["git-tree-sha1"]
        if !contains(content, tree_hash)
            push!(
                errors,
                "Package '$name': git-tree-sha1 '$tree_hash' from Manifest.toml not found in any URL in Manifest.bazel.json",
            )
        end

        # Check that SHA256 field exists for this package
        # Look for the pattern after the package name
        pkg_section_start = findfirst("\"$name\": {", content)
        if pkg_section_start !== nothing
            # Find the next closing brace
            start_idx = pkg_section_start[end]
            depth = 1
            idx = start_idx + 1
            pkg_section_end = start_idx

            while idx <= length(content) && depth > 0
                if content[idx] == '{'
                    depth += 1
                elseif content[idx] == '}'
                    depth -= 1
                    if depth == 0
                        pkg_section_end = idx
                    end
                end
                idx += 1
            end

            pkg_section = content[start_idx:pkg_section_end]
            if !contains(pkg_section, "\"sha256\":")
                push!(
                    errors,
                    "Package '$name': missing 'sha256' field in Manifest.bazel.json",
                )
            elseif contains(pkg_section, "\"sha256\": \"\"")
                push!(
                    errors,
                    "Package '$name': 'sha256' field is empty in Manifest.bazel.json",
                )
            end
        end
    end

    return errors
end

function main()
    println("=" ^ 70)
    println("Julia Package Lockfile Verification Test")
    println("=" ^ 70)

    # Parse arguments
    args = parse_args()
    manifest_toml = args["manifest_toml"]
    manifest_bazel_json = args["manifest_bazel_json"]

    println("Manifest.toml: $manifest_toml")
    println("Manifest.bazel.json: $manifest_bazel_json")
    println()

    # Check files exist
    if !isfile(manifest_toml)
        println("ERROR: Manifest.toml not found: $manifest_toml")
        exit(1)
    end

    if !isfile(manifest_bazel_json)
        println("ERROR: Manifest.bazel.json not found: $manifest_bazel_json")
        exit(1)
    end

    # Parse Manifest.toml
    println("Parsing Manifest.toml...")
    toml_packages = parse_manifest_toml(manifest_toml)
    println("  Found $(length(toml_packages)) non-stdlib packages")
    println()

    # Verify lockfile
    println("Verifying Manifest.bazel.json...")
    errors = check_lockfile_basic(manifest_bazel_json, toml_packages)

    if isempty(errors)
        println()
        println("=" ^ 70)
        println("SUCCESS: Manifest files are in sync!")
        println("=" ^ 70)
        exit(0)
    else
        println()
        println("=" ^ 70)
        println("FAILED: Manifest files are out of sync!")
        println("=" ^ 70)
        println()
        println("Errors found:")
        for (i, error) in enumerate(errors)
            println("  $i. $error")
        end
        println()
        println("Please run the pkg_compiler to regenerate the lockfile:")
        println("  bazel run //path/to:pkg_update")
        println("=" ^ 70)
        exit(1)
    end
end

# Run the test
try
    main()
catch e
    println(stderr, "Fatal error:")
    showerror(stderr, e, catch_backtrace())
    println(stderr)
    exit(1)
end
