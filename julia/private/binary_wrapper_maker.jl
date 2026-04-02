"""
Template renderer for julia_binary_wrapper.

Reads a shell/batch template, splices runfiles library contents at marker
lines (file substitutions), applies string substitutions, and writes the
result. Invoked as a Bazel action by julia_binary_wrapper.
"""

function parse_args(args)
    output = nothing
    template = nothing
    substitutions = Dict{String,String}()
    file_substitutions = Dict{String,String}()

    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--output" && i + 1 <= length(args)
            output = args[i + 1]
            i += 2
        elseif arg == "--template" && i + 1 <= length(args)
            template = args[i + 1]
            i += 2
        elseif arg == "--substitution" && i + 2 <= length(args)
            substitutions[args[i + 1]] = args[i + 2]
            i += 3
        elseif arg == "--file_substitution" && i + 2 <= length(args)
            file_substitutions[args[i + 1]] = args[i + 2]
            i += 3
        else
            error("Unknown argument or missing value: $arg")
        end
    end

    output === nothing && error("--output is required")
    template === nothing && error("--template is required")

    return output, template, substitutions, file_substitutions
end

function main()
    output, template_path, substitutions, file_substitutions = parse_args(ARGS)

    text = read(template_path, String)

    for (marker, path) in file_substitutions
        contents = read(path, String)
        text = replace(text, marker => contents)
    end

    for (old, new) in substitutions
        text = replace(text, old => new)
    end

    write(output, text)
end

main()
