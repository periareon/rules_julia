"""
Julia Standalone Binary Compiler

This script uses PackageCompiler.jl to create standalone Julia applications.
It uses aspect-generated Project.toml files that contain dependency information
with relative paths from the runfiles root.
"""

import Pkg
import UUIDs
import TOML
import PackageCompiler
import Random

# Check if debug logging is enabled
const DEBUG = haskey(ENV, "RULES_JULIA_DEBUG")

macro debug(msg)
    quote
        if DEBUG
            println(stderr, $(esc(msg)))
        end
    end
end


function parse_args()
    """Parse command-line arguments for the compiler."""
    args = Dict{String,Any}()
    i = 1
    while i <= length(ARGS)
        if ARGS[i] == "--app-name" && i < length(ARGS)
            args["app_name"] = ARGS[i+1]
            i += 2
        elseif ARGS[i] == "--project-root" && i < length(ARGS)
            # Root include path for the project
            args["project_root"] = ARGS[i+1]
            i += 2
        elseif ARGS[i] == "--project-bin" && i < length(ARGS)
            # Runfiles rlocation path to the main binary file
            args["project_bin"] = ARGS[i+1]
            i += 2
        elseif ARGS[i] == "--output" && i < length(ARGS)
            # Output parent directory (PackageCompiler will create app/, lib/, share/ subdirs)
            args["output"] = ARGS[i+1]
            i += 2
        elseif ARGS[i] == "--runfiles-manifest" && i < length(ARGS)
            # Path to the runfiles manifest file
            args["runfiles_manifest"] = ARGS[i+1]
            i += 2
        elseif ARGS[i] == "--project-toml" && i < length(ARGS)
            # Project.toml file to copy in format {rlocationpath}={execpath}
            if !haskey(args, "project_tomls")
                args["project_tomls"] = String[]
            end
            push!(args["project_tomls"], ARGS[i+1])
            i += 2
        elseif ARGS[i] == "--project-root-toml" && i < length(ARGS)
            # Path to the root Project.toml file for validation
            args["project_root_toml"] = ARGS[i+1]
            i += 2
        else
            i += 1
        end
    end

    # Validate required arguments
    required_args = [
        "app_name",
        "project_root",
        "project_bin",
        "output",
        "runfiles_manifest",
        "project_root_toml",
    ]
    for arg in required_args
        if !haskey(args, arg) || isnothing(args[arg])
            error("Required argument --$(replace(arg, "_" => "-")) is missing")
        end
    end

    project_tomls = Dict{String,String}()
    for spec in args["project_tomls"]
        parts = split(spec, "=", limit = 2)
        if length(parts) != 2
            error("Invalid project-toml spec (expected rlocationpath=execpath): $spec")
        end

        rlocation_path = parts[1]
        exec_path = parts[2]
        project_tomls[rlocation_path] = exec_path
    end
    args["project_tomls"] = project_tomls

    return args
end


function load_runfiles_manifest(manifest_path::String)
    """Load the runfiles manifest file into a dictionary.

    The manifest format is: rlocation_path actual_path (delimited by first space)
    Returns a dictionary mapping rlocation_path => actual_path
    """
    if !isfile(manifest_path)
        error("Runfiles manifest not found: $manifest_path")
    end

    manifest_entries = Dict{String,String}()
    open(manifest_path, "r") do f
        for line in eachline(f)
            line = strip(line)
            if isempty(line)
                continue
            end
            parts = split(line, " ", limit = 2)
            if length(parts) == 2
                manifest_entries[parts[1]] = parts[2]
            end
        end
    end

    return manifest_entries
end

function sync_runfiles(
    project_dir::String,
    manifest_entries::Dict{String,String},
    include_paths::Vector{String},
)
    """Copy all runfiles under the include paths to the project directory.

    Uses the runfiles manifest to find files whose keys start with any of the
    include paths, then copies them to preserve the directory structure.
    """
    @debug "Syncing runfiles for $(length(include_paths)) include paths..."

    # Copy all files whose keys start with any include path
    copied_count = 0
    for (rloc_path, actual_path) in manifest_entries
        # Check if this file is under any include path
        for include_path in include_paths
            if startswith(rloc_path, include_path * "/") || rloc_path == include_path
                # Copy this file to the project directory, preserving structure
                dest_path = joinpath(project_dir, rloc_path)
                mkpath(dirname(dest_path))
                cp(actual_path, dest_path, force = true)
                copied_count += 1
                @debug "Copied runfile: $rloc_path"

                # Don't check other include paths for this file
                break
            end
        end
    end

    @debug "Copied $copied_count runfiles from manifest"
end

function validate_project_structure(
    project_root_toml::String,
    project_bin_rlocation::String,
    app_name::String,
)
    """Validate that the project structure is correct.

    Checks that:
    1. The Project.toml file exists and contains the expected app name
    2. The project-bin runfiles path is in the correct format (src/{app_name}.jl)
    """
    @debug "Validating project structure..."

    # Check that Project.toml exists
    if !isfile(project_root_toml)
        error("Project.toml not found: $project_root_toml")
    end

    # Parse Project.toml to get the project name
    project_data = TOML.parsefile(project_root_toml)
    project_name = get(project_data, "name", nothing)

    if isnothing(project_name)
        error("Project.toml does not contain a 'name' field: $project_root_toml")
    end

    # Validate that project name matches app name
    if project_name != app_name
        error(
            "Project name '$project_name' from Project.toml does not match app name '$app_name'",
        )
    end

    # Get the directory containing the project-bin file from the runfiles path
    project_bin_dir = dirname(project_bin_rlocation)
    project_bin_filename = basename(project_bin_rlocation)

    # Check if the directory is named 'src'
    if basename(project_bin_dir) != "src"
        error("Project binary must be in a 'src' directory, but found in: $project_bin_dir")
    end

    # Check that the filename matches '{app_name}.jl'
    expected_filename = "$(app_name).jl"
    if project_bin_filename != expected_filename
        error(
            "Project binary filename '$project_bin_filename' does not match expected '$expected_filename'",
        )
    end
end

function install_project_tomls(
    project_dir::String,
    project_toml_specs::Dict{String,String},
    project_root::String,
)
    """Install Project.toml and Manifest.toml files to their specified locations.

    Each spec is in the format: rlocationpath=execpath
    The file at execpath will be installed to project_dir/rlocationpath but renamed to Project.toml
    The corresponding Manifest.toml will be derived by replacing "Project.toml" with "Manifest.toml"
    """
    @debug "Installing $(length(project_toml_specs)) Project.toml and Manifest.toml files..."

    for (rlocation_path, exec_path) in project_toml_specs
        # Create destination path: use the directory from rlocation_path but rename to Project.toml
        rlocation_dir = dirname(rlocation_path)
        dest_project_path = joinpath(project_dir, rlocation_dir, "Project.toml")

        mkpath(dirname(dest_project_path))
        cp(exec_path, dest_project_path, force = true)

        # Also install the corresponding Manifest.toml by replacing Project.toml with Manifest.toml
        manifest_exec_path = replace(exec_path, "Project.toml" => "Manifest.toml")
        dest_manifest_path = joinpath(project_dir, rlocation_dir, "Manifest.toml")
        cp(manifest_exec_path, dest_manifest_path, force = true)
        @debug "Installed Project.toml: $rlocation_path -> $dest_project_path"
    end

    # Load the project_root Project.toml and Manifest.toml into variables
    # If project_root is absolute, use it directly; otherwise join with project_dir
    if isabspath(project_root)
        root_project_toml_path = joinpath(project_root, "Project.toml")
        root_manifest_toml_path = joinpath(project_root, "Manifest.toml")
    else
        root_project_toml_path = joinpath(project_dir, project_root, "Project.toml")
        root_manifest_toml_path = joinpath(project_dir, project_root, "Manifest.toml")
    end

    if !isfile(root_project_toml_path)
        error("Root Project.toml not found: $root_project_toml_path")
    end
    if !isfile(root_manifest_toml_path)
        error("Root Manifest.toml not found: $root_manifest_toml_path")
    end

    # Load the original Project.toml and Manifest.toml
    original_project_data = TOML.parsefile(root_project_toml_path)
    manifest_data = TOML.parsefile(root_manifest_toml_path)

    # Delete existing files.
    rm(root_project_toml_path; force = true)
    rm(root_manifest_toml_path; force = true)

    # Create a new Project.toml with no dependencies
    new_project_data = Dict{String,Any}()
    for (key, value) in original_project_data
        if key != "deps"
            new_project_data[key] = value
        end
    end

    # Write the new Project.toml
    open(root_project_toml_path, "w") do f
        TOML.print(f, new_project_data)
    end

    # Collect all dependencies into a dict of name -> path
    # Error if any manifest dependency doesn't have a path
    # Do not include dependencies that match the name in the original project.toml
    project_name = get(original_project_data, "name", nothing)
    deps = get(manifest_data, "deps", Dict{String,Any}())
    local_deps = Dict{String,String}()

    for (dep_name, dep_info) in deps
        # Skip dependencies that match the project name
        if dep_name == project_name
            continue
        end

        dep_path = dep_info[1]["path"]
        local_deps[dep_name] = dep_path
    end

    @debug "Rewrote Project.toml with no dependencies"
    @debug "Found $(length(local_deps)) local dependencies to develop"

    open(root_manifest_toml_path, "w") do f
        write(f, "# This file is machine-generated - editing it directly is not advised\n")
    end

    cd(dirname(root_project_toml_path)) do
        # Capture stdout and stderr
        original_stdout = stdout
        original_stderr = stderr
        stream = Pipe()

        try
            if !DEBUG
                redirect_stdout(stream)
                redirect_stderr(stream)
            end

            # Activate the project and develop all dependencies
            Pkg.activate(".")

            # Develop all local dependencies
            for (dep_name, dep_path) in local_deps
                @debug "Developing dependency '$dep_name' from path: $dep_path"
                Pkg.develop(Pkg.PackageSpec(name = dep_name, path = dep_path))
            end
        finally
            # Always restore original stdout and stderr
            if !DEBUG
                redirect_stdout(original_stdout)
                redirect_stderr(original_stderr)
                close(stream)
                content = read(stream, String)
                if !isempty(content)
                    println(stderr, content)
                end
            end
        end
    end

    @debug "Developed all local dependencies"
end


function resolve_compiler_path(env_var_name::String)
    """Resolve compiler path from environment variable.

    If the path contains '/' but is not absolute, prefix with pwd().
    Otherwise, return as-is (handles both absolute paths and bare commands like 'gcc').
    """
    if !haskey(ENV, env_var_name)
        return nothing
    end

    path = ENV[env_var_name]

    # If path contains '/' but doesn't start with '/', make it absolute
    if occursin('/', path) && !startswith(path, '/')
        return joinpath(pwd(), path)
    end

    # Otherwise return as-is (absolute path or bare command name)
    return path
end

function compile_app(
    project_dir::String,
    output_dir::String,
    app_name::String,
    project_bin::String,
)
    """
    Compile the Julia application using PackageCompiler.

    The project_bin is the runfiles rlocation path to the main file.
    """
    abs_project_dir = abspath(project_dir)
    if !isdir(abs_project_dir)
        error("Project dir does not exist: $(abs_project_dir)")
    end

    # Ensure output directory exists
    abs_output_dir = abspath(output_dir)
    mkpath(abs_output_dir)

    rel_project_bin = relpath(project_bin, project_dir)

    # Resolve compiler paths
    cc_path = resolve_compiler_path("CC")
    cxx_path = resolve_compiler_path("CXX")
    ar_path = resolve_compiler_path("AR")

    if isnothing(cc_path)
        error("No CC environment value found")
    elseif isnothing(cxx_path)
        error("No CXX environment value found")
    elseif isnothing(ar_path)
        error("No AR environment value found")
    end

    # Append compiler flags to the compiler paths
    cflags = get(ENV, "CFLAGS", "")
    cxxflags = get(ENV, "CXXFLAGS", "")

    # Create compiler commands with flags appended
    cc_with_flags =
        isnothing(cc_path) ? nothing : (isempty(cflags) ? cc_path : "$cc_path $cflags")
    cxx_with_flags =
        isnothing(cxx_path) ? nothing :
        (isempty(cxxflags) ? cxx_path : "$cxx_path $cxxflags")

    # Use withenv to temporarily set environment variables
    withenv(
        "CC"=>cc_with_flags,
        "JULIA_CC"=>cc_with_flags,
        "CXX"=>cxx_with_flags,
        "JULIA_CXX"=>cxx_with_flags,
        "AR"=>ar_path,
        "JULIA_AR"=>ar_path,
    ) do
        # Capture stdout and stderr
        original_stdout = stdout
        original_stderr = stderr
        stream = Pipe()
        try
            if !DEBUG
                redirect_stdout(stream)
                redirect_stderr(stream)
            end

            Pkg.activate(abs_project_dir)
            Pkg.precompile(timing = true)

            PackageCompiler.create_app(
                abs_project_dir,
                abs_output_dir;
                filter_stdlibs = false,
                force = true,
                include_lazy_artifacts = true,
                include_transitive_dependencies = true,
                incremental = false,
                #precompile_execution_file = String[],  # Disable precompilation
            )

        finally
            # Always restore original stdout and stderr
            if !DEBUG
                redirect_stdout(original_stdout)
                redirect_stderr(original_stderr)
                close(stream)
                content = read(stream, String)
                if !isempty(content)
                    println(stderr, content)
                end
            end
        end
    end
end



function main()
    @debug "\n1. Parsing arguments..."
    args = parse_args()

    # 1. Load runfiles manifest
    @debug "\n2. Loading runfiles manifest..."
    manifest_entries = load_runfiles_manifest(args["runfiles_manifest"])
    @debug "  Loaded $(length(manifest_entries)) manifest entries"

    # 2. Set up project directory in temp location
    # The output directory is where PackageCompiler will create app/, lib/, share/
    # We create a project/ subdirectory for the working files in temp space
    output_parent = args["output"]
    temp_dir = mktempdir(prefix = "rjlsa_", cleanup = false)
    project_dir = joinpath(temp_dir, "project")
    mkpath(project_dir)
    @debug "\n3. Setting up project directory: $project_dir"

    @debug "\n4. Validating project structure..."
    validate_project_structure(
        args["project_root_toml"],
        args["project_bin"],
        args["app_name"],
    )

    @debug "\n5. Syncing runfiles"
    project_tomls = args["project_tomls"]
    include_paths = String[]
    for path in keys(project_tomls)
        push!(include_paths, dirname(path))
    end

    sync_runfiles(project_dir, manifest_entries, include_paths)

    install_project_tomls(project_dir, project_tomls, args["project_root"])

    # Verify that a Project.toml exists at the project root
    root_project_toml = joinpath(project_dir, args["project_root"], "Project.toml")
    if !isfile(root_project_toml)
        error("Missing Project.toml: $(root_project_toml)")
    end
    root_manifest_toml = joinpath(project_dir, args["project_root"], "Manifest.toml")
    if !isfile(root_manifest_toml)
        error("Missing Manifest.toml: $(root_manifest_toml)")
    end

    # 6. Compile the application
    @debug "\n7. Compiling application..."

    # PackageCompiler will create app/, lib/, share/ subdirectories in output_parent
    compile_app(
        dirname(root_project_toml),
        output_parent,
        args["app_name"],
        joinpath(project_dir, args["project_bin"]),
    )

    # 7. Sanity check: ensure output directories are not empty
    @debug "\n8. Verifying output directories..."
    bin_dir = joinpath(output_parent, "bin")
    lib_dir = joinpath(output_parent, "lib")
    share_dir = joinpath(output_parent, "share")

    for (dir_name, dir_path) in [("bin", bin_dir), ("lib", lib_dir), ("share", share_dir)]
        if !isdir(dir_path)
            error("Expected $dir_name directory not found: $dir_path")
        end

        # Check if directory is empty
        contents = readdir(dir_path)
        if isempty(contents)
            error("$dir_name directory is empty: $dir_path")
        end

        @debug "✓ $dir_name directory contains $(length(contents)) items"
    end

    # 8. Clean up temporary directory after successful compilation
    @debug "\n9. Cleaning up temporary directory..."
    rm(temp_dir, recursive = true, force = true)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
