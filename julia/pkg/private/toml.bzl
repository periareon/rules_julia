"""TOML decoding for the files Julia's `Pkg` writes.

Parsing is delegated to `toml.bzl`. This wrapper only attributes failures to
the file being read, since `toml.decode` reports syntax errors without one.
"""

load("@toml.bzl//:toml.bzl", "toml")

# Returned by `toml.decode` in place of failing. A TOML document always
# decodes to a dict, so no valid document can collide with it.
_INVALID = struct()

def parse_toml(content, label = "TOML"):
    """Decode TOML text into nested dicts and lists.

    Args:
        content (str): The TOML text.
        label (str): Describes the source of `content` in error messages.

    Returns:
        dict: The decoded document.
    """
    data = toml.decode(content, default = _INVALID)
    if data == _INVALID:
        fail("{}: not valid TOML".format(label))
    return data
