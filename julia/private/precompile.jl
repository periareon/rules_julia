# rules_julia precompile driver
#
# Precompiles a single Julia package into a depot directory so that binaries
# and tests can load it from a cache instead of compiling it at run time.
#
# The package's runfiles are materialized into a runfiles-shaped tree which is
# placed on `DEPOT_PATH`. Julia (1.11+) records source paths that live inside a
# depot as `@depot/...`, so the cache remains valid when the same files are
# later found under a binary's runfiles directory, which the entrypoint also
# puts on `DEPOT_PATH`.

include(joinpath(@__DIR__, "rules_julia_common.jl"))

function main()
    flags = parse_flags(ARGS; scalars = ["--config", "--manifest", "--depot", "--package"])
    config = require_flag(flags, "--config")
    manifest = require_flag(flags, "--manifest")
    depot = abspath(require_flag(flags, "--depot"))
    package = require_flag(flags, "--package")

    includes, depots, _ = read_config(config)

    tree = mktempdir(prefix = "rules_julia_precompile_")
    install_tree(manifest, tree)

    # Julia writes new caches to the first depot. The tree and dependency
    # depots follow, then the bundled depots for stdlib caches.
    copy!(DEPOT_PATH, [depot])
    configure_depots!(tree, depots)
    append_bundled_depots!(DEPOT_PATH)

    copy!(LOAD_PATH, ["@stdlib"])
    add_includes!(tree, includes)

    debug("DEPOT_PATH: $(DEPOT_PATH)")
    debug("LOAD_PATH: $(LOAD_PATH)")

    # Julia prints precompilation progress; only surface it on failure or when
    # debugging so successful actions stay quiet.
    log = tempname()
    try
        if DEBUG
            Base.require(Main, Symbol(package))
        else
            redirect_stdio(stdout = log, stderr = log) do
                Base.require(Main, Symbol(package))
            end
        end
    catch
        isfile(log) && print(stderr, read(log, String))
        rethrow()
    end

    # Everything but the package itself must have been loaded from an existing
    # cache. Anything else in the output depot means a dependency's cache was
    # rejected and the dependency was recompiled here, which would silently
    # duplicate work at every level of the dependency graph.
    found = false
    unexpected = String[]
    compiled = joinpath(depot, "compiled")
    for (dir, _, files) in (isdir(compiled) ? walkdir(compiled) : ()), file in files
        rel = relpath(joinpath(dir, file), compiled)
        # Entries under `compiled/v1.x/` are `<Name>.ji` and `<Name>.<dlext>`
        # (plus `<Name>.<dlext>.dSYM/...` on macOS) for packages without a
        # UUID, or a `<Name>/` directory for packages with one.
        parts = splitpath(rel)
        entry = length(parts) >= 2 ? parts[2] : parts[1]
        if first(split(entry, ".")) == package
            found = true
        else
            push!(unexpected, rel)
        end
    end
    found || error("Precompiling `$package` produced no cache files.")
    isempty(unexpected) || error(
        "Precompiling `$package` also compiled other packages, meaning their " *
        "caches were stale or missing:\n  " * join(unexpected, "\n  "),
    )
end

main()
