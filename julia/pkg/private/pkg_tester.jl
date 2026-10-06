"""
Julia Package Lockfile Test driver

Runs `pkg_tester_core.jl` once per manifest, each time with the Julia that
the manifest is declared for, so every manifest is verified by the Pkg that
resolved it. Runfiles are resolved here and passed on as absolute paths.
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
    println("=" ^ 70)
    println("Julia Package Lockfile Verification Test")
    println("=" ^ 70)

    core = locate(ENV["RULES_JULIA_PKG_TEST_CORE"])
    project_toml = locate(ENV["RULES_JULIA_PKG_TEST_PROJECT_TOML"])
    manifest_bazel_json = if haskey(ENV, "RULES_JULIA_PKG_TEST_MANIFEST_BAZEL_JSON")
        locate(ENV["RULES_JULIA_PKG_TEST_MANIFEST_BAZEL_JSON"])
    else
        nothing
    end

    entries = split(ENV["RULES_JULIA_PKG_TEST_MANIFESTS"], ";"; keepempty = false)
    failures = String[]
    for entry in entries
        version, manifest_rlocation, julia_rlocation = split(entry, "|")
        julia = locate(String(julia_rlocation))
        manifest_toml = locate(String(manifest_rlocation))

        println("Manifest $(basename(manifest_toml)), declared for Julia $version")

        env = copy(ENV)
        env["RULES_JULIA_PKG_TEST_PROJECT_TOML"] = project_toml
        env["RULES_JULIA_PKG_TEST_MANIFEST_TOML"] = manifest_toml
        env["RULES_JULIA_PKG_TEST_JULIA_VERSION"] = String(version)
        if manifest_bazel_json !== nothing
            env["RULES_JULIA_PKG_TEST_MANIFEST_BAZEL_JSON"] = manifest_bazel_json
        else
            delete!(env, "RULES_JULIA_PKG_TEST_MANIFEST_BAZEL_JSON")
        end
        env["JULIA_LOAD_PATH"] = "@stdlib"
        delete!(env, "JULIA_PROJECT")

        cmd = Cmd(`$julia --startup-file=no --color=yes $core`; env = env)
        if !success(run(ignorestatus(cmd)))
            push!(failures, "$(basename(manifest_toml)) (Julia $version)")
        end
        println()
    end

    if isempty(failures)
        println("=" ^ 70)
        println("SUCCESS: Manifest files are in sync!")
        println("=" ^ 70)
        exit(0)
    end

    label = ENV["RULES_JULIA_PKG_TEST_COMPILER_LABEL"]
    println("=" ^ 70)
    println("FAILED: " * join(failures, ", "))
    println()
    println("Please run the pkg_compiler to regenerate the lockfile(s):")
    println("  bazel run $(label)")
    println("=" ^ 70)
    exit(1)
end

try
    main()
catch e
    println(stderr, "Fatal error:")
    showerror(stderr, e, catch_backtrace())
    println(stderr)
    exit(1)
end
