"""julia_standalone_binary"""

load(
    "//julia/private:standalone.bzl",
    _julia_standalone_binary = "julia_standalone_binary",
)

julia_standalone_binary = _julia_standalone_binary
