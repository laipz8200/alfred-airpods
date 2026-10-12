#!/usr/bin/env python3
"""Build and package the Alfred workflow using macOS, Python 3, and Xcode CLI tools."""

import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / "workflow"
DIST = ROOT / "dist"


def check_workflow():
    metadata = plistlib.loads((WORKFLOW / "info.plist").read_bytes())
    configuration = {item["variable"]: item for item in metadata["userconfigurationconfig"]}
    assert configuration["keyword"]["config"]["default"] == "airpods"
    assert configuration["device"]["config"]["default"] == ""
    objects = metadata["objects"]
    filters = [obj for obj in objects if obj["type"] == "alfred.workflow.input.scriptfilter"]
    actions = [obj for obj in objects if obj["type"] == "alfred.workflow.action.script"]
    notifications = [obj for obj in objects if obj["type"] == "alfred.workflow.output.notification"]
    assert len(filters) == len(actions) == len(notifications) == 1
    script_filter, action, notification = filters[0], actions[0], notifications[0]
    assert script_filter["config"]["keyword"] == "{var:keyword}"
    assert script_filter["config"]["argumenttype"] == 1
    assert script_filter["config"]["alfredfiltersresults"] is False
    for obj, script in [(script_filter, 'exec ./airpods menu "${1:-}"'), (action, './airpods action "${1:-}"\nexit 0')]:
        assert obj["config"]["scriptargtype"] == 1
        assert obj["config"]["script"] == script
    assert metadata["connections"][script_filter["uid"]][0]["destinationuid"] == action["uid"]
    assert metadata["connections"][action["uid"]][0]["destinationuid"] == notification["uid"]
    assert notification["config"]["text"] == "{query}"
    assert (ROOT / "LICENSE").read_text().startswith("MIT License")
    metadata["readme"] = (ROOT / "README.md").read_text()
    print("Workflow metadata and argv wiring checks passed.")
    return metadata


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    metadata = check_workflow()
    if sys.argv[1:] == ["--check"]:
        return
    if sys.argv[1:]:
        raise SystemExit("Usage: python3 scripts/build.py [--check]")
    sources = sorted(WORKFLOW.glob("*.swift"))
    assert sources, "No Swift sources found."
    sdk = run("xcrun", "--sdk", "macosx", "--show-sdk-path")
    helper = WORKFLOW / "airpods"
    with tempfile.TemporaryDirectory(prefix="airpods-build-") as directory:
        binaries = []
        for architecture in ("arm64", "x86_64"):
            binary = Path(directory) / architecture
            subprocess.run([
                "xcrun", "swiftc", "-O", "-whole-module-optimization", "-parse-as-library",
                "-sdk", sdk, "-target", f"{architecture}-apple-macos13.0",
                *map(str, sources), "-o", str(binary),
            ], check=True)
            binaries.append(str(binary))
        subprocess.run(["lipo", "-create", *binaries, "-output", str(helper)], check=True)
    helper.chmod(0o755)
    subprocess.run(["codesign", "--force", "--sign", "-", str(helper)], check=True)
    assert {"arm64", "x86_64"} <= set(run("lipo", "-archs", str(helper)).split())
    subprocess.run([str(helper), "--self-test"], check=True)
    build_info = {
        "version": metadata["version"], "minimum_macos": "13.0",
        "architectures": ["arm64", "x86_64"],
        "compiler": run("xcrun", "swiftc", "--version").splitlines()[0],
        "checks": ["workflow metadata and argv wiring", "universal architectures", "native helper self-test"],
    }
    DIST.mkdir(exist_ok=True)
    with zipfile.ZipFile(DIST / "AirPods.alfredworkflow", "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("info.plist", plistlib.dumps(metadata, sort_keys=False))
        for name in ["airpods", "icon.png"]:
            archive.write(WORKFLOW / name, name)
        for name in ["README.md", "LICENSE"]:
            archive.write(ROOT / name, name)
        archive.writestr("BUILD-INFO.json", json.dumps(build_info, indent=2) + "\n")
    with zipfile.ZipFile(DIST / "AirPods-source.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        paths = [ROOT / name for name in ["README.md", "LICENSE", ".gitignore"]]
        paths += sources + [WORKFLOW / "info.plist", WORKFLOW / "icon.png"]
        paths += sorted((ROOT / "scripts").glob("*.py")) + sorted((ROOT / "scripts").glob("*.swift"))
        paths += sorted((ROOT / ".github" / "workflows").glob("*.yml"))
        for path in paths:
            archive.write(path, str(Path("alfred-airpods") / path.relative_to(ROOT)))
    with zipfile.ZipFile(DIST / "AirPods.alfredworkflow") as archive:
        assert archive.testzip() is None
        assert (archive.getinfo("airpods").external_attr >> 16) & 0o111
        assert plistlib.loads(archive.read("info.plist"))["name"] == "AirPods"
    print(f"Created {DIST / 'AirPods.alfredworkflow'}")
    print(f"Created {DIST / 'AirPods-source.zip'}")


if __name__ == "__main__":
    main()
