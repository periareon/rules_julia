# Shared by the JuliaFormatter checker and fixer.

using JuliaFormatter: JuliaFormatter

"""
    load_options(config_path) -> Dict{Symbol,Any}

Load formatter options from a config file as explicit keyword arguments for
`JuliaFormatter.format_file`. Explicit options take precedence over
discovered config files, and `config_applied` stops JuliaFormatter from
searching parent directories for `.JuliaFormatter.toml` at all.
"""
function load_options(config_path::String)::Dict{Symbol,Any}
    options = Dict{Symbol,Any}(
        Symbol(key) => value for (key, value) in JuliaFormatter.parse_config(config_path)
    )
    options[:config_applied] = true
    return options
end
