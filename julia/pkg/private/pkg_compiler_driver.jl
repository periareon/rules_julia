"""
Julia Package Manifest Generator driver

Runs `pkg_compiler.jl` once per manifest, each time with the Julia that the
manifest is declared for, so every manifest is resolved by its own Pkg. The
set of manifests, their Julia versions and the interpreters to use come from
the environment set by the `julia_pkg_compiler` rule.
"""

using Runfiles: rlocation

function locate(rlocationpath::String)
    path = rlocation(rlocationpath)
    if path === nothing || !ispath(path)
        error("Failed to locate runfile: $rlocationpath")
    end
    return path
end

function main()
    # Source files are addressed relative to the workspace.
    if haskey(ENV, "BUILD_WORKSPACE_DIRECTORY") && isdir(ENV["BUILD_WORKSPACE_DIRECTORY"])
        cd(ENV["BUILD_WORKSPACE_DIRECTORY"])
    end

    script = locate(ENV["RULES_JULIA_PKG_COMPILER_SCRIPT"])
    project_toml = abspath(ENV["RULES_JULIA_PKG_COMPILER_PROJECT_TOML"])
    manifest_bazel_json = if haskey(ENV, "RULES_JULIA_PKG_COMPILER_MANIFEST_BAZEL_JSON")
        abspath(ENV["RULES_JULIA_PKG_COMPILER_MANIFEST_BAZEL_JSON"])
    else
        nothing
    end

    entries = split(ENV["RULES_JULIA_PKG_COMPILER_MANIFESTS"], ";"; keepempty = false)
    failures = String[]
    for entry in entries
        version, manifest, julia_rlocation = split(entry, "|")
        julia = locate(String(julia_rlocation))
        manifest_toml = abspath(String(manifest))

        println("=" ^ 70)
        println("Resolving $(basename(manifest_toml)) with Julia $version")
        println("  julia: $julia")
        println("=" ^ 70)

        env = copy(ENV)
        env["RULES_JULIA_PKG_COMPILER_PROJECT_TOML"] = project_toml
        env["RULES_JULIA_PKG_COMPILER_MANIFEST_TOML"] = manifest_toml
        if manifest_bazel_json !== nothing
            env["RULES_JULIA_PKG_COMPILER_MANIFEST_BAZEL_JSON"] = manifest_bazel_json
        else
            delete!(env, "RULES_JULIA_PKG_COMPILER_MANIFEST_BAZEL_JSON")
        end
        # Resolve in a clean environment stack; the compiler activates its own.
        env["JULIA_LOAD_PATH"] = "@stdlib"
        delete!(env, "JULIA_PROJECT")

        cmd = Cmd(`$julia --startup-file=no --color=yes $script $ARGS`; env = env)
        process = run(ignorestatus(cmd))
        if !success(process)
            push!(failures, "$(basename(manifest_toml)) (Julia $version)")
        end
        println()
    end

    if !isempty(failures)
        println(stderr, "Failed to resolve: " * join(failures, ", "))
        exit(1)
    end
end

main()
