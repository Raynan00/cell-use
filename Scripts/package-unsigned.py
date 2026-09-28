#!/usr/bin/env python3
"""Package a compiled .app preserving modes. This is not a signed installable IPA."""
import stat
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
app = root / ".build/DerivedData/Build/Products/Debug-iphoneos/CellUseDemo.app"
if not app.is_dir() or not (app / "CellUseDemo").is_file():
    raise SystemExit("Compiled CellUseDemo.app not found; run the macOS build first.")
output = root / ".build/cell-use-demo-unsigned.ipa"
with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(app.rglob("*")):
        name = "Payload/CellUseDemo.app/" + path.relative_to(app).as_posix()
        if path.is_symlink():
            info = zipfile.ZipInfo(name)
            info.create_system = 3
            info.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(info, str(path.readlink()))
        elif path.is_file():
            archive.write(path, name)
print(f"Unsigned archive created: {output.name}. Signing and developer-image readiness are separate steps.")
