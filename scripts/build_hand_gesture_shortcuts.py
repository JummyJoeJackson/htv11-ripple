#!/usr/bin/env python3
"""Build four one-action Watch shortcuts without importing or running them.

Bundle identifiers are part of an App Intent action's identity, so pass the
identifier of the Watch app that will actually be installed. Personal signing
values belong in command arguments, not in the repository.
"""

from __future__ import annotations

import argparse
import ctypes
import json
import pathlib
import platform
import plistlib
import re
import subprocess
import sys
import uuid

GESTURES = (
    ("Ripple Pinch", "RipplePinchIntent"),
    ("Ripple Clench", "RippleClenchIntent"),
    ("Ripple Double Pinch", "RippleDoublePinchIntent"),
    ("Ripple Double Clench", "RippleDoubleClenchIntent"),
)


def build_source(name: str, intent: str, bundle: str, team: str | None) -> dict:
    descriptor = {
        "AppIntentIdentifier": intent,
        "BundleIdentifier": bundle,
        "Name": "Ripple",
    }
    if team:
        descriptor["TeamIdentifier"] = team
    return {
        "WFWorkflowName": name,
        "WFWorkflowClientVersion": "2600.0.0",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {
            "WFWorkflowIconStartColor": 463140863,
            "WFWorkflowIconGlyphNumber": 59511,
        },
        "WFWorkflowInputContentItemClasses": [],
        "WFWorkflowOutputContentItemClasses": [],
        "WFWorkflowHasShortcutInputVariables": False,
        "WFWorkflowHasOutputFallback": False,
        "WFWorkflowImportQuestions": [],
        "WFWorkflowTypes": ["WatchKit"],
        "WFQuickActionSurfaces": [],
        "WFWorkflowActions": [
            {
                "WFWorkflowActionIdentifier": f"{bundle}.{intent}",
                "WFWorkflowActionParameters": {
                    "AppIntentDescriptor": descriptor,
                    "ShowWhenRun": False,
                    "OpenWhenRun": False,
                    "UUID": str(uuid.uuid5(uuid.NAMESPACE_URL, f"ripple:{bundle}:{intent}" )).upper(),
                },
            }
        ],
    }


def validate_source(source: dict, name: str, intent: str, bundle: str, team: str | None) -> None:
    """Allow only the exact one-action input workflow we generate."""
    expected = build_source(name, intent, bundle, team)
    if source != expected:
        raise ValueError(f"{name}: shortcut differs from the gesture-input allowlist")
    if source["WFWorkflowTypes"] != ["WatchKit"]:
        raise ValueError(f"{name}: missing Show on Apple Watch flag")
    actions = source["WFWorkflowActions"]
    if len(actions) != 1 or actions[0]["WFWorkflowActionIdentifier"] != f"{bundle}.{intent}":
        raise ValueError(f"{name}: unexpected executable action")


class NativeParser:
    """Read-only validation with Apple's installed macOS Shortcuts parser.

    This development helper uses private macOS APIs only to read generated
    files. It is never shipped in the app and never invokes any shortcut.
    Uninstalled Watch actions are expected to be placeholders on a Mac.
    """

    def __init__(self) -> None:
        if platform.system() != "Darwin":
            raise RuntimeError("--validate-native requires macOS")
        self.pointer = ctypes.c_void_p
        self.objc = ctypes.CDLL("/usr/lib/libobjc.A.dylib")
        self.libraries = [
            ctypes.CDLL(path)
            for path in (
                "/System/Library/Frameworks/Foundation.framework/Foundation",
                "/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit",
                "/System/Library/PrivateFrameworks/ActionKit.framework/ActionKit",
            )
        ]
        self.objc.objc_getClass.argtypes = [ctypes.c_char_p]
        self.objc.objc_getClass.restype = self.pointer
        self.objc.sel_registerName.argtypes = [ctypes.c_char_p]
        self.objc.sel_registerName.restype = self.pointer
        self.objc.object_getClass.argtypes = [self.pointer]
        self.objc.object_getClass.restype = self.pointer
        self.objc.class_getName.argtypes = [self.pointer]
        self.objc.class_getName.restype = ctypes.c_char_p
        self.send_address = ctypes.cast(self.objc.objc_msgSend, self.pointer).value
        self.pool = self.message(self.message(self.cls("NSAutoreleasePool"), "alloc"), "init")
        self.registry = self.message(self.cls("WFActionRegistry"), "sharedRegistry")
        self.provider = self.message(self.message(self.cls("WFLinkActionProvider"), "alloc"), "init")
        if not self.registry or not self.provider:
            raise RuntimeError("Installed Shortcuts parser is unavailable")

    def cls(self, name: str):
        return self.objc.objc_getClass(name.encode())

    def message(self, obj, selector: str, *args, result=None):
        result = result or self.pointer
        call = ctypes.CFUNCTYPE(result, self.pointer, self.pointer, *([self.pointer] * len(args)))(self.send_address)
        return call(obj, self.objc.sel_registerName(selector.encode()), *args)

    def string(self, value: str):
        encoded = ctypes.c_char_p(value.encode())
        return self.message(self.cls("NSString"), "stringWithUTF8String:", ctypes.cast(encoded, self.pointer))

    def native(self, value):
        data = self.message(self.string(json.dumps(value)), "dataUsingEncoding:", 4)
        return self.message(self.cls("NSJSONSerialization"), "JSONObjectWithData:options:error:", data, 0, None)

    def python(self, value):
        if not value:
            return None
        array = self.message(self.cls("NSArray"), "arrayWithObject:", value)
        data = self.message(self.cls("NSJSONSerialization"), "dataWithJSONObject:options:error:", array, 0, None)
        if not data:
            raise RuntimeError("Native parser returned a non-JSON representation")
        raw = ctypes.string_at(self.message(data, "bytes"), self.message(data, "length", result=ctypes.c_ulong))
        return json.loads(raw)[0]

    def validate(self, source: dict) -> dict:
        action_source = source["WFWorkflowActions"][0]
        descriptor = action_source["WFWorkflowActionParameters"]["AppIntentDescriptor"]
        descriptor_valid = self.message(
            self.provider, "serializedAppIntentDescriptorIsValid:", self.native(descriptor), result=ctypes.c_bool
        )
        if not descriptor_valid:
            raise ValueError("Apple's parser rejected the App Intent descriptor")
        action = self.message(
            self.cls("WFAction"), "actionFromSerializedRepresentation:actionRegistry:", self.native(action_source), self.registry
        )
        if not action or self.python(self.message(action, "serializedRepresentation")) != action_source:
            raise ValueError("Apple's parser did not preserve the gesture action")
        workflow = self.message(
            self.message(self.cls("WFWorkflowFile"), "alloc"), "initWithDictionary:name:performMigration:",
            self.native(source), self.string(source["WFWorkflowName"]), 0,
        )
        if not workflow or self.message(self.message(workflow, "actions"), "count", result=ctypes.c_ulong) != 1:
            raise ValueError("Apple's parser rejected the one-action workflow")
        if self.python(self.message(workflow, "name")) != source["WFWorkflowName"]:
            raise ValueError("Apple's parser changed the workflow name")
        action_class = self.objc.class_getName(self.objc.object_getClass(action)).decode()
        return {
            "descriptorValid": True,
            "actionRoundTripPreserved": True,
            "workflowActionCount": 1,
            "actionClassOnMac": action_class,
            "isMissingOnMac": bool(self.message(action, "isMissing", result=ctypes.c_bool)),
            "runtimeVerifiedOnWatch": False,
        }


def readme(bundle: str, signed: bool, native: bool) -> str:
    file_kind = ".shortcut" if signed else ".unsigned.shortcut (not signed for import)"
    return f"""# Ripple hand-gesture shortcuts

These four files each send one gesture input to the installed Ripple Watch
app. Ripple matches the selected preset and only dismisses an active check-in
when the entire sequence matches. They contain no messaging, Open App, Show
Alert, Run Shortcut, URL, or network actions.

Target Watch bundle: `{bundle}`
Import files: `{file_kind}`

| AssistiveTouch gesture | Shortcut |
| --- | --- |
| Pinch (Tap on watchOS 26) | Ripple Pinch |
| Clench | Ripple Clench |
| Double pinch (Double Tap on watchOS 26) | Ripple Double Pinch |
| Double clench | Ripple Double Clench |

Install the matching new Ripple Watch build before importing these shortcuts.
Transfer the signed files to the iPhone and add them in Shortcuts. Confirm each
shortcut's Show on Apple Watch setting. In the Watch app on iPhone, go to
Accessibility → AssistiveTouch → Hand Gestures, then assign each gesture to its
matching Siri shortcut. These assignments apply systemwide. Apple disables
native double tap when AssistiveTouch is on. If necessary, set the separate
AssistiveTouch activation gesture to None so double clench is available as an
input instead of being consumed to activate AssistiveTouch.

In Ripple on iPhone, enable hand gestures and select one of the ten presets.
Keep Ripple visible on Watch while testing. For a two-step preset, allow each
individual shortcut to finish before the next input and keep the inputs within
Ripple's sequence timeout. Do not assign the existing Ripple Alert messaging
shortcut; these four input shortcuts are separate.

Each `.source.json` is human-readable. Each `.unsigned.shortcut` is its binary
property-list representation. Signed `.shortcut` files are generated only with
`--sign`. `validation.json` records structural and optional native-parser checks.

Structural allowlist: passed for all four files.
Apple native-parser checks requested: {str(native).lower()}.
Apple signing requested: {str(signed).lower()}.

A missing-action placeholder on macOS is expected because the Watch app is not
installed on the Mac. Native parsing and signing do not verify Watch execution,
shortcut syncing, consecutive gesture delivery, or whether Ripple stays visible.
Those require the paired physical devices. Nothing was imported or executed by
the generator.

The files are bound to this Watch bundle. Regenerate them if the installed
bundle changes. See `scripts/build_hand_gesture_shortcuts.py --help` in the
repository. Personal signing identifiers need not be committed.
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-id", required=True, help="Bundle identifier of the installed Ripple Watch app")
    parser.add_argument("--output-dir", required=True, type=pathlib.Path, help="Folder for the four shortcuts and validation report")
    parser.add_argument("--team-id", help="Optional signing team identifier for AppIntentDescriptor; kept in generated output only")
    parser.add_argument("--sign", action="store_true", help="Sign all four with macOS shortcuts sign --mode anyone; does not import or run them")
    parser.add_argument("--validate-native", action="store_true", help="Read generated workflows with Apple's native macOS parser; does not run actions")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*", args.bundle_id) or "." not in args.bundle_id:
        parser.error("--bundle-id must be a reverse-DNS bundle identifier")
    if args.team_id and not re.fullmatch(r"[A-Z0-9]{10}", args.team_id):
        parser.error("--team-id must have ten uppercase letters or digits")
    if args.sign and platform.system() != "Darwin":
        parser.error("--sign requires macOS")
    native_parser = NativeParser() if args.validate_native else None
    output = args.output_dir.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    report = {"watchBundleIdentifier": args.bundle_id, "runtimeVerifiedOnWatch": False, "shortcuts": []}
    for name, intent in GESTURES:
        source = build_source(name, intent, args.bundle_id, args.team_id)
        validate_source(source, name, intent, args.bundle_id, args.team_id)
        unsigned = output / f"{name}.unsigned.shortcut"
        unsigned.write_bytes(plistlib.dumps(source, fmt=plistlib.FMT_BINARY, sort_keys=False))
        validate_source(plistlib.loads(unsigned.read_bytes()), name, intent, args.bundle_id, args.team_id)
        (output / f"{name}.source.json").write_text(json.dumps(source, indent=2) + "\n", encoding="utf-8")
        checked = {"name": name, "intent": intent, "structuralAllowlistPassed": True, "signed": False}
        if native_parser:
            checked["nativeParser"] = native_parser.validate(source)
        if args.sign:
            signed = output / f"{name}.shortcut"
            result = subprocess.run(
                ["/usr/bin/shortcuts", "sign", "--mode", "anyone", "--input", str(unsigned), "--output", str(signed)],
                capture_output=True, text=True, check=False,
            )
            if result.returncode != 0 or not signed.is_file() or signed.stat().st_size == 0:
                raise RuntimeError(f"Signing {name} failed: {result.stderr.strip() or result.stdout.strip()}")
            checked["signed"] = True
            checked["signedFileBytes"] = signed.stat().st_size
        report["shortcuts"].append(checked)
        print(f"Created {name}" + (" (signed)" if args.sign else " (unsigned)"))
    (output / "validation.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    (output / "README.md").write_text(readme(args.bundle_id, args.sign, args.validate_native), encoding="utf-8")
    print(f"Output: {output}")
    print("No shortcuts were imported or executed. Watch runtime validation remains pending.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError) as error:
        print(f"Error: {error}", file=sys.stderr)
        raise SystemExit(1)
