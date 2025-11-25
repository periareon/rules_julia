# rules_julia

## Overview

This repository implements Bazel rules for the [Julia programming language](https://julialang.org/).

## Setup

To begin using the rules, add the following to your `MODULE.bazel` file.

```python
bazel_dep(name = "rules_julia", version = "{version}")

julia = use_extension("@rules_julia//julia:extensions.bzl", "julia")
julia.toolchain(
    name = "julia_toolchains",
    version = "1.12.2",
)
use_repo(julia, "julia_toolchains")

register_toolchains(
    "@julia_toolchains//:all",
)
```
