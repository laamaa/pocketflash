"""The complete source and package snapshot used by a PocketFlash build."""

import hashlib


def source_hashes(root):
    return {
        str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
        for folder in (root / "src", root / "pkg")
        for path in sorted(folder.rglob("*"))
        if path.is_file()
    }
