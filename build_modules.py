"""
Build script to generate wrapped shell modules.

This script reads the shell modules and wrapper.sh, then creates wrapped
versions that combine them. The wrapped modules are what get included in
the collection distribution.
"""

from __future__ import annotations

import shutil
from pathlib import Path


def build_wrapped_modules():
    """Generate wrapped shell modules for the collection."""

    # Paths
    project_root = Path(__file__).parent
    source_modules_dir = project_root / "source_modules"
    wrapper_path = project_root / "build_templates" / "wrapper.sh"
    modules_dir = project_root / "plugins" / "modules"

    # Read the wrapper
    print(f"Reading wrapper from: {wrapper_path}")
    with open(wrapper_path, "r") as f:
        wrapper_content = f.read()

    # Create modules directory
    modules_dir.mkdir(parents=True, exist_ok=True)

    # Find all shell modules in source
    shell_modules = list(source_modules_dir.glob("*.sh"))
    print(f"Found {len(shell_modules)} shell modules to wrap")

    # Wrap each module
    for module_path in shell_modules:
        print(f"  Wrapping {module_path.name}...")

        # Read the module
        with open(module_path, "r") as f:
            module_content = f.read()

        # Inject the module into the wrapper at the `. "$_script"` line
        wrapped_content = wrapper_content.replace(
            '\n. "$_script"\n', "\n" + module_content + "\n"
        )

        # Write the wrapped module to plugins/modules
        output_path = modules_dir / module_path.name
        with open(output_path, "w") as f:
            f.write(wrapped_content)

        print(f"    Created: {output_path}")

    # Copy YAML modules from source as-is
    other_files = (
        list(source_modules_dir.glob("*.yml"))
        + list(source_modules_dir.glob("*.yaml"))
        + list(source_modules_dir.glob("*.md"))
    )
    print(f"\nCopying {len(other_files)} other files...")
    for module_path in other_files:
        output_path = modules_dir / module_path.name
        shutil.copy2(module_path, output_path)
        print(f"  Copied: {module_path.name}")

    print(f"\nBuild complete! Wrapped modules are in: {modules_dir}")
    print("\nThe wrapped modules can now be used directly by the collection.")
    print("Run 'ansible-galaxy collection build' to create the collection artifact.")


if __name__ == "__main__":
    build_wrapped_modules()
