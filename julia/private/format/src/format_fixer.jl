"""
JuliaFormatter wrapper for Bazel - Fixer

This script runs JuliaFormatter in fix mode on specified Julia source files.
It queries Bazel to find all Julia sources in the specified scope, then formats them.
All sources are copied to a temp directory with the config, formatted, and copied back.
"""

using JuliaFormatter: JuliaFormatter
using Runfiles: rlocation

const DEBUG = haskey(ENV, "RULES_JULIA_DEBUG")

function debug(msg)
    if DEBUG
        println(stderr, "[JuliaFormatFixer] ", msg)
    end
end

function find_bazel()::String
    """Locate a Bazel executable."""
    # Check common environment variables that Bazel sets
    if haskey(ENV, "BAZEL_REAL")
        return ENV["BAZEL_REAL"]
    end
    if haskey(ENV, "BAZEL")
        return ENV["BAZEL"]
    end

    # Try to find bazel in PATH
    for filename in ["bazel", "bazel.exe", "bazelisk", "bazelisk.exe"]
        try
            result = readchomp(`which $(filename)`)
            if !isempty(result) && isfile(result)
                return result
            end
        catch
            # Try direct execution - if the command exists, it might be in PATH
            try
                run(
                    pipeline(
                        `$(filename) version`;
                        stdout = IOBuffer(),
                        stderr = IOBuffer(),
                    ),
                )
                return filename  # Return just the filename if it's in PATH
            catch
                continue
            end
        end
    end

    return error(
        "Could not locate a Bazel binary. Set BAZEL_REAL or BAZEL environment variable, or ensure bazel/bazelisk is in PATH",
    )
end

function query_targets(
    scope::Vector{String},
    bazel::String,
    workspace_dir::String,
)::Vector{String}
    """Query for all source targets of all Julia targets within a given workspace.

    Args:
        scope: The scope of the Bazel query (e.g. `["//..."]`)
        bazel: The path to a Bazel binary.
        workspace_dir: The workspace root in which to query.

    Returns:
        A list of all discovered target labels.
    """
    # Query explanation:
    # Filter targets down to anything beginning with `//` and ends with `.jl`.
    #       Collect source files.
    #           Collect dependencies of targets for a given scope.
    #           Except for targets tagged to ignore formatting
    scope_str = join(scope, " ")
    # Build query template with string concatenation to avoid interpolation issues
    query_template = string(
        """filter("^//.*\\.jl\$", kind("source file", deps(set(""",
        scope_str,
        """) except attr(tags, "(^\\[|, )(noformat|no-format|nojuliafmt|no_juliafmt|no_format|no_julia_format)(, |\\]\$)", set(""",
        scope_str,
        """)), 1)))""",
    )

    debug("Running Bazel query: $query_template")
    debug("Bazel: $bazel")
    debug("Workspace: $workspace_dir")

    try
        cd(workspace_dir) do

            # Execute bazel query command - pass query template as a single string argument
            # Need to properly quote the query string when passing to shell
            # Use shell=true or construct command properly to ensure query is a single argument
            cmd = `$(bazel) query $(query_template) --noimplicit_deps --keep_going`
            query_result = readchomp(cmd)
            targets = filter(!isempty, split(query_result, "\n"))
            debug("Found $(length(targets)) targets")
            return targets
        end
    catch e
        error("Failed to run Bazel query: $e")
    end
end

function pathify(label::String)::String
    """Converts `//foo:bar` into `foo/bar`."""
    if startswith(label, "@")
        error("External labels are unsupported: $label")
    end
    if startswith(label, "//:")
        return label[4:end]
    end
    # Replace // with empty, then replace : with /
    label = replace(label, "//" => "")
    label = replace(label, ":" => "/")
    return label
end

function parse_args()
    """Parse command line arguments."""
    bazel = nothing
    scope = String[]
    config_path_env = nothing

    args = ARGS

    i = 1
    while i <= length(args)
        arg = args[i]
        if startswith(arg, "--bazel=")
            bazel = arg[9:end]  # Skip "--bazel="
            i += 1
        elseif arg == "--bazel" && i + 1 <= length(args)
            bazel = args[i+1]
            i += 2
        else
            # Everything else is scope
            push!(scope, arg)
            i += 1
        end
    end

    # Default scope if none provided
    if isempty(scope)
        scope = ["//...:all"]
    end

    # Find bazel if not provided
    if bazel === nothing
        bazel = find_bazel()
    end

    # Get config path from environment variable
    if !haskey(ENV, "JULIA_FORMATTER_CONFIG_PATH")
        error("JULIA_FORMATTER_CONFIG_PATH environment variable is not set")
    end
    config_path_env = ENV["JULIA_FORMATTER_CONFIG_PATH"]

    config_path = rlocation(config_path_env)
    if config_path === nothing
        error("Could not resolve JULIA_FORMATTER_CONFIG_PATH: $config_path_env")
    end

    if !isfile(config_path)
        error("Config file not found: $config_path")
    end

    return bazel, scope, config_path
end

function format_files(
    sources::Vector{String},
    config_path::String,
    workspace_dir::String,
)::Nothing
    """Format files by copying to temp directory, formatting, and copying back."""
    if isempty(sources)
        debug("No sources to format")
        return nothing
    end

    # Create a temporary directory for formatting
    tempdir = mktempdir(; prefix = "julia_format_fix_", cleanup = true)
    debug("Created temp directory: $tempdir")

    try
        # Copy config file to temp directory root
        config_basename = basename(config_path)
        temp_config = joinpath(tempdir, config_basename)
        cp(config_path, temp_config)
        debug("Copied config to: $temp_config")

        # Copy all source files to temp directory, preserving directory structure
        temp_sources = String[]
        for src in sources
            # Source paths are workspace-relative (e.g., "julia/private/tests/format/library/src/test_lib.jl")
            # Make absolute path by joining with workspace_dir
            src_abs = joinpath(workspace_dir, src)
            # Preserve this structure in the temp directory
            dest_file = joinpath(tempdir, src)
            dest_dir = dirname(dest_file)

            mkpath(dest_dir)
            cp(src_abs, dest_file)
            push!(temp_sources, dest_file)
            debug("Copied source: $src_abs -> $dest_file")
        end

        # Change to temp directory and perform formatting
        old_pwd = pwd()
        cd(tempdir)
        debug("Changed to temp directory: $tempdir")

        try
            # Format files using JuliaFormatter in fix mode (overwrite=true)
            formatted_files = String[]

            for temp_src in temp_sources
                # Get relative path from tempdir for format_file
                rel_path = relpath(temp_src, tempdir)
                debug("Formatting: $rel_path")

                # Format the file (overwrite=true means it will modify the file)
                JuliaFormatter.format_file(rel_path; overwrite = true, verbose = false)
                push!(formatted_files, temp_src)
                debug("Formatted: $rel_path")
            end

            # Copy formatted files back to workspace
            for (i, temp_src) in enumerate(formatted_files)
                original_src = joinpath(workspace_dir, sources[i])
                cp(temp_src, original_src; force = true)
                debug("Copied back: $temp_src -> $original_src")
            end

            debug("Successfully formatted $(length(formatted_files)) files")
        finally
            # Always restore original directory
            cd(old_pwd)
            debug("Restored directory: $old_pwd")
        end
    catch e
        println(stderr, "Error during formatting: $e")
        if DEBUG
            showerror(stderr, e, catch_backtrace())
        end
        rethrow(e)
    end
end

function main()
    try
        # Check for BUILD_WORKSPACE_DIRECTORY
        if !haskey(ENV, "BUILD_WORKSPACE_DIRECTORY")
            error(
                "BUILD_WORKSPACE_DIRECTORY is not set. Is the process running under Bazel?",
            )
        end

        workspace_dir = ENV["BUILD_WORKSPACE_DIRECTORY"]
        debug("Workspace directory: $workspace_dir")

        bazel, scope, config_path = parse_args()
        debug("Bazel: $bazel")
        debug("Scope: $scope")
        debug("Config: $config_path")

        # Query for all sources
        targets = query_targets(scope, bazel, workspace_dir)
        debug("Found $(length(targets)) targets to format")

        # Convert targets to file paths
        sources = [pathify(t) for t in targets]
        debug("Source paths: $sources")

        # Format the files
        format_files(sources, config_path, workspace_dir)

        exit(0)
    catch e
        println(stderr, "Error: $e")
        if DEBUG
            showerror(stderr, e, catch_backtrace())
        end
        exit(1)
    end
end

main()
