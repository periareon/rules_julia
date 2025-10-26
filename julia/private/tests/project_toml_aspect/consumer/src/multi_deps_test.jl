"""
Test program that uses math_utils, string_utils, and calc_utils libraries.
"""

using math_utils
using string_utils
using calc_utils

"""
    parse_args()

Parse command-line arguments to extract the output file path.
"""
function parse_args()
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

    # Validate argument
    if isnothing(output) || isempty(output)
        error("Usage: multi_deps_test.jl --output <file path>")
    end

    # Create parent directory if needed
    mkpath(dirname(output))

    # Write the output to file
    open(output, "w") do f
        println(f, "=== Multi Dependencies Test ===")

        # Test math_utils (no dependencies)
        println(f, "Testing math_utils:")
        result1 = math_utils.add_numbers(5, 3)
        println(f, "5 + 3 = $result1")

        result2 = math_utils.multiply_numbers(4, 7)
        println(f, "4 * 7 = $result2")

        pi_val = math_utils.get_pi()
        println(f, "Pi ≈ $pi_val")

        # Test string_utils (no dependencies)
        println(f, "")
        println(f, "Testing string_utils:")
        greeting = string_utils.format_greeting("World")
        println(f, "Greeting: $greeting")

        reversed = string_utils.reverse_string("Hello")
        println(f, "'Hello' reversed: $reversed")

        word_count = string_utils.count_words("This is a test sentence")
        println(f, "Word count: $word_count")

        version = string_utils.get_version()
        println(f, "String utils version: $version")

        # Test calc_utils (depends on math_utils - transitive dependency)
        println(f, "")
        println(f, "Testing calc_utils (transitive dependency):")
        area = calc_utils.calculate_area(5, 3)
        println(f, "Area of 5x3 rectangle: $area")

        perimeter = calc_utils.calculate_perimeter(5, 3)
        println(f, "Perimeter of 5x3 rectangle: $perimeter")

        circle_area, circle_circumference = calc_utils.get_circle_info(2)
        println(
            f,
            "Circle with radius 2 - Area: $circle_area, Circumference: $circle_circumference",
        )

        # Combined test
        println(f, "")
        println(f, "Combined test:")
        combined_result = math_utils.add_numbers(
            string_utils.count_words("Hello world test"),
            math_utils.multiply_numbers(2, 3),
        )
        println(f, "Combined result: $combined_result")

        println(f, "")
        println(f, "=== Test completed successfully! ===")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
