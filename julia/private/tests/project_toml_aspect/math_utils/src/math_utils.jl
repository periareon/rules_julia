"""
Math utilities library for testing multiple dependencies.
"""

module math_utils

export add_numbers, multiply_numbers, get_pi

function add_numbers(a, b)
    """Add two numbers together."""
    return a + b
end

function multiply_numbers(a, b)
    """Multiply two numbers together."""
    return a * b
end

function get_pi()
    """Return an approximation of pi."""
    return 3.14159
end

end # module
