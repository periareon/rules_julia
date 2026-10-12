# rules_julia

This repository implements Bazel rules for the [Julia programming language](https://julialang.org/).

## Why rules_julia

rules_julia builds ordinary Julia packages. The `Project.toml` and
`src/Foo.jl` layout stays as it is, and dependencies come from the same
`Manifest.toml` that Pkg writes. What it adds over Pkg and PackageCompiler is
what Bazel adds to any language:

- **Shared, cached precompilation.** Pkg keeps precompile caches in each
  machine's depot, so every laptop and fresh CI runner rebuilds them. Here
  precompilation is a Bazel action, cached by its inputs and shareable through
  a remote cache.
- **Hermetic builds.** Toolchains, packages, and BinaryBuilder artifacts are
  fetched by checksum from a lockfile, with no Pkg, no `deps/build.jl`, and no
  `~/.julia` involved.
- **Incremental system images and binaries.** PackageCompiler rebuilds from
  scratch every time. `julia_sysimage` and `julia_standalone_binary` are
  ordinary targets, rebuilt only when their inputs change.
- **Explicit Julia versions.** Each Julia minor version gets its own manifest
  and toolchain, selected with a build setting.
- **One build graph.** In a repository that already uses Bazel, Julia code
  builds and tests alongside everything else, and unchanged tests are not
  rerun.

For a standalone Julia package, Pkg on its own may be all that is needed.

## Documentation

Documentation can be found at <https://periareon.github.io/rules_julia/>.
