# Hand gesture dismissal

Ripple supports these ten selectable sequences, in this order:

1. pinch
2. clench
3. double pinch
4. double clench
5. pinch + clench
6. double pinch + clench
7. clench + pinch
8. clench + double pinch
9. double clench + pinch
10. double clench + double pinch

On the iPhone, open **Ripple → Settings → Hand gestures**, turn on **Hand gestures to dismiss**, choose a **Gesture sequence**, and tap **Save**. The existing Watch sync section confirms which configuration version the Watch has received. Hand gestures are off by default, including when an existing installation first loads the new setting. The initial selection is **pinch + clench**.

Only the selected, complete sequence dismisses an active alarm, using Ripple's usual “I'm okay” action. Intermediate inputs do nothing to the alarm. Inputs received without an active alarm update the Watch's receipt display so setup can be checked. The gesture input shortcuts do not send messages or start Help/duress actions themselves. The existing touchscreen and swipe controls keep their existing behavior.

## How the input reaches Ripple

```text
AssistiveTouch recognises a gesture
  → its assigned one-action shortcut runs
  → the matching background Ripple Watch App Intent records the input
  → Ripple checks the selected sequence
  → a complete match answers the current alarm through the paired iPhone
```

Apple supplies four base gestures. A double pinch or double clench is one recognised input, not two separate shortcut executions. Compound presets need two inputs in order, with at most **5 seconds** between them. A wrong input restarts matching if it can begin the selected sequence. A timed-out partial sequence must be entered again. Changing the selection or alarm discards a pending partial sequence.

Ripple's App Intents return without a dialog or request to open an app. The useful background execution and successive gesture delivery still need physical Watch verification; a Mac build cannot establish AssistiveTouch's on-device timing or screen behavior.

## One-time shortcut setup

Install the updated Ripple iPhone and Watch apps before importing the input shortcuts. Send these four signed `.shortcut` files supplied with the build to the iPhone using AirDrop or iCloud Drive, import them into Shortcuts, then enable **Show on Apple Watch** in each shortcut's details:

- `Ripple Pinch.shortcut`
- `Ripple Clench.shortcut`
- `Ripple Double Pinch.shortcut`
- `Ripple Double Clench.shortcut`

Wait for them to sync to the Watch. The wrappers refer directly to Ripple's Watch app; the iPhone's Shortcuts action catalog is not a reliable way to create these Watch-only actions.

| AssistiveTouch input | Shortcut name | Single Ripple action |
| --- | --- | --- |
| pinch (may appear as **Tap**) | Ripple Pinch | Ripple Pinch |
| clench | Ripple Clench | Ripple Clench |
| double pinch (may appear as **Double Tap**) | Ripple Double Pinch | Ripple Double Pinch |
| double clench | Ripple Double Clench | Ripple Double Clench |

Each imported shortcut contains only its matching Ripple Watch App Intent action. Avoid adding **Open App**, **Show Alert**, or another action that requests a screen change. Ripple also publishes the four actions through its Watch App Shortcuts provider. Appearance of the imported wrappers in the AssistiveTouch assignment picker still needs to be checked on the physical Watch.

These are separate from the existing **Ripple Alert** messaging shortcut. Do not replace it or assign it directly to a hand gesture.

On the iPhone:

1. Open **Watch → Accessibility → AssistiveTouch**.
2. Turn on **AssistiveTouch** and **Hand Gestures**.
3. Open each of the four gesture assignments. Select **Shortcuts**, then choose its matching Ripple input shortcut from the table.
4. Set **Activation Gesture → None** so double clench can run its assigned shortcut rather than being consumed as the activation gesture.
5. Open **Ripple → Settings → Hand gestures**, enable hand gesture dismissal, choose the preset, and **Save**.
6. In **Watch sync**, wait until the iPhone and Watch configuration versions match.

The AssistiveTouch assignments apply across watchOS. AssistiveTouch disables Apple's native double tap. The physical input shortcuts continue to represent the same four base gestures whenever the dropdown changes; choose another preset and save/sync it without rebuilding the shortcuts.

## Generate wrappers for another local build

The wrappers must name the bundle identifier of the Watch app that will be installed. Generate a matching set on the Mac with [the shortcut generator](../scripts/build_hand_gesture_shortcuts.py):

```bash
python3 scripts/build_hand_gesture_shortcuts.py \
  --bundle-id com.example.ripple.wearer.watchkitapp \
  --output-dir /tmp/ripple-hand-gestures \
  --sign
```

Replace the example bundle identifier with the installed Watch app's bundle identifier. The `--sign` flag signs the wrappers using Apple's `shortcuts sign`; without it the generator only creates unsigned files for inspection. If the local build requires a team identifier, pass `--team-id` followed by that identifier as well. Add `--validate-native` to check the generated workflow structure with the Mac's native shortcut parser. Keep personal signing settings outside this repository. Send the generated signed `.shortcut` files to the iPhone; the generated source/unsigned files are for inspection and regeneration.

## Physical acceptance check

The iPhone and Watch can remain disconnected while code is built on the Mac. When the devices return:

1. Install the updated builds over the existing apps, preserving the wearer account and configuration.
2. Set up and sync the four input shortcuts and AssistiveTouch assignments above.
3. With **no alarm open**, keep Ripple visible on the Watch and run each gesture. Verify that **Gesture #N: <gesture>** and its status update and that Ripple remains visible. This check must use the actual AssistiveTouch gesture; calling the matcher directly does not verify the integration.
4. Still with no alarm open, run two different gestures in succession and check both input receipts. This establishes successive shortcut delivery only; sequence matching runs only while an alarm is active.
5. During a separately coordinated alarm test, check each single gesture preset and each compound preset. Save and confirm Watch sync after each selection. Perform an incomplete sequence, then the complete selected sequence within 5 seconds between steps. Only the complete match should answer that same alarm.
6. During those alarm tests, repeat with a gap longer than 5 seconds and with a wrong first or second gesture. Check that these do not dismiss the alarm, and that no old partial sequence can carry into a new alarm or a changed preset.

Mac unit tests cover preset matching, duplicate handling, sequence timeout/reset, and backward-compatible configuration decoding. Device testing must establish actual shortcut delivery, single/double gesture recognition, execution order, and whether Ripple stays visible.
