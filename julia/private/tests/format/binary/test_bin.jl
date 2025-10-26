"""
A test binary for format checking
"""

function main()
    println("Hello from test_bin!")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
