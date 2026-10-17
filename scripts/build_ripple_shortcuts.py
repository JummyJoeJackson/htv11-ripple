#!/usr/bin/env python3
"""Build the two iPhone shortcuts Ripple's messaging needs, without running them.

Ripple Alert   Ripple opens shortcuts://x-callback-url/run-shortcut with JSON
               {"messages":[{"to":"+1416…","text":"…"}]}. The shortcut sends
               each text to its own recipient with Send Message (Show When Run
               off), so nobody is in a group text.

Ripple Accept  A Messages automation ("Message contains Ripple accept") runs it
               with the incoming message. It opens ripple://accept?text=<reply>,
               and Ripple counts "RIPPLE ACCEPT 4821" like a tap on the link.

Both only use built-in Shortcuts actions and Ripple's URL scheme, so unlike
the hand-gesture wrappers they work with any Ripple bundle identifier.

iOS imports only signed shortcut files. `--sign` signs them with Apple's
`shortcuts sign` on a Mac; without it the generator writes unsigned files for
inspection. `--validate-native` reads every action back with the Mac's own
Shortcuts parser.
"""

from __future__ import annotations

import argparse
import ctypes
import json
import pathlib
import platform
import plistlib
import subprocess
import sys
import uuid

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT = ROOT / "shortcuts"

# What Shortcuts writes for a shortcut that accepts any input. The Messages
# automation passes the message; the URL scheme passes text.
ANY_INPUT = [
    "WFAppContentItem", "WFAppStoreAppContentItem", "WFArticleContentItem", "WFContactContentItem",
    "WFDateContentItem", "WFEmailAddressContentItem", "WFFolderContentItem", "WFGenericFileContentItem",
    "WFImageContentItem", "WFiTunesProductContentItem", "WFLocationContentItem", "WFDCMapsLinkContentItem",
    "WFAVAssetContentItem", "WFPDFContentItem", "WFPhoneNumberContentItem", "WFRichTextContentItem",
    "WFSafariWebPageContentItem", "WFStringContentItem", "WFURLContentItem",
]


def stable_uuid(name: str) -> str:
    """Fixed identifiers, so regenerating gives byte-identical files."""
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"ripple-shortcut:{name}")).upper()


def attachment(value: dict) -> dict:
    """A parameter set to one whole variable."""
    return {"Value": value, "WFSerializationType": "WFTextTokenAttachment"}


def token_string(*parts) -> dict:
    """Text with variables inside it. Variables sit at U+FFFC placeholders,
    keyed by their UTF-16 position."""
    text, attachments = "", {}
    for part in parts:
        if isinstance(part, str):
            text += part
        else:
            location = len(text.encode("utf-16-le")) // 2
            attachments[f"{{{location}, 1}}"] = part
            text += "￼"
    return {"Value": {"string": text, "attachmentsByRange": attachments}, "WFSerializationType": "WFTextTokenString"}


SHORTCUT_INPUT = {"Type": "ExtensionInput"}


def output(action_uuid: str, name: str) -> dict:
    return {"OutputUUID": action_uuid, "Type": "ActionOutput", "OutputName": name}


def variable(name: str) -> dict:
    return {"Type": "Variable", "VariableName": name}


def action(identifier: str, action_uuid: str, **parameters) -> dict:
    return {"WFWorkflowActionIdentifier": identifier, "WFWorkflowActionParameters": {"UUID": action_uuid, **parameters}}


def workflow(name: str, actions: list[dict], glyph: int, color: int) -> dict:
    return {
        "WFWorkflowName": name,
        "WFWorkflowClientVersion": "2600.0.0",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {"WFWorkflowIconStartColor": color, "WFWorkflowIconGlyphNumber": glyph},
        "WFWorkflowInputContentItemClasses": ANY_INPUT,
        "WFWorkflowOutputContentItemClasses": [],
        "WFWorkflowHasShortcutInputVariables": True,
        "WFWorkflowHasOutputFallback": False,
        "WFWorkflowImportQuestions": [],
        "WFWorkflowTypes": [],
        "WFQuickActionSurfaces": [],
        "WFWorkflowActions": actions,
    }


def ripple_alert() -> dict:
    ids = {key: stable_uuid(f"alert:{key}") for key in ("dictionary", "messages", "repeat", "to", "text", "send", "end")}
    group = stable_uuid("alert:repeat-group")

    def value_for(key: str, action_uuid: str, source: dict) -> dict:
        return action(
            "is.workflow.actions.getvalueforkey", action_uuid,
            WFDictionaryKey=key, WFGetDictionaryValueType="Value", WFInput=attachment(source),
        )

    actions = [
        # {"messages":[{"to":…,"text":…}]} → Dictionary
        action("is.workflow.actions.detect.dictionary", ids["dictionary"], WFInput=attachment(SHORTCUT_INPUT)),
        value_for("messages", ids["messages"], output(ids["dictionary"], "Dictionary")),
        action(
            "is.workflow.actions.repeat.each", ids["repeat"],
            GroupingIdentifier=group, WFControlFlowMode=0,
            WFInput=attachment(output(ids["messages"], "Dictionary Value")),
        ),
        value_for("to", ids["to"], variable("Repeat Item")),
        value_for("text", ids["text"], variable("Repeat Item")),
        # One recipient per Send Message, so nobody is in a group text.
        action(
            "is.workflow.actions.sendmessage", ids["send"],
            WFSendMessageContent=token_string(output(ids["text"], "Dictionary Value")),
            WFSendMessageActionRecipients=attachment(output(ids["to"], "Dictionary Value")),
            ShowWhenRun=False,
        ),
        action("is.workflow.actions.repeat.each", ids["end"], GroupingIdentifier=group, WFControlFlowMode=2),
    ]
    return workflow("Ripple Alert", actions, glyph=59511, color=463140863)


def ripple_accept() -> dict:
    ids = {key: stable_uuid(f"accept:{key}") for key in ("encode", "url", "open")}
    actions = [
        # The message from the automation, as text, made safe for a URL.
        action("is.workflow.actions.urlencode", ids["encode"], WFEncodeMode="Encode", WFInput=token_string(SHORTCUT_INPUT)),
        action(
            "is.workflow.actions.gettext", ids["url"],
            WFTextActionText=token_string("ripple://accept?text=", output(ids["encode"], "URL Encoded Text")),
        ),
        # Opens Ripple, which checks the code against the open alert.
        action("is.workflow.actions.openurl", ids["open"], WFInput=attachment(output(ids["url"], "Text")), **{"Show-WFInput": True}),
    ]
    return workflow("Ripple Accept", actions, glyph=59511, color=463140863)


SHORTCUTS = (ripple_alert, ripple_accept)

ALLOWED_ACTIONS = {
    "Ripple Alert": [
        "is.workflow.actions.detect.dictionary", "is.workflow.actions.getvalueforkey", "is.workflow.actions.repeat.each",
        "is.workflow.actions.getvalueforkey", "is.workflow.actions.getvalueforkey", "is.workflow.actions.sendmessage",
        "is.workflow.actions.repeat.each",
    ],
    "Ripple Accept": ["is.workflow.actions.urlencode", "is.workflow.actions.gettext", "is.workflow.actions.openurl"],
}


def validate_source(source: dict) -> None:
    """Only the exact actions above: no network, no other apps, no deletes."""
    name = source["WFWorkflowName"]
    identifiers = [a["WFWorkflowActionIdentifier"] for a in source["WFWorkflowActions"]]
    if identifiers != ALLOWED_ACTIONS[name]:
        raise ValueError(f"{name}: unexpected actions {identifiers}")
    for item in source["WFWorkflowActions"]:
        parameters = item["WFWorkflowActionParameters"]
        if item["WFWorkflowActionIdentifier"] == "is.workflow.actions.sendmessage" and parameters.get("ShowWhenRun") is not False:
            raise ValueError(f"{name}: Send Message must not show the composer")
        if item["WFWorkflowActionIdentifier"] == "is.workflow.actions.gettext":
            if not parameters["WFTextActionText"]["Value"]["string"].startswith("ripple://accept?text="):
                raise ValueError(f"{name}: may only open Ripple's accept link")


def native_checks(parser, source: dict) -> list[dict]:
    """Read each action back with Apple's parser and make sure no parameter is
    dropped, then load the whole workflow. Nothing is run."""
    results = []
    for item in source["WFWorkflowActions"]:
        identifier = item["WFWorkflowActionIdentifier"]
        native = parser.message(
            parser.cls("WFAction"), "actionFromSerializedRepresentation:actionRegistry:", parser.native(item), parser.registry
        )
        if not native:
            raise ValueError(f"Apple's parser couldn't read {identifier}")
        if parser.message(native, "isMissing", result=ctypes.c_bool):
            raise ValueError(f"{identifier} isn't a Shortcuts action on this Mac")
        back = parser.python(parser.message(native, "serializedRepresentation")) or {}
        kept = back.get("WFWorkflowActionParameters", {})
        dropped = sorted(key for key in item["WFWorkflowActionParameters"] if key not in kept)
        if dropped:
            raise ValueError(f"Apple's parser dropped {dropped} from {identifier}")
        results.append({"identifier": identifier, "parametersKept": True})
    loaded = parser.message(
        parser.message(parser.cls("WFWorkflowFile"), "alloc"), "initWithDictionary:name:performMigration:",
        parser.native(source), parser.string(source["WFWorkflowName"]), 0,
    )
    count = parser.message(parser.message(loaded, "actions"), "count", result=ctypes.c_ulong) if loaded else 0
    if count != len(source["WFWorkflowActions"]):
        raise ValueError(f"Apple's parser loaded {count} of {len(source['WFWorkflowActions'])} actions")
    return results


def readme(signed: bool) -> str:
    files = "`Ripple Alert.shortcut` and `Ripple Accept.shortcut`" if signed else "the `.unsigned.shortcut` files (sign them first)"
    return f"""# Ripple messaging shortcuts

Generated by `scripts/build_ripple_shortcuts.py`. Import {files} on the
wearer's iPhone. iOS only imports signed shortcut files; sign on a Mac with:

```bash
python3 scripts/build_ripple_shortcuts.py --sign
```

| Shortcut | What runs it | What it does |
| --- | --- | --- |
| Ripple Alert | Ripple, through the Shortcuts URL scheme | Sends each alert text to its own recipient with Send Message, Show When Run off |
| Ripple Accept | A Messages automation: Message contains "Ripple accept", Run Immediately | Opens `ripple://accept?text=<the reply>`; Ripple checks the code and marks that person as responding |

## Set up on the wearer's iPhone

1. AirDrop both signed files to the iPhone and tap **Add Shortcut** for each. Keep their names.
2. In Ripple, open **Settings → Messaging shortcuts** and send a test message. Approve anything Shortcuts asks for.
3. In Shortcuts, open **Automation**, tap **+**, choose **Message**, set **Message Contains** to `Ripple accept`, choose **Run Immediately**, tap **Next**, and pick **Ripple Accept**.

Alert texts end with "or reply RIPPLE ACCEPT 4821", with a different code
for each person. Their reply runs the automation, Ripple shows "[Name] is
responding" on the iPhone and Watch, texts the others, and stops Tier 2.

Each `.source.json` is the readable version of its shortcut and
`.unsigned.shortcut` is the same thing as a binary property list. Neither
shortcut uses the network, other apps or Ripple's bundle identifier.
Whether sending and the automation run without prompts still needs checking
on the actual iPhone.
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output-dir", type=pathlib.Path, default=DEFAULT_OUTPUT, help=f"Folder for the shortcuts (default: {DEFAULT_OUTPUT})")
    parser.add_argument("--sign", action="store_true", help="Sign with macOS `shortcuts sign --mode anyone`; nothing is imported or run")
    parser.add_argument("--validate-native", action="store_true", help="Read the actions back with Apple's macOS Shortcuts parser; nothing is run")
    args = parser.parse_args()
    if (args.sign or args.validate_native) and platform.system() != "Darwin":
        parser.error("--sign and --validate-native need macOS")

    native = None
    if args.validate_native:
        sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
        from build_hand_gesture_shortcuts import NativeParser  # Mac-only helper shared with the gesture shortcuts
        native = NativeParser()

    out = args.output_dir.expanduser().resolve()
    out.mkdir(parents=True, exist_ok=True)
    report = {"runtimeVerifiedOnIPhone": False, "shortcuts": []}
    for build in SHORTCUTS:
        source = build()
        validate_source(source)
        name = source["WFWorkflowName"]
        unsigned = out / f"{name}.unsigned.shortcut"
        unsigned.write_bytes(plistlib.dumps(source, fmt=plistlib.FMT_BINARY, sort_keys=False))
        if plistlib.loads(unsigned.read_bytes()) != source:
            raise ValueError(f"{name}: binary property list didn't round-trip")
        (out / f"{name}.source.json").write_text(json.dumps(source, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        entry = {"name": name, "actions": len(source["WFWorkflowActions"]), "allowlistPassed": True, "signed": False}
        if native:
            entry["nativeParser"] = native_checks(native, source)
        if args.sign:
            signed = out / f"{name}.shortcut"
            result = subprocess.run(
                ["/usr/bin/shortcuts", "sign", "--mode", "anyone", "--input", str(unsigned), "--output", str(signed)],
                capture_output=True, text=True, check=False,
            )
            if result.returncode != 0 or not signed.is_file() or signed.stat().st_size == 0:
                raise RuntimeError(f"Signing {name} failed: {result.stderr.strip() or result.stdout.strip()}")
            entry["signed"] = True
        report["shortcuts"].append(entry)
        print(f"Created {name}" + (" (signed)" if args.sign else " (unsigned)"))
    (out / "validation.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    (out / "README.md").write_text(readme(args.sign), encoding="utf-8")
    print(f"Output: {out}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError) as error:
        print(f"Error: {error}", file=sys.stderr)
        raise SystemExit(1)
