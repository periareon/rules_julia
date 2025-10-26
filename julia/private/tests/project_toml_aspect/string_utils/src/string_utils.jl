"""
String utilities library for testing multiple dependencies.
"""

module string_utils

export format_greeting, reverse_string, count_words, get_version

function format_greeting(name)
    """Format a greeting message."""
    return "Hello, $(name)!"
end

function reverse_string(s)
    """Reverse a string."""
    return reverse(s)
end

function count_words(text)
    """Count the number of words in a text."""
    return length(split(text))
end

function get_version()
    """Return the library version."""
    return "1.0.0"
end

end # module
