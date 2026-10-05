"""
JuliaFormatter wrapper for Bazel

This script runs JuliaFormatter in check mode on specified Julia source files
using an explicit config file. JuliaFormatter's upward search for
`.JuliaFormatter.toml` files is disabled so that config files outside the
workspace (e.g. in a parent directory of the repository) have no effect.
"""

using Runfiles: rlocation

include(joinpath(@__DIR__, "format_common.jl"))

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

    options = load_options(config_path)

    all_formatted = true
    for (original_path, resolved_path) in sort(collect(sources_dict))
        debug("Checking format: $original_path")
        is_formatted = JuliaFormatter.format_file(
            resolved_path;
            overwrite = false,
            verbose = false,
            options...,
        )
        if !is_formatted
            all_formatted = false
            println(stderr, "File is not formatted: $original_path")
        end
    end

    # Create marker file if specified (for aspect mode)
    if marker_path !== nothing && all_formatted
        mkpath(dirname(marker_path))
        touch(marker_path)
        debug("Created marker file: $marker_path")
    end

    exit(all_formatted ? 0 : 1)
end

main()
