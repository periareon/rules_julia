"""Unit tests for the `Artifacts.toml` reader and platform selection."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//julia/pkg/private:artifacts_toml.bzl", "parse_artifacts_toml")
load("//julia/private:platforms.bzl", "abi_suffix", "choose_variants", "config_setting_text", "match_abi", "select_abi_variant", "selection_key")

_ARTIFACTS = """\
[[Bzip2]]
arch = "x86_64"
git-tree-sha1 = "715b660f53eb83c33e199a44ececfd8dc03f2a27"
libc = "glibc"
os = "linux"

    [[Bzip2.download]]
    sha256 = "a1"
    url = "https://example.com/Bzip2.x86_64-linux-gnu.tar.gz"

    [[Bzip2.download]]
    sha256 = "a1"
    url = "https://mirror.example.com/Bzip2.x86_64-linux-gnu.tar.gz"
[[Bzip2]]
arch = "armv6l"
call_abi = "eabihf"
git-tree-sha1 = "4a21f2ca0d8ba3abb1e8340bb27406ecc979c92b"
libc = "glibc"
os = "linux"

    [[Bzip2.download]]
    sha256 = "a2"
    url = "https://example.com/Bzip2.armv6l-linux-gnueabihf.tar.gz"
[[Bzip2]]
arch = "x86_64"
git-tree-sha1 = "c1600fa286afe4bf3616780a19b65285c63968ca"
os = "macos"

    [[Bzip2.download]]
    sha256 = "a3"
    url = "https://example.com/Bzip2.x86_64-apple-darwin.tar.gz"

[[Fortran]]
arch = "x86_64"
git-tree-sha1 = "0000000000000000000000000000000000000003"
libc = "glibc"
libgfortran_version = "3.0.0"
os = "linux"

    [[Fortran.download]]
    sha256 = "f3"
    url = "https://example.com/Fortran.libgfortran3.tar.gz"
[[Fortran]]
arch = "x86_64"
git-tree-sha1 = "0000000000000000000000000000000000000005"
libc = "glibc"
libgfortran_version = "5.0.0"
os = "linux"

    [[Fortran.download]]
    sha256 = "f5"
    url = "https://example.com/Fortran.libgfortran5.tar.gz"

[[Cxx]]
arch = "x86_64"
cxxstring_abi = "cxx11"
git-tree-sha1 = "0000000000000000000000000000000000000011"
libc = "glibc"
libstdcxx_version = "3.4.26"
os = "linux"

    [[Cxx.download]]
    sha256 = "c26"
    url = "https://example.com/Cxx.libstdcxx26.tar.gz"
[[Cxx]]
arch = "x86_64"
cxxstring_abi = "cxx11"
git-tree-sha1 = "0000000000000000000000000000000000000012"
libc = "glibc"
libstdcxx_version = "3.4.30"
os = "linux"

    [[Cxx.download]]
    sha256 = "c30"
    url = "https://example.com/Cxx.libstdcxx30.tar.gz"

[[Lazy]]
arch = "x86_64"
git-tree-sha1 = "0000000000000000000000000000000000000020"
lazy = true
os = "linux"
libc = "glibc"

    [[Lazy.download]]
    sha256 = "l0"
    url = "https://example.com/Lazy.tar.gz"

[Data]
git-tree-sha1 = "0000000000000000000000000000000000000030"

    [[Data.download]]
    sha256 = "d0"
    url = "https://example.com/data.tar.gz"
"""

def _parse_test_impl(ctx):
    env = unittest.begin(ctx)

    artifacts = parse_artifacts_toml(_ARTIFACTS, label = "//pkg:Artifacts.toml")
    asserts.equals(env, ["Bzip2", "Cxx", "Data", "Fortran", "Lazy"], sorted(artifacts.keys()))

    bzip2 = artifacts["Bzip2"]
    asserts.equals(env, 3, len(bzip2))
    asserts.equals(env, {"arch": "x86_64", "libc": "glibc", "os": "linux"}, bzip2[0]["tags"])
    asserts.equals(env, "715b660f53eb83c33e199a44ececfd8dc03f2a27", bzip2[0]["tree_hash"])
    asserts.equals(env, "a1", bzip2[0]["sha256"])
    asserts.equals(
        env,
        [
            "https://example.com/Bzip2.x86_64-linux-gnu.tar.gz",
            "https://mirror.example.com/Bzip2.x86_64-linux-gnu.tar.gz",
        ],
        bzip2[0]["urls"],
    )
    asserts.equals(env, False, bzip2[0]["lazy"])
    asserts.equals(env, "eabihf", bzip2[1]["tags"]["call_abi"])

    asserts.equals(env, True, artifacts["Lazy"][0]["lazy"])

    data = artifacts["Data"]
    asserts.equals(env, 1, len(data))
    asserts.equals(env, {}, data[0]["tags"])
    asserts.equals(env, ["https://example.com/data.tar.gz"], data[0]["urls"])

    return unittest.end(env)

_parse_test = unittest.make(_parse_test_impl)

def _selection_key_test_impl(ctx):
    env = unittest.begin(ctx)

    # ABI tags do not take part in the platform key; they are matched against
    # the toolchain at analysis time.
    key = selection_key({"arch": "x86_64", "cxxstring_abi": "cxx11", "libc": "glibc", "libgfortran_version": "5.0.0", "os": "linux"})
    asserts.true(env, key.supported)
    asserts.equals(env, "platform__linux_x86_64_glibc", key.name)
    asserts.equals(env, ["@platforms//os:linux", "@platforms//cpu:x86_64"], key.constraint_values)
    asserts.equals(env, {}, key.flag_values)

    # `call_abi` is ignored; unknown architectures are unsupported.
    asserts.true(env, selection_key({"arch": "armv7l", "call_abi": "eabihf", "libc": "glibc", "os": "linux"}).supported)
    asserts.false(env, selection_key({"arch": "armv6l", "call_abi": "eabihf", "libc": "glibc", "os": "linux"}).supported)
    asserts.false(env, selection_key({"arch": "x86_64", "os": "haiku"}).supported)

    # Only glibc is selectable on Linux until a libc constraint exists.
    asserts.false(env, selection_key({"arch": "x86_64", "libc": "musl", "os": "linux"}).supported)

    # Unknown ABI values are unsupported.
    asserts.false(env, selection_key({"arch": "x86_64", "libgfortran_version": "9.0.0", "os": "linux"}).supported)

    # Platform independent.
    independent = selection_key({})
    asserts.true(env, independent.supported)
    asserts.equals(env, "", independent.name)

    text = config_setting_text(selection_key({"arch": "aarch64", "os": "macos"}))
    asserts.true(env, "name = \"platform__macos_aarch64\"" in text)
    asserts.true(env, "@platforms//cpu:aarch64" in text)
    asserts.false(env, "flag_values" in text)

    asserts.equals(env, "libgfortran5_cxx11", abi_suffix({"cxxstring_abi": "cxx11", "libgfortran_version": "5.0.0", "os": "linux"}))
    asserts.equals(env, "any", abi_suffix({"arch": "x86_64", "os": "linux"}))

    return unittest.end(env)

_selection_key_test = unittest.make(_selection_key_test_impl)

def _choose_variants_test_impl(ctx):
    env = unittest.begin(ctx)

    artifacts = parse_artifacts_toml(_ARTIFACTS)

    bzip2 = choose_variants(artifacts["Bzip2"])
    asserts.equals(env, ["platform__linux_x86_64_glibc", "platform__macos_x86_64"], sorted(bzip2.selected.keys()))
    asserts.equals(env, ["a1"], [v["sha256"] for v in bzip2.selected["platform__linux_x86_64_glibc"].variants])
    asserts.equals(env, 1, len(bzip2.skipped))
    asserts.equals(env, "unsupported arch `armv6l`", bzip2.skipped[0][1])

    # ABI variants of one platform are all offered; the toolchain decides.
    fortran = choose_variants(artifacts["Fortran"])
    asserts.equals(env, ["platform__linux_x86_64_glibc"], fortran.selected.keys())
    asserts.equals(env, ["f3", "f5"], sorted([v["sha256"] for v in fortran.selected["platform__linux_x86_64_glibc"].variants]))

    # Variants differing only in unmodeled tags collapse to the highest version.
    cxx = choose_variants(artifacts["Cxx"])
    asserts.equals(env, ["c30"], [v["sha256"] for v in cxx.selected["platform__linux_x86_64_glibc"].variants])
    asserts.equals(env, 1, len(cxx.skipped))

    # Lazy artifacts are offered where a variant exists.
    lazy = choose_variants(artifacts["Lazy"])
    asserts.equals(env, ["platform__linux_x86_64_glibc"], lazy.selected.keys())
    asserts.equals(env, True, lazy.selected["platform__linux_x86_64_glibc"].variants[0]["lazy"])

    # Platform independent artifacts select unconditionally.
    data = choose_variants(artifacts["Data"])
    asserts.equals(env, [""], data.selected.keys())

    return unittest.end(env)

_choose_variants_test = unittest.make(_choose_variants_test_impl)

def _abi_match_test_impl(ctx):
    env = unittest.begin(ctx)

    official = {"cxxstring_abi": "cxx11", "libgfortran_version": "5"}

    # Tags on one side only match anything; tags on both sides must agree.
    asserts.true(env, match_abi({}, official))
    asserts.true(env, match_abi({"libgfortran_version": "5"}, official))
    asserts.false(env, match_abi({"libgfortran_version": "3"}, official))
    asserts.true(env, match_abi({"cxxstring_abi": "cxx11"}, {}))

    candidates = [
        struct(tags = {"libgfortran_version": "3"}, value = "f3"),
        struct(tags = {"libgfortran_version": "5"}, value = "f5"),
    ]
    asserts.equals(env, "f5", select_abi_variant(candidates, official).value)
    asserts.equals(env, "f3", select_abi_variant(candidates, {"libgfortran_version": "3"}).value)
    asserts.equals(env, None, select_abi_variant(candidates, {"libgfortran_version": "4"}))

    # The most specific match wins over a generic one.
    mixed = [
        struct(tags = {}, value = "generic"),
        struct(tags = {"cxxstring_abi": "cxx11"}, value = "specific"),
    ]
    asserts.equals(env, "specific", select_abi_variant(mixed, official).value)
    asserts.equals(env, "generic", select_abi_variant(mixed, {"cxxstring_abi": "cxx03"}).value)

    return unittest.end(env)

_abi_match_test = unittest.make(_abi_match_test_impl)

def artifacts_test_suite(name):
    """Define the test suite.

    Args:
        name (str): The name of the test suite.
    """
    unittest.suite(
        name,
        _parse_test,
        _selection_key_test,
        _choose_variants_test,
        _abi_match_test,
    )
