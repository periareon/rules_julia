"""Mapping Julia artifact platforms onto Bazel configuration.

Julia describes the platform an artifact was built for with a set of tags
(see `Base.BinaryPlatforms`): `os` and `arch` are always present, Linux
artifacts add `libc`, and packages with Fortran or C++ code add
`libgfortran_version` and `cxxstring_abi`. At run time `Pkg` compares them
with the tags of the running Julia. Tags that only one side defines match
anything.

Under Bazel the choice is made in two steps so only relevant variants are
downloaded. `os` and `arch` map onto `@platforms` constraints and are decided
by `select()` in generated BUILD files; `libc` is assumed to be glibc on
Linux (see `ASSUMED_LINUX_LIBC`). The ABI tags describe the runtimes bundled
with the Julia distribution, so they are decided at analysis time against the
resolved toolchain's `libgfortran_version` and `cxxstring_abi` (see
`match_abi`). Tags that are not modeled (`libstdcxx_version`,
`julia_version`, GPU tags, ...) reduce to one deterministic choice.
"""

OS_CONSTRAINTS = {
    "freebsd": "@platforms//os:freebsd",
    "linux": "@platforms//os:linux",
    "macos": "@platforms//os:macos",
    "windows": "@platforms//os:windows",
}

ARCH_CONSTRAINTS = {
    "aarch64": "@platforms//cpu:aarch64",
    "armv7l": "@platforms//cpu:armv7",
    "i686": "@platforms//cpu:i386",
    "powerpc64le": "@platforms//cpu:ppc64le",
    "riscv64": "@platforms//cpu:riscv64",
    "x86_64": "@platforms//cpu:x86_64",
}

# Tags describing the runtimes bundled with a Julia distribution, matched
# against the toolchain at analysis time, with the values Julia uses.
ABI_TAGS = {
    "cxxstring_abi": ["cxx03", "cxx11"],
    "libgfortran_version": ["3", "4", "5"],
}

# Tags expressed as `@platforms` constraints.
_CONSTRAINT_TAGS = ["os", "arch"]

# The C library assumed on Linux. `@platforms` has no libc constraint and
# official Julia binaries are built against glibc, so musl variants are not
# selectable. TODO: derive this from the libc constraint in `platforms_contrib`
# once it is available, so musl toolchains and artifacts can be selected.
ASSUMED_LINUX_LIBC = "glibc"

# Tags that carry no information beyond `arch` for the platforms Julia ships.
_IGNORED_TAGS = ["call_abi"]

# Order of tags in generated names.
_NAME_ORDER = ["os", "arch", "libc"]
_ABI_NAME_ORDER = ["libgfortran_version", "cxxstring_abi"]

def normalize_tag(key, value):
    """Normalize a tag value to the form used in flags and names.

    `libgfortran_version` is written as a full version (`5.0.0`) but only
    the major version is meaningful.
    """
    if key == "libgfortran_version":
        return value.split(".")[0]
    return value

def unmodeled_tags(tags):
    """Return the tags of a variant that cannot be selected on."""
    return {
        key: value
        for key, value in tags.items()
        if key not in _CONSTRAINT_TAGS and key != "libc" and key not in ABI_TAGS and key not in _IGNORED_TAGS
    }

def selection_key(tags):
    """Describe the `config_setting` needed to select a variant.

    Args:
        tags (dict): The variant's platform tags.

    Returns:
        struct: With fields `supported` (bool), `reason` (str, why the variant
            is unsupported), `name` (str, empty for platform independent
            variants), `constraint_values` (list[str]) and `flag_values`
            (dict[str, str]).
    """
    constraint_values = []
    flag_values = {}
    name_parts = []
    unsupported = None

    for key in ABI_TAGS:
        if key in tags and normalize_tag(key, tags[key]) not in ABI_TAGS[key]:
            return struct(
                supported = False,
                reason = "unsupported {} `{}`".format(key, tags[key]),
                name = "",
                constraint_values = [],
                flag_values = {},
            )

    for key in _NAME_ORDER:
        if key not in tags:
            continue
        value = normalize_tag(key, tags[key])
        if key == "os":
            if value not in OS_CONSTRAINTS:
                unsupported = "unsupported os `{}`".format(value)
                break
            constraint_values.append(OS_CONSTRAINTS[value])
            name_parts.append(value)
        elif key == "arch":
            if value not in ARCH_CONSTRAINTS:
                unsupported = "unsupported arch `{}`".format(value)
                break
            constraint_values.append(ARCH_CONSTRAINTS[value])
            name_parts.append(value)
        elif key == "libc":
            if value != ASSUMED_LINUX_LIBC:
                unsupported = "libc `{}` is not selectable; `{}` is assumed on Linux".format(value, ASSUMED_LINUX_LIBC)
                break
            name_parts.append(value)

    if unsupported:
        return struct(
            supported = False,
            reason = unsupported,
            name = "",
            constraint_values = [],
            flag_values = {},
        )

    return struct(
        supported = True,
        reason = "",
        name = "platform__" + "_".join(name_parts) if name_parts else "",
        constraint_values = constraint_values,
        flag_values = flag_values,
    )

def _version_tuple(value):
    """Turn `3.4.30` into `[3, 4, 30]` for comparisons; non-numeric parts sort low."""
    parts = []
    for part in str(value).replace("+", ".").split("."):
        parts.append(int(part) if part.isdigit() else -1)
    return parts

def abi_tags(tags):
    """The normalized ABI tags of a variant, as matched against a toolchain.

    Args:
        tags (dict): The variant's platform tags.

    Returns:
        dict[str, str]: `libgfortran_version` (major only) and `cxxstring_abi`, when present.
    """
    return {key: normalize_tag(key, tags[key]) for key in ABI_TAGS if key in tags}

def abi_suffix(tags):
    """A name suffix identifying a variant's ABI.

    Args:
        tags (dict): The variant's platform tags.

    Returns:
        str: e.g. `libgfortran5_cxx11`, or `any` when the variant has no ABI tags.
    """
    abi = abi_tags(tags)
    parts = []
    for key in _ABI_NAME_ORDER:
        if key in abi:
            parts.append(("libgfortran" if key == "libgfortran_version" else "") + abi[key])
    return "_".join(parts) if parts else "any"

def _preference(variant):
    """Sort key among variants with identical ABI: lowest versions of unmodeled tags first.

    The *last* element after sorting is chosen, so the highest versions win.
    This matches how `Pkg` resolves `libstdcxx_version` and `julia_version`
    against a recent Julia, where the newest compatible build is selected.
    """
    extra = unmodeled_tags(variant["tags"])
    versions = [_version_tuple(extra[key]) for key in sorted(extra.keys())]
    return (-len(extra), versions)

def choose_variants(variants):
    """Pick the variants to offer for every selectable platform.

    Variants differing in ABI tags are all kept, since the ABI is decided at
    analysis time against the toolchain. Variants differing only in unmodeled
    tags collapse to one.

    Args:
        variants (list[dict]): Artifact variants as returned by
            `parse_artifacts_toml`.

    Returns:
        struct: With fields `selected`, a dict mapping a `selection_key` name
            to `struct(key, variants)` where `variants` is the list of
            variants to offer for that platform, and `skipped`, a list of
            `(variant, reason)` tuples.
    """
    groups = {}
    skipped = []
    for variant in variants:
        key = selection_key(variant["tags"])
        if not key.supported:
            skipped.append((variant, key.reason))
            continue
        groups.setdefault(key.name, (key, {}))[1].setdefault(abi_suffix(variant["tags"]), []).append(variant)

    selected = {}
    for name, (key, by_abi) in groups.items():
        kept = []
        for suffix in sorted(by_abi.keys()):
            ordered = sorted(by_abi[suffix], key = _preference)
            chosen = ordered[-1]
            for variant in ordered[:-1]:
                skipped.append((variant, "superseded by a variant with tags {}".format(chosen["tags"])))
            kept.append(chosen)
        selected[name] = struct(key = key, variants = kept)

    return struct(selected = selected, skipped = skipped)

def match_abi(variant_tags, toolchain_abi):
    """Whether a variant's ABI tags are compatible with a toolchain's.

    Follows `Base.BinaryPlatforms.platforms_match`: a tag present on both
    sides must agree, a tag present on one side only matches anything.

    Args:
        variant_tags (dict): The variant's (normalized) ABI tags.
        toolchain_abi (dict): The toolchain's ABI tags.

    Returns:
        bool: Whether they match.
    """
    for key, value in variant_tags.items():
        if key in toolchain_abi and toolchain_abi[key] != value:
            return False
    return True

def select_abi_variant(candidates, toolchain_abi):
    """Pick the variant of one artifact that matches a toolchain's ABI.

    Args:
        candidates (list[struct]): Each with `tags` (normalized ABI tags) and
            an arbitrary `value`.
        toolchain_abi (dict): The toolchain's ABI tags.

    Returns:
        struct|None: The most specific matching candidate, or `None`.
    """
    best = None
    for candidate in candidates:
        if not match_abi(candidate.tags, toolchain_abi):
            continue
        if best == None or len(candidate.tags) > len(best.tags):
            best = candidate
    return best

def config_setting_text(key):
    """Render the `config_setting` for a selection key as BUILD file text.

    Args:
        key (struct): A supported key returned by `selection_key`.

    Returns:
        str: The `config_setting` definition.
    """
    lines = ["config_setting(", "    name = \"{}\",".format(key.name)]
    if key.constraint_values:
        lines.append("    constraint_values = [")
        for value in key.constraint_values:
            lines.append("        \"{}\",".format(value))
        lines.append("    ],")
    if key.flag_values:
        lines.append("    flag_values = {")
        for flag, value in sorted(key.flag_values.items()):
            lines.append("        \"{}\": \"{}\",".format(flag, value))
        lines.append("    },")
    lines.append("    visibility = [\"//visibility:public\"],")
    lines.append(")")
    return "\n".join(lines)
