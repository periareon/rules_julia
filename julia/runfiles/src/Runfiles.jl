"""
Bazel Runfiles library for Julia

This module provides utilities for locating runfiles in Bazel-built Julia programs.
Runfiles are data dependencies that are available at runtime.
"""
module Runfiles

export rlocation, create

"""
Structure to hold runfiles information
"""
struct RunfilesImpl
    directory::Union{String,Nothing}
    manifest::Union{Dict{String,String},Nothing}
end

"""
Find the path to the current executable.

This function tries multiple strategies to locate the executable path:
1. PROGRAM_FILE (when available in regular Julia execution)
2. ARGS[0] (when the script is executed directly)
3. Environment variables (JULIA_EXECUTABLE, etc.)
4. Fallback strategies for standalone binaries

Returns the executable path or empty string if not found.
"""
function find_executable_path()::String
    # Strategy 1: Try PROGRAM_FILE (works in regular Julia execution)
    try
        if isdefined(Base, :PROGRAM_FILE) &&
           !isempty(Base.PROGRAM_FILE) &&
           isabspath(Base.PROGRAM_FILE)
            return Base.PROGRAM_FILE
        end
    catch
        # PROGRAM_FILE might not be available in standalone binaries
    end

    # Strategy 2: Try ARGS[0] (when script is executed directly)
    if length(ARGS) > 0 && isfile(ARGS[1])
        return ARGS[1]
    end

    # Strategy 3: Try environment variables
    if haskey(ENV, "JULIA_EXECUTABLE") && !isempty(ENV["JULIA_EXECUTABLE"])
        return ENV["JULIA_EXECUTABLE"]
    end

    # Strategy 4: For standalone binaries, we might not have a reliable way
    # to detect the executable path, so return empty string
    return ""
end

"""
Find the runfiles directory adjacent to the current executable.

Looks for a directory named `{executable_name}.runfiles` in the same directory
as the current executable.
"""
function find_adjacent_runfiles_dir()::Union{String,Nothing}
    executable_path = find_executable_path()

    # If we don't have a valid executable path, return nothing
    if isempty(executable_path) || !isabspath(executable_path)
        return nothing
    end

    # Get the directory and name of the executable
    exe_dir = dirname(executable_path)
    exe_name = basename(executable_path)

    # Look for {executable_name}.runfiles directory
    runfiles_dir = joinpath(exe_dir, "$(exe_name).runfiles")
    if isdir(runfiles_dir)
        return runfiles_dir
    end

    return nothing
end

"""
Load a manifest file from the given path.

Returns a dictionary mapping runfile paths to their actual locations,
or Nothing if the manifest doesn't exist or is empty.
"""
function load_manifest_file(manifest_path::String)::Union{Dict{String,String},Nothing}
    if !isfile(manifest_path)
        return nothing
    end

    manifest = Dict{String,String}()
    open(manifest_path, "r") do f
        for line in eachline(f)
            line = strip(line)
            # Skip empty lines and comments
            if isempty(line) || startswith(line, "#")
                continue
            end

            # Parse "key value" format
            parts = split(line, " ", limit = 2)
            if length(parts) >= 2
                manifest[parts[1]] = parts[2]
            end
        end
    end

    return isempty(manifest) ? nothing : manifest
end

"""
Get the runfiles directory and manifest.

Returns a tuple of (directory, manifest) where either may be Nothing.
Searches in the following order:
1. RUNFILES_DIR environment variable
2. RUNFILES_MANIFEST_FILE environment variable
3. Adjacent .runfiles directory
"""
function get_runfiles_info()::Tuple{
    Union{String,Nothing},
    Union{Dict{String,String},Nothing},
}
    directory = nothing
    manifest = nothing

    # 1. Try RUNFILES_DIR environment variable
    if haskey(ENV, "RUNFILES_DIR") && !isempty(ENV["RUNFILES_DIR"])
        directory = ENV["RUNFILES_DIR"]
        # Check for manifest in the runfiles directory
        manifest_path = joinpath(directory, "MANIFEST")
        if isfile(manifest_path)
            manifest = load_manifest_file(manifest_path)
        end
        return (directory, manifest)
    end

    # 2. Try RUNFILES_MANIFEST_FILE environment variable
    if haskey(ENV, "RUNFILES_MANIFEST_FILE") && !isempty(ENV["RUNFILES_MANIFEST_FILE"])
        manifest_file = ENV["RUNFILES_MANIFEST_FILE"]
        manifest = load_manifest_file(manifest_file)
        # The directory might be the parent of the manifest file
        directory = dirname(manifest_file)
        return (directory, manifest)
    end

    # 3. Try to find adjacent .runfiles directory
    adjacent_dir = find_adjacent_runfiles_dir()
    if adjacent_dir !== nothing
        directory = adjacent_dir
        # Check for MANIFEST file in the runfiles directory
        manifest_path = joinpath(directory, "MANIFEST")
        if isfile(manifest_path)
            manifest = load_manifest_file(manifest_path)
        end
        return (directory, manifest)
    end

    # No runfiles found
    return (nothing, nothing)
end

"""
Create a Runfiles instance for accessing Bazel runfiles.

Returns Nothing if runfiles cannot be located.
"""
function create()::Union{RunfilesImpl,Nothing}
    (dir, manifest) = get_runfiles_info()

    # If we found neither directory nor manifest, return Nothing
    if dir === nothing && manifest === nothing
        return nothing
    end

    return RunfilesImpl(dir, manifest)
end

# Global default runfiles instance
const DEFAULT_RUNFILES = Ref{Union{RunfilesImpl,Nothing}}(nothing)

function get_default_runfiles()::Union{RunfilesImpl,Nothing}
    if DEFAULT_RUNFILES[] === nothing
        DEFAULT_RUNFILES[] = create()
    end
    return DEFAULT_RUNFILES[]
end

"""
    rlocation(path::String)::Union{String, Nothing}

Find the absolute path to a runfile using the default runfiles instance.

# Arguments
- `path`: The runfiles-relative path (e.g., "my_workspace/path/to/file.txt")

# Returns
The absolute path to the file, or Nothing if runfiles cannot be located

# Example
```julia
data_file = rlocation("my_workspace/data/input.txt")
if data_file !== nothing
    content = read(data_file, String)
end
```
"""
function rlocation(path::String)::Union{String,Nothing}
    rf = get_default_runfiles()
    if rf === nothing
        return nothing
    end
    return rlocation(rf, path)
end

"""
    rlocation(rf::RunfilesImpl, path::String)::Union{String, Nothing}

Find the absolute path to a runfile using a specific RunfilesImpl.

# Arguments
- `rf`: The RunfilesImpl instance to use
- `path`: The runfiles-relative path (e.g., "my_workspace/path/to/file.txt")

# Returns
The absolute path to the file, or Nothing if the file cannot be located
"""
function rlocation(rf::RunfilesImpl, path::String)::Union{String,Nothing}
    # First, try the manifest if it exists
    if rf.manifest !== nothing && haskey(rf.manifest, path)
        return rf.manifest[path]
    end

    # Otherwise, construct the path from the directory if we have one
    if rf.directory !== nothing
        full_path = joinpath(rf.directory, path)

        # Return the path if it exists
        if isfile(full_path) || isdir(full_path)
            return full_path
        end
    end

    # Could not locate the runfile
    return nothing
end

"""
    runfiles_dir()::Union{String, Nothing}

Get the runfiles directory path.

# Returns
The absolute path to the runfiles directory, or Nothing if not available
"""
function runfiles_dir()::Union{String,Nothing}
    rf = get_default_runfiles()
    if rf === nothing
        return nothing
    end
    return rf.directory
end

end # module
