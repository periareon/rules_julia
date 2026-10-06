# rules_julia system image driver
#
# Runs inside `julia --output-o` to produce the object archive for a system
# image containing a package and its dependencies. Modeled on Julia's own
# `juliac-buildscript.jl` and PackageCompiler's sysimage script: the package
# is loaded from a runfiles-shaped tree, precompile statements are executed,
# and all build-time state is cleared before the image is serialized.

# `--output-o` mode skips normal startup. The default load path is needed to
# import stdlibs (TOML) until the paths are configured below.
Sys.__init__()
Base.reinit_stdio()
Base.init_depot_path()
Base.init_load_path()
Base.init_active_project()

include(joinpath(@__DIR__, "rules_julia_common.jl"))

"""
Execute precompile statements (as produced by `--trace-compile`) so the
compiled methods are included in the image. Statements that fail to parse or
evaluate are skipped, as in `Base`'s own precompile generation.
"""
function run_precompile_statements(files::Vector{String})
    staging = Module()
    for file in files, statement in eachline(file)
        ps = try
            Meta.parse(statement)
        catch
            continue
        end
        Meta.isexpr(ps, :call) || continue
        popfirst!(ps.args) # precompile(...)
        ps.head = :tuple
        local args
        while true
            try
                args = Core.eval(staging, ps)
                break
            catch e
                if e isa UndefVarError
                    mods = filter(p -> p.first.name == string(e.var), Base.loaded_modules)
                    if length(mods) != 1
                        @goto skip
                    end
                    _, mod = only(mods)
                    Core.eval(staging, :($(e.var) = $mod))
                else
                    debug("Failed to execute `$statement`: $e")
                    @goto skip
                end
            end
        end
        precompile(args...)
        @label skip
    end
end

function main()
    flags = parse_flags(
        ARGS;
        scalars = ["--config", "--manifest", "--package"],
        lists = ["--precompile-statements"],
    )
    config = require_flag(flags, "--config")
    manifest = require_flag(flags, "--manifest")
    package = require_flag(flags, "--package")
    statements = abspath.(flags["--precompile-statements"])

    includes, depots, _ = read_config(config)

    tree = mktempdir(prefix = "rules_julia_sysimage_")
    install_tree(manifest, tree)

    empty!(DEPOT_PATH)
    configure_depots!(tree, depots)
    append_bundled_depots!(DEPOT_PATH)

    copy!(LOAD_PATH, ["@stdlib"])
    add_includes!(tree, includes)

    debug("DEPOT_PATH: $(DEPOT_PATH)")
    debug("LOAD_PATH: $(LOAD_PATH)")

    # The entrypoint that starts every binary needs TOML. On Julia 1.12 some
    # stdlibs ship as package images outside the stock system image, and
    # package images built against the stock image are rejected under a
    # custom one, so anything the runtime needs must be in the image itself.
    Base.require(Main, :TOML)

    Base.require(Main, Symbol(package))

    return package, statements
end

const PACKAGE, PRECOMPILE_STATEMENTS = main()

# Bind the package in `Main` so the entry point can be reached as
# `Main.<package>` once the image is in use. This happens at top level so the
# new binding is visible to the code below without a world age bump.
Core.eval(Main, Meta.parse("import $PACKAGE"))

let mod = getfield(Main, Symbol(PACKAGE))
    if isdefined(mod, :julia_main)
        precompile(Tuple{typeof(getfield(mod, :julia_main))})
    end
end
run_precompile_statements(PRECOMPILE_STATEMENTS)

# Clear build-time state so none of it is baked into the image. Julia
# re-initializes all of this at startup.
empty!(Core.ARGS)
empty!(Base.ARGS)
empty!(LOAD_PATH)
empty!(DEPOT_PATH)
empty!(Base.TOML_CACHE.d)
Base.TOML.reinit!(Base.TOML_CACHE.p, "")
Base.ACTIVE_PROJECT[] = nothing
@eval Base begin
    PROGRAM_FILE = ""
end
@eval Sys begin
    BINDIR = ""
    STDLIB = ""
end
