"""Shared runfiles location utility."""

def rlocationpath(file, workspace_name):
    """Convert a file to its runfiles location path.

    Args:
        file: A File object.
        workspace_name: The workspace name.

    Returns:
        str: The runfiles location path for the file.
    """
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]
    return "{}/{}".format(workspace_name, file.short_path)
