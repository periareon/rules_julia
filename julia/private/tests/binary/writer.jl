
"""
A small test script for writing output
"""

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

function main()
    output = parse_args()

    # Check that --output was provided
    if isnothing(output) || isempty(output)
        error("Usage: writer.jl --output <file path>")
    end

    # Create parent directory if needed
    mkpath(dirname(output))

    # Write the output
    open(output, "w") do f
        println(f, "La-Li-Lu-Le-Lo.")
    end
end

# Run main function
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
