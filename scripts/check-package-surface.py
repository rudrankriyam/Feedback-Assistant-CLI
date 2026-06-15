#!/usr/bin/env python3
"""Verify that xcfb ships only as an executable Swift package product."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    result = subprocess.run(
        ["swift", "package", "dump-package"],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    package = json.loads(result.stdout)
    products = package.get("products", [])

    if package.get("name") != "xcfb":
        print("Package name must be xcfb.")
        return 1
    if len(products) != 1:
        print("xcfb must expose exactly one Swift package product.")
        return 1

    product = products[0]
    if product.get("name") != "xcfb" or "executable" not in product.get("type", {}):
        print("The only Swift package product must be the xcfb executable.")
        return 1

    print("Package surface is executable-only.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
