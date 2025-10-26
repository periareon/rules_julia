"""
JuliaFormatter wrapper for Bazel

This script runs JuliaFormatter in check mode on specified Julia source files.
It's designed to be used from Bazel rules for formatting checks.
"""

using JuliaFormatter: JuliaFormatter
using Runfiles: rlocation

const DEBUG = haskey(ENV, "RULES_JULIA_DEBUG")

function debug(msg)
    if DEBUG
        println(stderr, "[JuliaFormat] ", msg)
    end
end

function maybe_rlocationpath(path::String, use_runfiles::Bool)::String
    """Convert a runfile path to absolute path if needed."""
    if use_runfiles
        resolved = rlocation(path)
        if resolved == nothing
            error("Unable to locate runfile: $(path)")
        end
        return resolved
    end

    return path
end


function parse_args()
    """Parse command line arguments."""
    config_path = nothing
    marker_path = nothing
    sources_dict = Dict{String,String}()
    use_runfiles = false

    # Check if we should load from args file (test mode)
    if haskey(ENV, "RULES_JULIA_FORMAT_ARGS_FILE")
        args_file = rlocation(ENV["RULES_JULIA_FORMAT_ARGS_FILE"])
        if args_file === nothing
            error(
                "Could not resolve RULES_JULIA_FORMAT_ARGS_FILE: $(ENV["RULES_JULIA_FORMAT_ARGS_FILE"])",
            )
        end
        debug("Loading arguments from: $args_file")
        args_lines = readlines(args_file)
        # Filter out empty lines and use lines as args (multiline format)
        args = filter(line -> !isempty(strip(line)), args_lines)
        use_runfiles = true
    else
        args = ARGS
    end

    i = 1
    while i <= length(args)
        arg = args[i]
        if startswith(arg, "--config=")
            config_path = maybe_rlocationpath(arg[10:end], use_runfiles)  # Skip "--config="
            i += 1
        elseif arg == "--config" && i + 1 <= length(args)
            config_path = maybe_rlocationpath(args[i+1], use_runfiles)
            i += 2
        elseif startswith(arg, "--marker=")
            marker_path = maybe_rlocationpath(arg[10:end], use_runfiles)  # Skip "--marker="
            i += 1
        elseif arg == "--marker" && i + 1 <= length(args)
            marker_path = maybe_rlocationpath(args[i+1], use_runfiles)
            i += 2
        elseif startswith(arg, "--src=")
            original_path = arg[7:end]  # Skip "--src="
            resolved_path = maybe_rlocationpath(original_path, use_runfiles)
            sources_dict[original_path] = resolved_path
            i += 1
        elseif arg == "--src" && i + 1 <= length(args)
            original_path = args[i+1]
            resolved_path = maybe_rlocationpath(original_path, use_runfiles)
            sources_dict[original_path] = resolved_path
            i += 2
        else
            error("Unknown argument or missing value: $arg")
        end
    end

    if config_path === nothing
        error("--config is required")
    end

    if isempty(sources_dict)
        error("At least one --src must be provided")
    end

    # Verify files exist
    if !isfile(config_path)
        error("Config file not found: $config_path")
    end

    for (original_path, resolved_path) in sources_dict
        if !isfile(resolved_path)
            error("Source file not found: $resolved_path (original: $original_path)")
        end
    end

    return config_path, marker_path, sources_dict
end


function main()
    config_path, marker_path, sources_dict = parse_args()

    debug("Config: $config_path")
    debug("Sources dict: $sources_dict")
    if marker_path !== nothing
        debug("Marker: $marker_path")
    end

    # Create a temporary directory for formatting
    tempdir = mktempdir(; prefix = "julia_format_", cleanup = true)
    debug("Created temp directory: $tempdir")

    # Copy config file to temp directory root
    config_basename = basename(config_path)
    temp_config = joinpath(tempdir, config_basename)
    cp(config_path, temp_config)
    debug("Copied config to: $temp_config")

    # Copy all source files to temp directory, using paths specified on command line (key)
    temp_sources = String[]
    original_paths = String[]  # Keep track of original paths for error messages
    for (original_path, resolved_path) in sources_dict
        # Copy to temp directory using the original_path (key) as the destination path
        dest_file = joinpath(tempdir, original_path)
        dest_dir = dirname(dest_file)

        # Ensure destination directory exists
        if !ispath(dest_dir)
            mkpath(dest_dir)
            debug("Created destination directory: $dest_dir")
        end

        # Copy from the resolved path (actual file location) to the destination based on original path (key)
        cp(resolved_path, dest_file)
        push!(temp_sources, dest_file)
        push!(original_paths, original_path)
        debug("Copied source: $resolved_path -> $dest_file (original: $original_path)")
    end

    # Define variables that need to be accessed in finally block
    exit_code = 0
    all_formatted = true

    # Change to temp directory and perform formatting checks
    debug("Changed to temp directory: $tempdir")
    cd(tempdir) do
        # Format files using JuliaFormatter in check mode
        # format_file with overwrite=false returns true if the file is already formatted

        for (i, temp_src) in enumerate(temp_sources)
            # Get relative path from tempdir for format_file
            rel_path = relpath(temp_src, tempdir)
            debug("Checking format: $rel_path")

            # Check if file needs formatting
            # format_file returns true if file is already formatted (no changes needed)
            is_formatted =
                JuliaFormatter.format_file(rel_path; overwrite = false, verbose = false)
            if !is_formatted
                all_formatted = false
                exit_code = 1
                # Use original path for error message
                original_src = original_paths[i]
                println(stderr, "File is not formatted: $original_src")
            end
        end
    end


    # Create marker file if specified (for aspect mode)
    # This must be done after restoring the directory so paths are correct
    if marker_path !== nothing && all_formatted
        # Ensure the directory exists before creating the marker file
        marker_dir = dirname(marker_path)
        if !ispath(marker_dir)
            mkpath(marker_dir)
            debug("Created marker directory: $marker_dir")
        end
        touch(marker_path)
        debug("Created marker file: $marker_path")
    end

    exit(exit_code)
end

main()
