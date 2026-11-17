"""Fill in an entitlements file's $(VAR) references from xcodebuild's settings.

Usage: render-entitlements.py <BUILD_SETTINGS_JSON> <ENTITLEMENTS> <OUTPUT>

BUILD_SETTINGS_JSON is the output of `xcodebuild -showBuildSettings -json`; the
first target's settings are used. $(AppIdentifierPrefix) is the team followed by
a dot, as Xcode signs it. Fails on a reference it cannot fill.
"""
import json
import re
import sys


def main():
    settings_path, source, output = sys.argv[1:4]
    with open(settings_path) as f:
        settings = json.load(f)[0]["buildSettings"]
    settings.setdefault("AppIdentifierPrefix", settings["DEVELOPMENT_TEAM"] + ".")

    def fill(match):
        name = match.group(1)
        if name not in settings:
            sys.exit(f"{source}: no build setting {name}")
        return settings[name]

    with open(source) as f:
        text = f.read()
    for _ in range(5):  # settings may refer to other settings
        text, count = re.subn(r"\$\((\w+)\)", fill, text)
        if count == 0:
            break
    with open(output, "w") as f:
        f.write(text)


if __name__ == "__main__":
    main()
