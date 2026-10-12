"""Deprecated alias of `julia_pkg_resolve`."""

load(":julia_pkg_resolve.bzl", "julia_pkg_resolve")

def julia_pkg_compiler(name, **kwargs):
    """Resolve Julia manifests from `Project.toml`; the former name of `julia_pkg_resolve`.

    Args:
        name (str): The name of the target.
        **kwargs: Forwarded to `julia_pkg_resolve`.

    Deprecated:
        Use `julia_pkg_resolve`. The rule was renamed because "package
        compiler" means PackageCompiler.jl to Julia users, and this rule runs
        Pkg's resolver. This alias will be removed in a future release.
    """

    # buildifier: disable=print
    print("`julia_pkg_compiler` is deprecated and will be removed in a future release; use `julia_pkg_resolve` for //{}:{}".format(
        native.package_name(),
        name,
    ))
    julia_pkg_resolve(name = name, **kwargs)
