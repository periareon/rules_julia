"""Deprecated alias of `julia_pkg_resolve_test`."""

load(":julia_pkg_resolve_test.bzl", "julia_pkg_resolve_test")

def julia_pkg_test(name, compiler, **kwargs):
    """Check that manifests are up to date; the former name of `julia_pkg_resolve_test`.

    Args:
        name (str): The name of the target.
        compiler (Label): The `julia_pkg_resolve` (formerly `julia_pkg_compiler`)
            target to check; passed on as `resolver`.
        **kwargs: Forwarded to `julia_pkg_resolve_test`.

    Deprecated:
        Use `julia_pkg_resolve_test` with `resolver` in place of `compiler`.
        This alias will be removed in a future release.
    """

    # buildifier: disable=print
    print("`julia_pkg_test` is deprecated and will be removed in a future release; use `julia_pkg_resolve_test` for //{}:{}".format(
        native.package_name(),
        name,
    ))
    julia_pkg_resolve_test(name = name, resolver = compiler, **kwargs)
