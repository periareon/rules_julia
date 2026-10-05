# rules_julia entrypoint

module RulesJuliaInit

include(joinpath(@__DIR__, "rules_julia_common.jl"))

macro debug(msg)
    quote
        if DEBUG
            t = time()
            ms = round(Int, (t - floor(t)) * 1000)
            timestamp = Libc.strftime("%H:%M:%S", t) * "." * lpad(ms, 3, '0')
            println(stderr, "[", timestamp, "] ", $(esc(msg)))
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

    # Find `--` separator (must be after config and main paths)
    separator_index = -1
    for i = 3:length(ARGS)
        if ARGS[i] == "--"
            separator_index = i
            break
        end
    end

    if separator_index == -1
        println(stderr, "Missing -- separator after config and main script paths")
        exit(1)
    end

    # Extract extra args (after the separator)
    extra_args = ARGS[(separator_index+1):end]

    return config_path, main_path, extra_args
end

# Install the runfiles listed in the config (plus the repo mapping and the
# contents of precompile depots) from a runfiles manifest into a directory.
function install_runfiles_from_manifest(
    manifest_file::String,
    output_dir::String,
    runfiles_paths::Vector{String},
    runfiles_dirs::Vector{String},
)
    runfiles_set = Set(runfiles_paths)
    dir_prefixes = [dir * "/" for dir in runfiles_dirs]
    keep(rlocation) =
        rlocation == "_repo_mapping" ||
        rlocation in runfiles_set ||
        any(prefix -> startswith(rlocation, prefix), dir_prefixes)

    installed = install_tree(manifest_file, output_dir; keep = keep)
    @debug "Installed $(length(installed)) files from manifest to $(output_dir)"
end

# Function to compute include paths and set up LOAD_PATH
function compute_includes(config_path)
    # Load config file in TOML format:
    # includes: Array of include paths for LOAD_PATH
    # runfiles: Array of all runfiles paths for manifest mode
    includes, depots, runfiles_paths = read_config(config_path)

    # Determine RUNFILES_DIR
    runfiles_dir = ""
    should_use_manifest = false

    if haskey(ENV, "RUNFILES_DIR")
        runfiles_dir = ENV["RUNFILES_DIR"]
        # Check if the directory actually exists
        if !isdir(runfiles_dir)
            @debug "RUNFILES_DIR set but directory does not exist: $(runfiles_dir)"
            # Fall through to manifest handling
            runfiles_dir = ""
            should_use_manifest = true
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
                should_use_manifest = true
            else
                # Directory exists and has some files, but check if the actual include paths exist
                # On Windows with manifest mode, the directory might exist but not have the actual source files
                has_actual_files = false
                for inc in includes
                    inc_path = normpath(joinpath(runfiles_dir, inc))
                    if isdir(inc_path)
                        has_actual_files = true
                        break
                    end
                end

                if !has_actual_files
                    @debug "RUNFILES_DIR exists but include paths are not present (manifest-only mode)"
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
                    should_use_manifest = true
                end
            end
        end
    else
        # RUNFILES_DIR not set, must use manifest
        should_use_manifest = true
    end

    # If no valid RUNFILES_DIR, try to create from manifest
    if isempty(runfiles_dir) && should_use_manifest && haskey(ENV, "RUNFILES_MANIFEST_FILE")
        manifest_file = ENV["RUNFILES_MANIFEST_FILE"]
        if isfile(manifest_file)
            # Create a temporary runfiles directory
            # Use TEST_TMPDIR if available (Bazel will clean it up), otherwise tempdir()
            temp_base = get(ENV, "TEST_TMPDIR", tempdir())
            runfiles_dir = mktempdir(temp_base; prefix = "runfiles_")

            @debug "Creating runfiles directory from manifest: $(runfiles_dir)"

            # Install files from manifest, filtering to runfiles_paths from config
            install_runfiles_from_manifest(
                manifest_file,
                runfiles_dir,
                runfiles_paths,
                depots,
            )

            ENV["RUNFILES_DIR"] = runfiles_dir
        else
            # Use manifest file location as base (fallback)
            runfiles_dir = dirname(manifest_file)
            ENV["RUNFILES_DIR"] = runfiles_dir
        end
    end

    # Error if we couldn't determine a valid runfiles location
    if isempty(runfiles_dir)
        if should_use_manifest
            println(
                stderr,
                "ERROR: RUNFILES_MANIFEST_FILE is not set or invalid, and RUNFILES_DIR is not usable.",
            )
        else
            println(
                stderr,
                "ERROR: Neither RUNFILES_DIR nor RUNFILES_MANIFEST_FILE are set or valid.",
            )
        end
        exit(1)
    end

    # Normalize path separators (important on Windows)
    runfiles_dir = normpath(runfiles_dir)

    # Make RUNFILES_DIR absolute
    if !isabspath(runfiles_dir)
        runfiles_dir = abspath(runfiles_dir)
    end
    ENV["RUNFILES_DIR"] = runfiles_dir

    # Expose build-time precompile caches and add the include paths to LOAD_PATH.
    configure_depots!(runfiles_dir, depots)
    include_paths = add_includes!(runfiles_dir, includes)

    return runfiles_dir, include_paths, runfiles_paths
end

function initialize()
    # Parse arguments
    @debug "Parsing command line arguments."
    config_path, main_path, extra_args = parse_args()

    # Compute includes
    @debug "Computing includes."
    runfiles_dir, include_paths, runfiles_paths = compute_includes(config_path)

    @debug "Runfiles dir: $(runfiles_dir)"
    @debug "DEPOT_PATH: $(DEPOT_PATH)"

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

end

# Run initialization and get the main script path and include paths
RULES_JULIA_PROGRAM_FILE, _ = RulesJuliaInit.initialize()

# Set PROGRAM_FILE so scripts using the `if abspath(PROGRAM_FILE) == @__FILE__`
# guard will execute their main function when include()'d.
# Uses Core.eval to set it in Base directly, which works on Julia 1.10+
# (unlike `global PROGRAM_FILE = ...` which fails on 1.10).
RULES_JULIA_ORIGINAL_PROGRAM_FILE = PROGRAM_FILE
Core.eval(Base, :(PROGRAM_FILE = $RULES_JULIA_PROGRAM_FILE))

# `include` is run through `invokelatest` so that the script's top-level
# expressions each observe the bindings defined before them. Wrapping the
# include in a single `try` expression pins the world age and, on Julia 1.12,
# a script that defines and then calls `main()` warns (and will later error).
# Uncaught errors propagate to Julia, which prints the error and exits 1.
Base.invokelatest(include, RULES_JULIA_PROGRAM_FILE)

Core.eval(Base, :(PROGRAM_FILE = $RULES_JULIA_ORIGINAL_PROGRAM_FILE))

RulesJuliaInit.@debug "Done"
