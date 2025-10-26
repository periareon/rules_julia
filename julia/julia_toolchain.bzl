"""julia_toolchain"""

load(
    "//julia/private:toolchain.bzl",
    _TOOLCHAIN_TYPE = "TOOLCHAIN_TYPE",
    _julia_toolchain = "julia_toolchain",
)

julia_toolchain = _julia_toolchain
TOOLCHAIN_TYPE = _TOOLCHAIN_TYPE
