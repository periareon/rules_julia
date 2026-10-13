"""julia_artifact"""

load(
    "//julia/private:artifact.bzl",
    _JuliaArtifactInfo = "JuliaArtifactInfo",
    _julia_artifact = "julia_artifact",
)

julia_artifact = _julia_artifact
JuliaArtifactInfo = _JuliaArtifactInfo
