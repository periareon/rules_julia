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
