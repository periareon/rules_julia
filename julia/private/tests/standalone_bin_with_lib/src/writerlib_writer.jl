"""
A small script for writing text to a file using the writelib module
"""

module writerlib_writer

import writelib

function parse_args()
    """Parse command-line arguments to extract the output file path."""
    output = nothing
    i = 1
    while i <= length(ARGS)
        if ARGS[i] == "--output" && i < length(ARGS)
            output = ARGS[i+1]
            i += 2
        else
            i += 1
        end
    end
    return output
end

function julia_main()::Cint
    output = parse_args()

    # Validate argument
    if isnothing(output) || isempty(output)
        error("Usage: writerlib_writer.jl --output <file path>")
    end

    # Use the library
    writelib.write_output(output, "La-Li-Lu-Le-Lo.")

    return 0
end
end
