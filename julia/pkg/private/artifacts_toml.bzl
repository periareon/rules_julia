"""Reading Julia `Artifacts.toml` files.

```toml
[[Bzip2]]
arch = "x86_64"
git-tree-sha1 = "715b660f53eb83c33e199a44ececfd8dc03f2a27"
libc = "glibc"
os = "linux"

    [[Bzip2.download]]
    sha256 = "..."
    url = "https://github.com/JuliaBinaryWrappers/Bzip2_jll.jl/releases/download/..."
```

Platform specific artifacts are arrays of tables keyed by platform tags.
Platform independent artifacts (data files, models, ...) are a single table
without tags.
"""

load(":toml.bzl", "parse_toml")

# Keys of an artifact table that are not platform tags.
_NON_TAG_KEYS = ["git-tree-sha1", "download", "lazy"]

def _artifact_entry(name, table, label):
    tree_hash = table.get("git-tree-sha1")
    if not tree_hash:
        fail("{}: artifact `{}` is missing `git-tree-sha1`".format(label, name))

    downloads = table.get("download", [])
    if type(downloads) == "dict":
        downloads = [downloads]
    urls = []
    sha256 = None
    for download in downloads:
        url = download.get("url")
        if url:
            urls.append(url)
        if not sha256:
            sha256 = download.get("sha256")

    tags = {}
    for key, value in table.items():
        if key not in _NON_TAG_KEYS:
            tags[key] = str(value)

    return {
        "lazy": table.get("lazy", False) == True,
        "sha256": sha256 or "",
        "tags": tags,
        "tree_hash": tree_hash,
        "urls": urls,
    }

def parse_artifacts_toml(content, label = "Artifacts.toml"):
    """Parse the content of a Julia `Artifacts.toml` file.

    Args:
        content (str): The text of the file.
        label (str): A human readable name for the file used in error messages.

    Returns:
        dict: A mapping of artifact name to a list of variants. Each variant
            is a dict with keys `tags` (dict of platform tags, empty for
            platform independent artifacts), `tree_hash`, `urls`, `sha256`
            and `lazy`.
    """
    toml = parse_toml(content, label)

    artifacts = {}
    for name, value in toml.items():
        if type(value) == "dict":
            variants = [value]
        elif type(value) == "list":
            variants = value
        else:
            fail("{}: unexpected value for artifact `{}`".format(label, name))
        artifacts[name] = [_artifact_entry(name, variant, label) for variant in variants]

    return artifacts
