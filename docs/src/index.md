# rules_julia

## Overview

This repository implements Bazel rules for the [Julia programming language](https://julialang.org/).

## Setup

To begin using the rules, add the following to your `MODULE.bazel` file.

```python
bazel_dep(name = "rules_julia", version = "{version}")

julia = use_extension("@rules_julia//julia:extensions.bzl", "julia")
use_repo(julia, "julia_toolchains")

register_toolchains(
    "@julia_toolchains//:all",
)
```

The default Julia version is always registered. To make additional versions
available, request them and select one with the `version` setting:

```python
julia.toolchain(version = "1.11.9")
```

```text
bazel build --@rules_julia//julia/settings:version=1.11.9 //...
```

## Package layout

Targets follow Julia's conventions. A `julia_library` named `Foo` is loaded
with `using Foo` from `src/Foo.jl` (or `Foo.jl` next to the `BUILD.bazel`
file). When the package directory also holds a `Project.toml`, list it in
`data` so Julia loads the package through it. The package then has the name
and UUID recorded there, which packages such as `Preferences` and package
extensions depend on, and its dependencies resolve from the `[deps]` table:

```python
julia_library(
    name = "Foo",
    srcs = glob(["src/**/*.jl"]),
    data = ["Project.toml"],
    deps = ["@deps//:JSON"],
)
```

Packages installed by the `pkg` extension are always set up this way.

## External dependencies

Third party packages are declared the way Julia expects: a `Project.toml`
with a resolved `Manifest.toml` next to it. The `pkg` module extension turns
every package in the manifest into a `julia_library` target.

```python
pkg = use_extension("@rules_julia//julia/pkg:extensions.bzl", "pkg")
pkg.install(
    name = "deps",
    manifest = "//:Manifest.toml",
)
use_repo(pkg, "deps")
```

Packages are then available as `@deps//:<PackageName>`:

```python
julia_binary(
    name = "app",
    srcs = ["app.jl"],
    deps = ["@deps//:JSON"],
)
```

Package tarballs are fetched from the Julia package server using the UUID and
git tree hash recorded in the manifest. On Bazel 9 and newer the integrity value
of each tarball is stored in the `facts` section of `MODULE.bazel.lock` the first
time it is needed, so no additional lockfile has to be maintained. Keep
`--lockfile_mode` at its default (`update`) so the facts are persisted.

A `julia_pkg_compiler` target resolves manifests from `Project.toml` without
leaving Bazel, and `julia_pkg_test` fails when they drift apart. Pkg resolves
against one Julia version, so each manifest is declared with the Julia minor
version it is for and is resolved and verified under a toolchain of that
version, whatever the `version` setting selects elsewhere:

```python
load("@rules_julia//julia/pkg:defs.bzl", "julia_pkg_compiler", "julia_pkg_test")

julia_pkg_compiler(
    name = "pkg_update",
    project_toml = "Project.toml",
    manifests = {"Manifest.toml": "1.12"},
)

julia_pkg_test(
    name = "pkg_test",
    compiler = ":pkg_update",
)
```

```text
bazel run //:pkg_update
bazel run //:pkg_update -- --add JSON
```

### Several Julia versions

A manifest is only valid for the Julia minor version that resolved it: the
standard libraries, compat bounds and Pkg itself all move with the minor
version. A project supporting several versions carries one manifest per
version, following Pkg's `Manifest-v<major>.<minor>.toml` convention, and the
compiler resolves all of them in one run:

```python
julia_pkg_compiler(
    name = "pkg_update",
    project_toml = "Project.toml",
    manifests = {
        "Manifest-v1.10.toml": "1.10",
        "Manifest-v1.12.toml": "1.12",
    },
)
```

```python
pkg.install(
    name = "deps",
    manifests = [
        "//:Manifest-v1.10.toml",
        "//:Manifest-v1.12.toml",
    ],
)
```

The extension reads the Julia version recorded in each manifest and builds a
package graph per version. `@deps//:<PackageName>` selects the graph matching
`@rules_julia//julia/settings:version`, and every package is marked
incompatible with other versions, so targets depending on a package without a
manifest for the selected Julia are skipped by wildcard builds and fail with
Bazel's standard incompatibility message when built explicitly.

### Artifacts

Many packages depend on prebuilt binaries or data shipped as Julia
[artifacts](https://pkgdocs.julialang.org/v1/artifacts/), most visibly the
`_jll` packages wrapping C libraries. These are built by
[BinaryBuilder](https://github.com/JuliaPackaging/BinaryBuilder.jl) inside a
cross compilation environment that cannot be reproduced in a Bazel action, so
the published tarballs are consumed as-is, pinned by the SHA-256 and git tree
hash recorded in each package's `Artifacts.toml`.

The `pkg` extension defines a repository per artifact variant and selects one
for the target platform at analysis time, so only the variant in use is ever
downloaded. Operating system and CPU come from the target platform. The
remaining ABI tags Julia uses to pick a variant are flags that default to what
official Julia binaries are built with:

| Flag | Values | Default |
|---|---|---|
| `@rules_julia//julia/settings:libc` | `glibc`, `musl` | `glibc` |
| `@rules_julia//julia/settings:libgfortran_version` | `3`, `4`, `5` | `5` |
| `@rules_julia//julia/settings:cxxstring_abi` | `cxx03`, `cxx11` | `cxx11` |

Variants that differ only in tags the rules do not model (for example
`libstdcxx_version`) resolve to the newest one, matching what `Pkg` picks on a
current Julia. A package whose artifact has no variant for the target platform
fails to analyze with a message listing the platforms it is available for.
Lazy artifacts, which Julia itself only downloads on first use, are the
exception: they are fetched like any other where a variant exists, and simply
omitted on platforms without one, so a package that never touches the artifact
there still builds. Code that does touch it fails at the point of use, as it
would under Julia without network access.

Artifact metadata is recorded next to the package integrity values, in
`MODULE.bazel.lock` facts or in `Manifest.bazel.json`, so reading
`Artifacts.toml` happens once per package version.

### Publishing a module

Facts are only persisted in the root module's lockfile. A module consumed by
other Bazel modules should instead ship a `Manifest.bazel.json` so consumers
never download tarballs just to learn their hashes. Set `manifest_bazel_json`
on `julia_pkg_compiler` to generate it and pass it to `pkg.install` as
`lockfile` instead of `manifest`.

```python
pkg.install(
    name = "deps",
    lockfile = "//:Manifest.bazel.json",
)
```
