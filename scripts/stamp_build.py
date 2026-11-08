import os
import plistlib
from pathlib import Path

path = Path("BuildSupport/DarkReader-Info.plist")
with path.open("rb") as file:
    info = plistlib.load(file)
info["ReaderSourceCommit"] = os.environ.get("GITHUB_SHA", "local")
if os.environ.get("GITHUB_RUN_NUMBER"):
    info["CFBundleVersion"] = os.environ["GITHUB_RUN_NUMBER"]
with path.open("wb") as file:
    plistlib.dump(info, file)
