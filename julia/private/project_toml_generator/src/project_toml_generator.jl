"""
Project.toml Generator for Julia Bazel Rules

This script generates Project.toml files based on dependency information
provided by Bazel aspects.
"""

import UUIDs
import TOML
import Pkg

const DEBUG = haskey(ENV, "RULES_JULIA_DEBUG")

function parse_args()
    """Parse command line arguments manually."""
    args = Dict{String,Any}()
    deps = String[]

    i = 1
    while i <= length(ARGS)
        arg = ARGS[i]
        if arg == "--label" && i + 1 <= length(ARGS)
            args["label"] = ARGS[i+1]
            i += 2
        elseif arg == "--name" && i + 1 <= length(ARGS)
            args["name"] = ARGS[i+1]
            i += 2
        elseif arg == "--version" && i + 1 <= length(ARGS)
            args["version"] = ARGS[i+1]
            i += 2
        elseif arg == "--uuid" && i + 1 <= length(ARGS)
            args["uuid"] = ARGS[i+1]
            i += 2
        elseif arg == "--base-uuid" && i + 1 <= length(ARGS)
            args["base-uuid"] = ARGS[i+1]
            i += 2
        elseif arg == "--output" && i + 1 <= length(ARGS)
            args["output"] = ARGS[i+1]
            i += 2
        elseif arg == "--output-manifest" && i + 1 <= length(ARGS)
            args["output-manifest"] = ARGS[i+1]
            i += 2
        elseif arg == "--include" && i + 1 <= length(ARGS)
            args["include"] = ARGS[i+1]
            i += 2
        elseif arg == "--dep" && i + 1 <= length(ARGS)
            push!(deps, ARGS[i+1])
            i += 2
        elseif arg == "--project" && i + 1 <= length(ARGS)
            # Store project arguments for later processing
            if !haskey(args, "project_args")
                args["project_args"] = String[]
            end
            push!(args["project_args"], ARGS[i+1])
            i += 2
        else
            i += 1
        end
    end

    # Check required arguments
    if !haskey(args, "label")
        error("--label is required")
    end
    if !haskey(args, "name")
        error("--name is required")
    end
    if !haskey(args, "include")
        error("--include is required")
    end
    if !haskey(args, "output")
        error("--output is required")
    end
    if !haskey(args, "output-manifest")
        error("--output-manifest is required")
    end
    if !haskey(args, "uuid") && !haskey(args, "base-uuid")
        error("Either --uuid or --base-uuid must be provided")
    end

    # Set defaults
    if !haskey(args, "version")
        args["version"] = "0.1.0"
    end

    args["dep"] = deps

    # Parse dependencies
    parsed_deps = Dict{String,String}()
    include_path = haskey(args, "include") ? args["include"] : ""

    for dep_arg in deps
        if '=' in dep_arg
            dep_name, dep_path = split(dep_arg, '=', limit = 2)
            parsed_deps[dep_name] = dep_path
        end
    end

    args["deps"] = parsed_deps
    return args
end

function generate_uuid_from_label(base_uuid_str, label)
    """Generate a deterministic UUID from a Bazel label using a base UUID."""
    base_uuid = UUIDs.UUID(base_uuid_str)
    # Convert label to string and use as input for UUID generation
    label_str = string(label)
    # Use UUIDs.uuid5 for deterministic UUID generation
    generated_uuid = UUIDs.uuid5(base_uuid, label_str)
    return string(generated_uuid)
end

function main()
    args = parse_args()

    # Determine UUID
    uuid = if haskey(args, "uuid")
        args["uuid"]
    else
        generate_uuid_from_label(args["base-uuid"], args["label"])
    end

    # Get parsed dependencies from args
    deps = args["deps"]

    # Create base Project.toml content
    project_data = Dict{String,Any}(
        "name" => args["name"],
        "uuid" => string(uuid),
        "version" => args["version"],
    )

    # Handle manifest file
    manifest_path = args["output-manifest"]

    # Create a temporary directory for Pkg operations
    temp_dir = mktempdir(prefix = "rjlptg_", cleanup = true)

    # Parse project arguments to understand the dependency structure
    project_args = Dict{String,String}()
    if haskey(args, "project_args")
        for project_arg in args["project_args"]
            if '=' in project_arg
                dep_path, dep_file = split(project_arg, '=', limit = 2)
                project_args[dep_path] = dep_file
            end
        end
    end

    # Copy all dependency Project.toml and Manifest.toml files to their proper locations in temp dir
    for (dep_path, dep_file) in project_args
        # Create the directory structure in temp dir
        temp_dep_dir = joinpath(temp_dir, dep_path)
        mkpath(temp_dep_dir)

        # Copy the Project.toml file
        temp_project_file = joinpath(temp_dep_dir, "Project.toml")
        cp(dep_file, temp_project_file)

        temp_manifest_file = joinpath(temp_dep_dir, "Manifest.toml")
        manifest_path = replace(dep_file, r"Project\.toml$" => "Manifest.toml")
        cp(manifest_path, temp_manifest_file)

        # Look at the Project.toml file and create an empty file at `src/{app_name}.jl`
        project_toml_content = TOML.parsefile(temp_project_file)
        if haskey(project_toml_content, "name")
            app_name = project_toml_content["name"]
            src_dir = joinpath(temp_dep_dir, "src")
            mkpath(src_dir)
            main_file = joinpath(src_dir, "$(app_name).jl")
            open(main_file, "w") do f
                write(f, "module $(app_name)\n\nend\n")
            end
        end
    end

    # Create the main project directory in temp dir
    main_project_dir = joinpath(temp_dir, args["include"])
    mkpath(main_project_dir)

    # Write the base Project.toml to the main project directory
    main_project_file = joinpath(main_project_dir, "Project.toml")
    open(main_project_file, "w") do f
        TOML.print(f, project_data)
    end

    main_manifest_file = joinpath(main_project_dir, "Manifest.toml")
    open(main_manifest_file, "w") do f
        write(f, "# This file is machine-generated - editing it directly is not advised\n")
    end

    path_prefix = relpath(temp_dir, main_project_dir)

    # Create a dummy General registry to prevent Pkg from trying to download it
    # This is necessary even with JULIA_PKG_OFFLINE=true when the depot is empty
    depot_path = first(Base.DEPOT_PATH)
    registry_dir = joinpath(depot_path, "registries", "General")
    if !isdir(registry_dir)
        mkpath(registry_dir)
        # Create a minimal Registry.toml that satisfies Pkg's requirements
        registry_toml = joinpath(registry_dir, "Registry.toml")
        open(registry_toml, "w") do f
            write(
                f,
                """
       name = "General"
       uuid = "23338594-aafe-5451-b93e-139f81909106"
       repo = "https://github.com/JuliaRegistries/General.git"

       [packages]
       """,
            )
        end
    end

    # Change to the main project directory and use Pkg to add dependencies
    cd(main_project_dir) do
        # Store the original relative paths for later replacement in Manifest.toml
        path_to_bazel_path = Dict{String,String}()

        # Capture Pkg.activate logging
        original_stdout = stdout
        original_stderr = stderr
        stream = Pipe()

        try
            if !DEBUG
                redirect_stdout(stream)
                redirect_stderr(stream)
            end

            Pkg.activate(".")

            for (dep_name, dep_path) in deps
                relative_path = replace(joinpath(path_prefix, dep_path), '\\' => '/')

                # Pkg.develop will normalize the path, so we need to predict what it will become
                # and map it back to our original path
                # Convert the relative path to an absolute path, then get the relative path from main_project_dir
                abs_dep_path = abspath(joinpath(main_project_dir, relative_path))

                normalized_path = relpath(abs_dep_path, main_project_dir)
                # Store the normalized path as-is; the replacement loop will handle normalization
                path_to_bazel_path[normalized_path] = relative_path

                Pkg.develop(Pkg.PackageSpec(name = dep_name, path = relative_path))
            end

        finally
            # Always restore original stdout and stderr
            if !DEBUG
                redirect_stdout(original_stdout)
                redirect_stderr(original_stderr)

                # Close the write ends of the pipes
                close(stream)

                # Read and print captured output if there was any
                content = read(stream, String)

                if !isempty(content)
                    println(stderr, content)
                end
            end
        end

        # Read the manifest file as text for string replacement
        manifest_text = read("Manifest.toml", String)

        # Read the project file as text for string replacement
        project_text = read("Project.toml", String)

        # Replace normalized paths with original relative paths
        # The loop normalizes paths to handle both Unix and Windows path formats that Pkg might have written
        for (original_path, bazel_path) in path_to_bazel_path
            # Normalize original_path to handle both Unix and Windows formats
            # Pkg writes paths with forward slashes to Project.toml even on Windows
            unix_path = replace(original_path, "\\" => '/')
            windows_path = replace(unix_path, '/' => "\\\\")

            # For manifest, use bazel_path as-is
            manifest_replacement = "path = \"$bazel_path\""
            project_replacement = "path = \"$unix_path\""

            # Replace in manifest
            manifest_text =
                replace(manifest_text, "path = \"$unix_path\"" => manifest_replacement)
            manifest_text =
                replace(manifest_text, "path = \"$windows_path\"" => manifest_replacement)

            # Replace in project (normalize to Unix format)
            project_text =
                replace(project_text, "path = \"$windows_path\"" => project_replacement)
        end

        # Write the updated manifest back
        write(main_manifest_file, manifest_text)

        # Write the updated manifest back
        write(main_project_file, project_text)
    end

    cp(main_project_file, args["output"])
    cp(main_manifest_file, args["output-manifest"])
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
