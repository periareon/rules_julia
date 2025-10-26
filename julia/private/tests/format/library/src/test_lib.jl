"""
A test library for format checking
"""
module test_lib

export greet

"""
    greet(name::String)

Greet someone by name.
"""
function greet(name::String)
    println("Hello, $name!")
end

end # module
