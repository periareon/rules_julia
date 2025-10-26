"""
Calculation utilities library for testing multiple dependencies.
"""

module calc_utils

export calculate_area, calculate_perimeter, get_circle_info

function calculate_area(length, width)
    """Calculate area."""
    return length * width
end

function calculate_perimeter(length, width)
    """Calculate perimeter."""
    return (length + width) * 2
end

function get_circle_info(radius)
    """Get circle information."""
    pi_val = 3.14159
    area = radius * radius * pi_val
    circumference = radius * 2 * pi_val
    return (area, circumference)
end

end # module
