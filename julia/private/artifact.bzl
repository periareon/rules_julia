"""julia_artifact"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(":julia_common.bzl", "DRIVER_ATTRS", "julia_common")
load(":platforms.bzl", "ARCH_CONSTRAINTS", "OS_CONSTRAINTS")
load(":toolchain.bzl", "TOOLCHAIN_TYPE")

JuliaArtifactInfo = provider(
    doc = "A Julia artifact tarball and the `Artifacts.toml` entry describing it.",
    fields = {
        "artifact_name": "str: The artifact's name in `Artifacts.toml`.",
        "artifacts_toml": "File: An `Artifacts.toml` holding the entry for the tarball.",
        "tarball": "File: The gzipped tarball.",
    },
)

# Platform tags the rule can derive from the configuration, in the order
# `Base.BinaryPlatforms` lists them.
PLATFORM_TAGS = ["os", "arch", "libc", "libgfortran_version", "cxxstring_abi"]

def _constraint_tag(ctx, names, targets, kind):
    """Name the target platform's value for a tag backed by `@platforms`."""
    for name, target in zip(names, targets):
        if ctx.target_platform_has_constraint(target[platform_common.ConstraintValueInfo]):
            return name
    fail("{}: the target platform has no {} Julia artifacts can be tagged with; known values: {}".format(
        ctx.label,
        kind,
        ", ".join(names),
    ))

def _platform_tags(ctx):
    """Collect the requested platform tags from the target configuration."""
    requested = ctx.attr.platform_tags
    for name in requested:
        if name not in PLATFORM_TAGS:
            fail("{}: unknown platform tag `{}`; `platform_tags` accepts {}".format(
                ctx.label,
                name,
                ", ".join(PLATFORM_TAGS),
            ))

    tags = {}
    os = None
    if "os" in requested or "libc" in requested:
        os = _constraint_tag(ctx, OS_CONSTRAINTS.keys(), ctx.attr._os_constraints, "os")
    if "os" in requested:
        tags["os"] = os
    if "arch" in requested:
        tags["arch"] = _constraint_tag(ctx, ARCH_CONSTRAINTS.keys(), ctx.attr._arch_constraints, "arch")

    # Only Linux platforms carry a `libc` tag in Julia; elsewhere it is dropped
    # so the entry matches what `HostPlatform()` reports there.
    if "libc" in requested and os == "linux":
        tags["libc"] = ctx.attr._libc[BuildSettingInfo].value

    # Julia writes the full version even though only the major matters.
    if "libgfortran_version" in requested:
        tags["libgfortran_version"] = ctx.attr._libgfortran_version[BuildSettingInfo].value + ".0.0"
    if "cxxstring_abi" in requested:
        tags["cxxstring_abi"] = ctx.attr._cxxstring_abi[BuildSettingInfo].value
    return tags

def _repo_relative(file):
    """The path of a file within its repository."""
    path = file.short_path
    if path.startswith("../"):
        path = path[len("../"):].split("/", 1)[-1]
    return path

def _strip(path, prefix):
    """Strip `prefix/` from `path`; `None` when `path` is not under it."""
    if not prefix:
        return path
    if path == prefix:
        return ""
    if path.startswith(prefix + "/"):
        return path[len(prefix) + 1:]
    return None

def _artifact_entries(ctx):
    """Map every input to its path inside the artifact.

    Returns:
        dict: Artifact path to `File`. The path `.` stands for the artifact
            root and is only valid for directories.
    """
    prefix = ctx.label.package
    if ctx.attr.strip_prefix:
        prefix = "{}/{}".format(prefix, ctx.attr.strip_prefix) if prefix else ctx.attr.strip_prefix
    prefix = prefix.strip("/")

    placements = []
    for file in ctx.files.srcs:
        dest = _strip(_repo_relative(file), prefix)
        if dest == None:
            fail("{}: `{}` is not under `{}`; use `files` to place files from elsewhere in the artifact".format(
                ctx.label,
                file.short_path,
                prefix,
            ))
        placements.append((dest, file))

    for target, dest in ctx.attr.files.items():
        files = target.files.to_list()
        if len(files) != 1:
            fail("{}: `files` entry `{}` must be a single file or directory, got {} files".format(
                ctx.label,
                target.label,
                len(files),
            ))
        placements.append((dest, files[0]))

    entries = {}
    for dest, file in placements:
        dest = dest.strip("/")
        if not dest or dest == ".":
            if not file.is_directory:
                fail("{}: `{}` would be the artifact root itself; files need a path inside the artifact".format(
                    ctx.label,
                    file.short_path,
                ))
            dest = "."
        if dest in entries:
            fail("{}: both `{}` and `{}` map to `{}` in the artifact".format(
                ctx.label,
                entries[dest].short_path,
                file.short_path,
                dest,
            ))
        entries[dest] = file
    return entries

def _julia_artifact_impl(ctx):
    toolchain_info = ctx.toolchains[TOOLCHAIN_TYPE]
    artifact_name = ctx.attr.artifact_name or ctx.label.name

    tarball = ctx.outputs.out or ctx.actions.declare_file(ctx.label.name + ".tar.gz")
    artifacts_toml = ctx.actions.declare_file(ctx.label.name + ".Artifacts.toml")

    entries = _artifact_entries(ctx)
    manifest = ctx.actions.declare_file(ctx.label.name + ".artifact_manifest")
    ctx.actions.write(
        output = manifest,
        content = "".join([
            "{}\t{}\n".format(dest, file.path)
            for dest, file in entries.items()
        ]),
    )

    args = ctx.actions.args()
    args.add("--output", tarball)
    args.add("--toml", artifacts_toml)
    args.add("--name", artifact_name)
    args.add("--manifest", manifest)
    for key, value in _platform_tags(ctx).items():
        args.add("--tag", "{}={}".format(key, value))
    if ctx.attr.lazy:
        args.add("--lazy", "true")
    if ctx.attr.url:
        args.add("--url", ctx.attr.url.replace("{file}", tarball.basename))

    julia_common.run_driver(
        ctx,
        toolchain_info = toolchain_info,
        driver = ctx.file._driver,
        arguments = args,
        inputs = depset([manifest] + entries.values()),
        outputs = [tarball, artifacts_toml],
        mnemonic = "JuliaArtifact",
    )

    return [
        DefaultInfo(files = depset([tarball, artifacts_toml])),
        OutputGroupInfo(
            artifacts_toml = depset([artifacts_toml]),
            tarball = depset([tarball]),
        ),
        JuliaArtifactInfo(
            artifact_name = artifact_name,
            artifacts_toml = artifacts_toml,
            tarball = tarball,
        ),
    ]

julia_artifact = rule(
    doc = """\
Build a Julia [artifact](https://pkgdocs.julialang.org/v1/artifacts/) from Bazel targets.

Julia distributes binaries and data as artifacts: gzipped tarballs identified by
the git tree hash of their contents and listed in a package's `Artifacts.toml`
with a download URL and SHA-256. This rule produces both halves: the tarball,
packed with the same `Tar` and `7z` Julia itself uses, and an `Artifacts.toml`
holding the entry for it, with both hashes computed by the code `Pkg` uses to
verify downloads. Upload the tarball to the URL and merge the entry into the
package's `Artifacts.toml`; `Pkg` and `artifact"name"` then install it like any
other artifact.

Files from `srcs` keep their path relative to the package (or `strip_prefix`
below it); `files` places outputs from anywhere at an explicit path. Directories
(tree artifacts) are copied whole.

Platform specific artifacts set `platform_tags`. The values are taken from the
target platform (`os`, `arch`) and the `@rules_julia//julia/settings` flags
(`libc`, `libgfortran_version`, `cxxstring_abi`), so building the same target
under several `--platforms` yields one entry per platform, ready to be
concatenated. Platform independent artifacts (data, models, ...) leave it empty.

Example:

```python
julia_artifact(
    name = "libfoo",
    srcs = ["include/foo.h"],
    files = {":libfoo_shared": "lib/libfoo.so"},
    platform_tags = ["os", "arch", "libc"],
    url = "https://github.com/me/Foo.jl/releases/download/v1.0.0/{file}",
)
```

produces `libfoo.tar.gz` and `libfoo.Artifacts.toml`:

```toml
[[libfoo]]
arch = "x86_64"
git-tree-sha1 = "..."
libc = "glibc"
os = "linux"

    [[libfoo.download]]
    sha256 = "..."
    url = "https://github.com/me/Foo.jl/releases/download/v1.0.0/libfoo.tar.gz"
```
""",
    implementation = _julia_artifact_impl,
    attrs = {
        "artifact_name": attr.string(
            doc = "The artifact's name in `Artifacts.toml`. Defaults to the target name.",
        ),
        "files": attr.label_keyed_string_dict(
            doc = (
                "Files or directories to place at an explicit path inside the artifact, " +
                "mapping each label to its destination. `.` places a directory's contents at the root."
            ),
            allow_files = True,
        ),
        "lazy": attr.bool(
            doc = "Mark the artifact lazy, so Julia only downloads it on first use.",
            default = False,
        ),
        "out": attr.output(
            doc = "The tarball to write. Defaults to `<name>.tar.gz`.",
        ),
        "platform_tags": attr.string_list(
            doc = (
                "Platform tags to record, any of `os`, `arch`, `libc`, `libgfortran_version` and " +
                "`cxxstring_abi`. Empty for platform independent artifacts. `libc` is only recorded on Linux."
            ),
        ),
        "srcs": attr.label_list(
            doc = "Files to include at their path relative to the package, or to `strip_prefix` within it.",
            allow_files = True,
        ),
        "strip_prefix": attr.string(
            doc = "A directory below the package that `srcs` paths are made relative to.",
        ),
        "url": attr.string(
            doc = (
                "The URL the tarball will be downloadable from, recorded in the entry. " +
                "`{file}` expands to the tarball's file name. Without it the entry has no download table."
            ),
        ),
        "_arch_constraints": attr.label_list(
            default = [Label(label) for label in ARCH_CONSTRAINTS.values()],
        ),
        "_cxxstring_abi": attr.label(
            default = Label("//julia/settings:cxxstring_abi"),
        ),
        "_driver": attr.label(
            default = Label("//julia/private:artifact.jl"),
            allow_single_file = True,
        ),
        "_libc": attr.label(
            default = Label("//julia/settings:libc"),
        ),
        "_libgfortran_version": attr.label(
            default = Label("//julia/settings:libgfortran_version"),
        ),
        "_os_constraints": attr.label_list(
            default = [Label(label) for label in OS_CONSTRAINTS.values()],
        ),
    } | DRIVER_ATTRS,
    provides = [JuliaArtifactInfo],
    toolchains = [TOOLCHAIN_TYPE],
)
