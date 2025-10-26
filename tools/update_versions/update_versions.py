"""A tool for fetching the integrity values of all known versions of Julia"""

import argparse
import base64
import binascii
import json
import logging
import os
import re
import urllib.request
from pathlib import Path

VERSIONS_JSON_URL = "https://julialang-s3.julialang.org/bin/versions.json"

REQUEST_HEADERS = {"User-Agent": "rules_julia/update_versions"}

# Supported triplets (from toolchain_repo.bzl)
SUPPORTED_TRIPLETS = {
    "aarch64-apple-darwin",
    "aarch64-linux-gnu",
    "i686-linux-gnu",
    "i686-w64-mingw32",
    "powerpc64le-linux-gnu",
    "x86_64-apple-darwin",
    "x86_64-linux-gnu",
    "x86_64-unknown-freebsd",
    "x86_64-w64-mingw32",
}

BUILD_TEMPLATE = """\
\"\"\"Julia Versions

AUTO-GENERATED: DO NOT MODIFY

Update using the following command:

```python
python3 tools/update_versions/update_versions.py
```
\"\"\"

JULIA_VERSIONS = {}
"""


def parse_args() -> argparse.Namespace:
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description=__doc__)

    repo_root = Path(__file__).parent.parent.parent
    if "BUILD_WORKSPACE_DIRECTORY" in os.environ:
        repo_root = Path(os.environ["BUILD_WORKSPACE_DIRECTORY"])

    parser.add_argument(
        "--output",
        type=Path,
        default=repo_root / "julia/private/versions.bzl",
        help="The path to write the versions bzl file to.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose logging",
    )
    parser.add_argument(
        "--min-version",
        type=str,
        default="1.6",
        help="Minimum Julia version to include (default: 1.6)",
    )

    return parser.parse_args()


def download_json(url: str) -> dict:
    """Downloads and parses a JSON file."""
    logging.info("Downloading %s", url)
    req = urllib.request.Request(url, headers=REQUEST_HEADERS)
    with urllib.request.urlopen(req) as response:
        return json.loads(response.read().decode("utf-8"))


def integrity(hex_str: str) -> str:
    """Convert a sha256 hex value to a Bazel integrity value"""

    # Remove any whitespace and convert from hex to raw bytes
    try:
        raw_bytes = binascii.unhexlify(hex_str.strip())
    except binascii.Error as e:
        raise ValueError(f"Invalid hex input: {e}") from e

    # Convert to base64
    encoded = base64.b64encode(raw_bytes).decode("utf-8")
    return f"sha256-{encoded}"


def version_tuple(version_str: str) -> tuple[int, ...]:
    """Convert version string to tuple for comparison"""
    parts = []
    for part in version_str.split('.'):
        try:
            parts.append(int(part))
        except ValueError:
            # Handle version strings like "1.6.0-rc1"
            parts.append(0)
    return tuple(parts)


def normalize_triplet(triplet: str) -> str | None:
    """
    Normalize a triplet by removing version suffixes.

    Examples:
        x86_64-apple-darwin14 -> x86_64-apple-darwin
        aarch64-apple-darwin20 -> aarch64-apple-darwin
        x86_64-unknown-freebsd11.1 -> x86_64-unknown-freebsd

    Returns the normalized triplet if it's supported, None otherwise.
    """
    # Remove version numbers from darwin and freebsd triplets
    # Match patterns like darwin14, darwin20, freebsd11.1, etc.
    normalized = re.sub(r'(darwin|freebsd)\d+(\.\d+)?$', r'\1', triplet)

    # Check if it's in our supported list
    if normalized in SUPPORTED_TRIPLETS:
        return normalized

    return None


def main() -> None:
    """The main entrypoint."""

    args = parse_args()

    if args.verbose:
        logging.basicConfig(level=logging.DEBUG)
    else:
        logging.basicConfig(level=logging.INFO)

    min_version = version_tuple(args.min_version)

    # Download the versions.json file
    versions_data = download_json(VERSIONS_JSON_URL)

    output = {}

    for version_str, version_info in versions_data.items():
        # Skip if not stable
        if not version_info.get("stable", False):
            logging.debug("Skipping non-stable version %s", version_str)
            continue

        # Skip if below minimum version
        try:
            if version_tuple(version_str) < min_version:
                logging.debug("Skipping version %s (below minimum)", version_str)
                continue
        except (ValueError, IndexError):
            logging.debug("Skipping invalid version: %s", version_str)
            continue

        files = version_info.get("files", [])
        if not files:
            logging.debug("No files for version %s", version_str)
            continue

        logging.info("Processing version %s", version_str)
        output[version_str] = {}

        for file_info in files:
            triplet = file_info.get("triplet")
            url = file_info.get("url")
            sha256_hex = file_info.get("sha256")

            if not triplet or not url or not sha256_hex:
                logging.debug("Missing data for file: %s", file_info)
                continue

            # Normalize and filter triplet
            normalized_triplet = normalize_triplet(triplet)
            if not normalized_triplet:
                logging.debug("Skipping unsupported triplet: %s", triplet)
                continue

            try:
                integrity_value = integrity(sha256_hex)

                output[version_str][normalized_triplet] = {
                    "url": url,
                    "integrity": integrity_value,
                }
                logging.debug("  %s: %s", normalized_triplet, url)
            except Exception as e:
                logging.warning("Failed to get checksum for %s %s: %s", version_str, normalized_triplet, e)
                continue

    # Remove versions with no platforms
    output = {k: v for k, v in output.items() if v}

    # Sort versions
    sorted_output = dict(sorted(output.items(), key=lambda x: version_tuple(x[0])))

    logging.debug("Writing to %s", args.output)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(BUILD_TEMPLATE.format(json.dumps(sorted_output, indent=4)))
    logging.info("Done - wrote %d versions", len(sorted_output))


if __name__ == "__main__":
    main()
