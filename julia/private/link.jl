# rules_julia system image linker
#
# Links the object archive produced by `julia --output-o` into a shared
# library with the `lld` bundled with Julia, through the same code path Julia
# uses to link its own package images. This works wherever Julia runs and
# needs no C++ toolchain.

include(joinpath(@__DIR__, "rules_julia_common.jl"))

function main()
    flags = parse_flags(ARGS; scalars = ["--archive", "--output"])
    archive = abspath(require_flag(flags, "--archive"))
    output = abspath(require_flag(flags, "--output"))

    mkpath(dirname(output))
    Base.Linking.link_image(archive, output)
    isfile(output) || error("Linking $archive produced no output at $output")
end

main()
