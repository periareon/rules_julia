"""Mapping Julia artifact platforms onto Bazel configuration.

Julia describes the platform an artifact was built for with a set of tags
(see `Base.BinaryPlatforms`): `os` and `arch` are always present, Linux
artifacts add `libc`, and packages with Fortran or C++ code add
`libgfortran_version` and `cxxstring_abi`. At run time `Pkg` compares them
with the tags of the running Julia. Tags that only one side defines match
anything.

Under Bazel the choice has to be made at analysis time so only the matching
variant is ever downloaded. `os` and `arch` map onto `@platforms`
constraints. The ABI tags map onto flags under `@rules_julia//julia/settings`
that default to what official Julia binaries are built with. Tags that are
not modeled (`libstdcxx_version`, `julia_version`, GPU tags, ...) cannot be
expressed as a `config_setting`; variants differing only in those are
reduced to one deterministic choice.
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

# Platform tags expressed as `@rules_julia//julia/settings` flags, with the
# values each flag accepts.
FLAG_TAGS = {
    "cxxstring_abi": struct(
        flag = "@rules_julia//julia/settings:cxxstring_abi",
        values = ["cxx03", "cxx11"],
    ),
    "libc": struct(
        flag = "@rules_julia//julia/settings:libc",
        values = ["glibc", "musl"],
    ),
    "libgfortran_version": struct(
        flag = "@rules_julia//julia/settings:libgfortran_version",
        values = ["3", "4", "5"],
    ),
}

# Tags expressed as `@platforms` constraints.
_CONSTRAINT_TAGS = ["os", "arch"]

# Tags that carry no information beyond `arch` for the platforms Julia ships.
_IGNORED_TAGS = ["call_abi"]

# Order of tags in generated names.
_NAME_ORDER = ["os", "arch", "libc", "libgfortran_version", "cxxstring_abi"]

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
        if key not in _CONSTRAINT_TAGS and key not in FLAG_TAGS and key not in _IGNORED_TAGS
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
        else:
            flag = FLAG_TAGS[key]
            if value not in flag.values:
                unsupported = "unsupported {} `{}`".format(key, value)
                break
            flag_values[flag.flag] = value
            name_parts.append(value if key != "libgfortran_version" else "libgfortran" + value)

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

def _preference(variant):
    """Sort key: fewer unmodeled tags first, then lowest versions first.

    The *last* element after sorting is chosen, so among variants with the
    same number of unmodeled tags the highest versions win. This matches how
    `Pkg` resolves `libstdcxx_version` and `julia_version` against a recent
    Julia, where the newest compatible build is selected.
    """
    extra = unmodeled_tags(variant["tags"])
    versions = [_version_tuple(extra[key]) for key in sorted(extra.keys())]
    return (-len(extra), versions)

def choose_variants(variants):
    """Pick the variant to use for every selectable platform.

    Args:
        variants (list[dict]): Artifact variants as returned by
            `parse_artifacts_toml`.

    Returns:
        struct: With fields `selected`, a dict mapping a `selection_key`
            struct (by name) to the chosen variant as `struct(key, variant)`,
            and `skipped`, a list of `(variant, reason)` tuples.
    """
    groups = {}
    skipped = []
    for variant in variants:
        key = selection_key(variant["tags"])
        if not key.supported:
            skipped.append((variant, key.reason))
            continue
        groups.setdefault(key.name, (key, []))[1].append(variant)

    selected = {}
    for name, (key, candidates) in groups.items():
        ordered = sorted(candidates, key = _preference)
        chosen = ordered[-1]
        for variant in ordered[:-1]:
            skipped.append((variant, "superseded by a variant with tags {}".format(chosen["tags"])))
        selected[name] = struct(key = key, variant = chosen)

    return struct(selected = selected, skipped = skipped)

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
