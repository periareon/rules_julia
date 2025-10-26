"""
writelib - A simple Julia module for writing output files
"""
module writelib

export write_output

"""
    write_output(filename::String, content::String)

Write content to a file, creating parent directories if needed.
"""
function write_output(filename::String, content::String)
    # Ensure the directory exists
    mkpath(dirname(filename))

    # Write to the file
    open(filename, "w") do f
        println(f, content)
    end
end

end # module
