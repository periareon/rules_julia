# rules_julia entrypoint

module RulesJuliaInit
using Dates

# Check if debug logging is enabled
const DEBUG = haskey(ENV, "RULES_JULIA_DEBUG")

macro debug(msg)
    quote
        if DEBUG
            println(
                stderr,
                "[",
                Dates.format(Dates.now(), "HH:MM:SS.sss"),
                "] ",
                $(esc(msg)),
            )
        end
    end
end

# Function to parse command line arguments
function parse_args()
    # Validate arguments
    if length(ARGS) < 3
        println(stderr, "Usage: julia entrypoint.jl <config_file> <main.jl> -- [args...]")
        exit(1)
    end

    # Extract config and main script paths
    config_path = ARGS[1]
    main_path = ARGS[2]

    # Find `--` separator
    function find_separator()
        for (i, arg) in enumerate(ARGS)
            if i > 2 && arg == "--"
                return i
            end
        end
        return -1
    end

    separator_index = find_separator()

    if separator_index == -1
        println(stderr, "Missing -- separator after config and main script paths")
        exit(1)
    end

    # Extract extra args (after the separator)
    extra_args = ARGS[(separator_index+1):end]

    return config_path, main_path, extra_args
end

# Function to install runfiles from manifest to a directory
function install_runfiles_from_manifest(
    manifest_file::String,
    output_dir::String,
    include_paths::Vector{String} = String[],
)
    """Install files from a manifest file into a directory structure.

    Args:
        manifest_file: Path to the manifest file (format: rlocation_path real_path per line)
        output_dir: Directory where files should be installed
        include_paths: Optional list of include path prefixes to filter by. If provided,
                      only files whose rlocation paths start with one of these prefixes
                      will be installed.
    """
    use_symlinks = !Sys.iswindows()

    # Create runfiles directory map from manifest, filtering by include paths
    runfiles_map = Dict{String,String}()
    total_entries = 0
    if isfile(manifest_file)
        open(manifest_file, "r") do f
            for line in eachline(f)
                line = strip(line)
                if isempty(line)
                    continue
                end
                # Parse "rlocation_path real_path" format
                parts = split(line, " ", limit = 2)
                if length(parts) == 2
                    total_entries += 1
                    rlocation = parts[1]
                    real_path = parts[2]
                    # Only add if it matches an include path prefix
                    for include_path in include_paths
                        # If the include path ends with `/src`, also collect everything above it
                        # (e.g., Project.toml, Manifest.toml, etc.)
                        parent_path = nothing
                        if endswith(include_path, "/src")
                            # Get the parent directory by removing "/src"
                            parent_path = include_path[1:(end-4)]  # Remove "/src"
                        end

                        # Check if rlocation matches the include_path or its parent
                        if startswith(rlocation, include_path) ||
                           (parent_path !== nothing && startswith(rlocation, parent_path))
                            runfiles_map[rlocation] = real_path
                            break
                        end
                    end
                end
            end
        end
    end

    @debug "Filtered manifest: $(length(runfiles_map)) of $(total_entries) entries match include paths"

    # Install files from manifest
    for (rlocation, real_path) in runfiles_map
        abs_src = normpath(real_path)
        abs_dest = normpath(joinpath(output_dir, rlocation))

        # Create parent directory
        mkpath(dirname(abs_dest))

        # Copy or symlink the file
        if isfile(abs_src)
            if use_symlinks
                try
                    symlink(abs_src, abs_dest)
                catch e
                    # If symlink fails (e.g., permissions), fall back to copy
                    @debug "Symlink failed, copying instead: $(e)"
                    cp(abs_src, abs_dest; force = true)
                end
            else
                # On Windows, always copy files
                cp(abs_src, abs_dest; force = true)
            end
        elseif isdir(abs_src)
            # For directories, we could recursively copy, but typically manifests
            # only contain files. Log a warning if we encounter a directory.
            @debug "Skipping directory in manifest: $(abs_src)"
        end
    end

    @debug "Installed $(length(runfiles_map)) files from manifest to $(output_dir)"
end

# Function to compute include paths and set up LOAD_PATH
function compute_includes(config_path)
    # Load config file (simple line-based format)
    # Each line is an include path
    includes = String[]
    if isfile(config_path)
        open(config_path, "r") do f
            for line in eachline(f)
                line = strip(line)
                if !isempty(line)
                    push!(includes, line)
                end
            end
        end
    end

    # Determine RUNFILES_DIR
    runfiles_dir = ""

    if haskey(ENV, "RUNFILES_DIR")
        runfiles_dir = ENV["RUNFILES_DIR"]
        # Check if the directory actually exists
        if !isdir(runfiles_dir)
            @debug "RUNFILES_DIR set but directory does not exist: $(runfiles_dir)"
            # Fall through to manifest handling
            runfiles_dir = ""
        else
            # Check if the runfiles directory has more than just a `MANIFEST` file and `_repo_mapping`.
            # If it only has these, consider it "empty" and fall through to manifest handling.
            entries = readdir(runfiles_dir)
            # Filter out MANIFEST and _repo_mapping
            other_entries = filter(e -> e != "MANIFEST" && e != "_repo_mapping", entries)
            if isempty(other_entries) &&
               ("MANIFEST" in entries || "_repo_mapping" in entries)
                @debug "RUNFILES_DIR set but directory only contains MANIFEST/_repo_mapping: $(runfiles_dir)"
                # If RUNFILES_MANIFEST_FILE is not set, set it to the MANIFEST file path
                if !haskey(ENV, "RUNFILES_MANIFEST_FILE") && "MANIFEST" in entries
                    manifest_path = joinpath(runfiles_dir, "MANIFEST")
                    if isfile(manifest_path)
                        ENV["RUNFILES_MANIFEST_FILE"] = manifest_path
                        @debug "Set RUNFILES_MANIFEST_FILE to: $(manifest_path)"
                    end
                end
                # Fall through to manifest handling
                runfiles_dir = ""
            end
        end
    end

    # If no valid RUNFILES_DIR, try to create from manifest
    if isempty(runfiles_dir) && haskey(ENV, "RUNFILES_MANIFEST_FILE")
        manifest_file = ENV["RUNFILES_MANIFEST_FILE"]
        if isfile(manifest_file)
            # Create a temporary runfiles directory
            # Use TEST_TMPDIR if available (Bazel will clean it up), otherwise tempdir()
            temp_base = get(ENV, "TEST_TMPDIR", tempdir())
            runfiles_dir = mktempdir(temp_base; prefix = "runfiles_")

            @debug "Creating runfiles directory from manifest: $(runfiles_dir)"

            # Install files from manifest, filtering to only include paths for performance
            install_runfiles_from_manifest(manifest_file, runfiles_dir, includes)

            ENV["RUNFILES_DIR"] = runfiles_dir
        else
            # Use manifest file location as base (fallback)
            runfiles_dir = dirname(manifest_file)
            ENV["RUNFILES_DIR"] = runfiles_dir
        end
    end

    if isempty(runfiles_dir)
        println(
            stderr,
            "RUNFILES_DIR is not set and RUNFILES_MANIFEST_FILE is not provided or invalid.",
        )
        exit(1)
    end

    # Normalize path separators (important on Windows)
    runfiles_dir = normpath(runfiles_dir)

    # Make RUNFILES_DIR absolute
    if !isabspath(runfiles_dir)
        runfiles_dir = abspath(runfiles_dir)
    end
    ENV["RUNFILES_DIR"] = runfiles_dir

    # Build include paths and add them to LOAD_PATH
    # Normalize paths after joining to ensure consistent separators on Windows
    include_paths = [normpath(joinpath(runfiles_dir, inc)) for inc in includes]
    for inc_path in include_paths
        if !(inc_path in LOAD_PATH)
            push!(LOAD_PATH, inc_path)
        end
    end

    return runfiles_dir, include_paths
end

function initialize()
    # Parse arguments
    @debug "Parsing command line arguments."
    config_path, main_path, extra_args = parse_args()

    # Compute includes
    @debug "Computing includes."
    runfiles_dir, include_paths = compute_includes(config_path)

    @debug "Runfiles dir: $(runfiles_dir)"

    # Set up ARGS for the main script
    empty!(ARGS)
    append!(ARGS, extra_args)

    # Resolve main script path
    main_full_path = if isfile(main_path)
        abspath(main_path)
    elseif isabspath(main_path)
        main_path
    else
        candidate = joinpath(runfiles_dir, main_path)
        if isfile(candidate)
            abspath(candidate)
        else
            main_path
        end
    end

    # Debug output if requested
    @debug "Main: $(main_full_path)"
    @debug "Arguments: $(ARGS)"
    @debug "Include paths: $(include_paths)"
    @debug "LOAD_PATH: $(LOAD_PATH)"

    return main_full_path, include_paths
end

function build_subprocess_cmd(
    main_full_path,
    include_paths = String[],
    depot_path = nothing,
)
    """Build a Cmd object for executing a Julia script in a subprocess.

    Args:
        main_full_path: Path to the main Julia script to execute
        include_paths: Optional list of include paths to add to LOAD_PATH
        depot_path: Optional path to Julia depot directory (sets JULIA_DEPOT_PATH)
    """
    # Start with Base.julia_cmd() to preserve default flags and get the correct Julia command
    base_cmd = Base.julia_cmd()

    # Build command parts starting from the base command's exec array
    cmd_parts = collect(base_cmd.exec)

    # Add the main script and its arguments
    push!(cmd_parts, main_full_path)
    append!(cmd_parts, ARGS)

    # Create Cmd object from the command parts
    cmd = Cmd(cmd_parts)

    # Preserve environment variables and other properties from base command
    # Merge base_cmd.env with current ENV to ensure all variables are passed through
    env_dict = copy(ENV)
    if base_cmd.env !== nothing
        merge!(env_dict, base_cmd.env)
    end

    # Set JULIA_LOAD_PATH environment variable to preserve LOAD_PATH in subprocess
    separator = Sys.iswindows() ? ';' : ':'
    # Always preserve current global LOAD_PATH
    current_load_paths = collect(LOAD_PATH)
    all_paths = filter(p -> p != "", current_load_paths)

    # If include_paths are provided, filter to existing directories and add them
    if !isempty(include_paths)
        valid_paths = filter(isdir, include_paths)
        if !isempty(valid_paths)
            append!(all_paths, valid_paths)
        end
    end

    # Set JULIA_LOAD_PATH to preserve LOAD_PATH in subprocess
    env_dict["JULIA_LOAD_PATH"] = join(all_paths, separator)

    # Set JULIA_DEPOT_PATH if depot_path is provided
    if depot_path !== nothing && !isempty(depot_path)
        env_dict["JULIA_DEPOT_PATH"] = depot_path
    end

    # Set environment and ignorestatus
    cmd = setenv(cmd, env_dict)
    cmd = ignorestatus(cmd)

    return cmd
end
end

# Run initialization and get the main script path and include paths
RULES_JULIA_PROGRAM_FILE, RULES_JULIA_INCLUDE_PATHS = RulesJuliaInit.initialize()

if haskey(ENV, "RULES_JULIA_EXPERIMENTAL_ENTRYPOINT_INCLUDE")

    # Set PROGRAM_FILE to the actual script being executed
    RULES_JULIA_ORIGINAL_PROGRAM_FILE = PROGRAM_FILE
    global PROGRAM_FILE = RULES_JULIA_PROGRAM_FILE

    # Execute the main script
    try
        include(RULES_JULIA_PROGRAM_FILE)
    catch e
        println(stderr, "Error executing Julia script:")
        showerror(stderr, e, catch_backtrace())
        println(stderr)
        exit(1)
    finally
        # Restore original PROGRAM_FILE
        global PROGRAM_FILE = RULES_JULIA_ORIGINAL_PROGRAM_FILE
    end

else
    # Create a temporary directory for the depot path
    main_basename = splitext(basename(RULES_JULIA_PROGRAM_FILE))[1]
    depot_path = mktempdir(prefix = "rjl_$(main_basename)_", cleanup = true)

    # Build command to execute the script in a subprocess
    cmd = RulesJuliaInit.build_subprocess_cmd(
        RULES_JULIA_PROGRAM_FILE,
        RULES_JULIA_INCLUDE_PATHS,
        depot_path,
    )

    RulesJuliaInit.@debug "Executing subprocess: $(cmd)"

    # Run the command with ignorestatus so we can check exit code
    result = run(cmd, wait = true)
    exit(result.exitcode)
end

RulesJuliaInit.@debug "Done"
