# Project KAZE — Product Requirements Document

October 16, 2026 · HTV11 prototype · Simplified scope

## Purpose

KAZE helps a person get assistance when they cannot respond to an alarm on their Apple Watch. The primary audience is people with Parkinson's. The wearer configures everything on their iPhone, uses a minimal Watch interface, and has emergency contacts notified at their phone numbers. A separate iPhone app controls alarms during demonstrations.

A missed response means no response was received. The prototype does not diagnose a condition or detect falls, intoxication, drugging, or unconsciousness. Demo alarm triggers are simulated.

## The three apps

### 1. Wearer's iPhone app: configuration

- Add, edit, and remove permanent backup contacts by name and phone number.
- Invite someone to be a temporary emergency contact for a one-hour session. Record their consent, show when the session expires, and allow early removal. An expired or removed contact must not receive new alerts.
- Configure preferred supported Watch gestures and a voice phrase for dismissing alarms. Touch remains available as the fallback.
- Configure alarm/check-in timing and the response countdown. Short timers may be used for demos.
- Send configuration to the paired Watch and show whether synchronization succeeded. The Watch should retain the last successfully received configuration.
- Show basic monitoring, alarm, connection, and message status. This app is primarily for setup, not a complicated live dashboard.

All app preferences live here. Apple-controlled accessibility settings and permissions may still require the user's action in system settings; app configuration cannot override them.

### 2. Apple Watch app: one large circle

The main screen contains one large tappable circle, a short status label, and a countdown when an alarm is pending. No contact lists or configuration forms belong on the main screen.

Use these default circle actions so enabling monitoring and dismissing an alarm are unambiguous:

| Current state | Circle label | Pressing the circle does |
| --- | --- | --- |
| Monitoring off | Start | Enables monitoring. |
| Monitoring on, no alarm | Stop | Disables future monitoring. |
| Alarm awaiting response | I'm okay | Cancels this alarm and keeps monitoring enabled. |
| Contact alert already initiated | Dismiss alarm | Ends this alarm locally; messages already sent cannot be recalled. |

Give clear visual and haptic feedback. Use readable text and color together. Do not require a PIN or a separate responder-resolution workflow to dismiss an alarm in this simplified version.

Desired ways to dismiss an alarm:

- **Touch:** press the circle; required baseline.
- **Apple gestures:** use a supported gesture, such as native double tap, for the visible dismiss action. Preferences are selected on the iPhone and synced to the Watch. Only offer gestures actually implemented on the test device.
- **Voice:** recognize the configured phrase through a supported voice mechanism. Validate foreground microphone/listening or Siri/Shortcuts integration on the actual Watch; do not assume an always-listening custom wake phrase works in the background.
- **Physical button, if possible:** investigate supported hardware input. Standard side-button and Digital Crown presses have system functions and are not ordinary app buttons. Do not make them a required cancellation method unless a supported route is demonstrated.

Native double tap supports one primary action per scene, and its control must be visible. It does not provide arbitrary custom gesture recognition. Voice and gesture failures must leave the touch fallback available.

Inviting a temporary contact from the Watch is optional. It may show a simple invitation shortcut or QR code if practical, but must not add a Watch setup workflow.

### 3. Second iPhone app: demo admin

This app exists solely to simplify testing and presentations:

- Select the paired/authorized demo wearer.
- Trigger an alarm and its response countdown on the wearer's Watch.
- Disable the current alarm.
- Reset the demo and adjust short demo countdowns.
- Show basic current state and whether a command reached the wearer device.

Admin commands must exercise the same alarm behavior as the wearer app. Resetting must clear old pending countdowns so they cannot fire in the next run. Label this app Demo admin; it is not a caregiver app.

## Phone-number messaging

**Every emergency-contact alert goes to a configured phone number using the wearer's iPhone and messaging account.** Contacts do not need a KAZE app, account, email address, or web portal. For testing, the user's iPhone sends actual messages to teammates' phones.

- Send an individual message to each currently eligible contact: permanent backup contacts plus accepted, unexpired one-hour contacts. No acknowledgment-based escalation chain is required for this version.
- Use a short message such as: “KAZE alert: [Name] did not respond to their Watch check-in at [time]. Please call or check on them.” Do not claim a diagnosis or confirmed emergency.
- Prevent duplicate sends for the same alarm and recipient. Cancelling an alarm stops pending, unsent messages; it cannot retract a message already sent.
- Show pending, submitted, failed, or unknown status accurately. Confirm actual receipt on teammates' phones during the demo.
- Messages may use SMS or iMessage according to the phone's configuration. The requirement is delivery to phone-number contacts from the wearer's phone.

### Chosen demo approach: Apple Shortcuts

A native iPhone app built in Xcode can launch a saved shortcut on the same iPhone through Apple's documented Shortcuts URL scheme. Use a user-installed shortcut named **KAZE Alert** as the demo messaging path.

One-time setup on the wearer's iPhone:

1. Create **KAZE Alert** in Shortcuts and add a **Send Message** action.
2. For the first test, use one teammate's phone number and a short test message. For integration, the app supplies alert text and currently eligible recipients as text input, excluding expired or removed contacts. The shortcut must parse that payload and repeat Send Message with one recipient per iteration to avoid a group message.
3. Turn **Show When Run** off on Send Message so it can send without presenting the message composer.
4. Run the shortcut manually once and approve any required permissions before the demo.

From the foreground iPhone app, launch the installed shortcut with:

```swift
let url = URL(string: "shortcuts://run-shortcut?name=KAZE%20Alert")!
UIApplication.shared.open(url)
```

This opens Shortcuts to run the workflow. Alert data can be passed using the URL's `input=text` and URL-encoded `text` parameters. Successfully opening the URL does not prove that a message was sent or received.

The intended flow is **Watch countdown expires → wearer iPhone app launches KAZE Alert → shortcut messages eligible contacts**. Start with the wearer's iPhone unlocked and KAZE in the foreground. App-to-shortcut launching is documented; automatic activation while the phone is locked or the app is suspended remains unverified and must be tested separately.

Apple's standard in-app message composer still requires someone to tap Send; it is not the chosen automatic messaging route. Prove the Shortcuts path early on the actual phone. If it still requires interaction, label that as a demo limitation. Do not silently replace phone-originated messages with a server SMS provider or a Mac relay.

Phone-originated messages depend on the wearer's phone being available and able to send. A backend cannot send through a dead or disconnected phone. This version makes no guarantee that contacts will still be messaged after phone failure.

## Simple system flow

1. Configure response methods, contacts, and alarm timing on the wearer iPhone; synchronize with the Watch.
2. Enable monitoring using the Watch circle.
3. An enabled check-in timer or a demo-admin command starts an alarm, haptic, and response countdown.
4. Touch or a supported configured response cancels the current alarm before messages are initiated.
5. If the countdown expires unanswered, the wearer's iPhone app launches KAZE Alert to message eligible contact phone numbers through Shortcuts.
6. Dismissing an alarm or resetting the demo cancels its remaining work. Duplicate commands must not restart it or create duplicate alerts.

Use SwiftUI for the three apps and WatchConnectivity for paired iPhone–Watch configuration and actions. Keep shared state minimal: monitoring on/off, current alarm/countdown, configuration version, contacts with expiry times, and per-recipient message status. A lightweight backend or relay may connect the admin phone to the wearer phone; it is not the message sender. Keep detailed implementation choices open until the device tests establish what works.

## MVP and demo checks

The core scope is the three apps, configuration sync, one-circle Watch UI, working touch and supported Apple-gesture dismissal, permanent and one-hour phone contacts, and a real phone-to-phone messaging path. Voice dismissal is a desired input to validate; physical-button dismissal and Watch invitations are conditional extras.

Demonstrate: configure and sync → enable monitoring → admin triggers an alarm → dismiss by touch and a supported Apple gesture → trigger again and let it expire → receive a real message on a teammate's phone → expire/remove a temporary contact → disable/reset without an old alarm returning. Demonstrate voice only when it actually works, and clearly label any manual message confirmation or simulated behavior.

No helper portals, venue-staff network, physician view, AI assistant, medication reminders, sensor detection, duress PINs, or complex responder lifecycle are required for this simplified MVP. Test background behavior, locked-phone operation, voice recognition, and gesture accessibility separately before making reliability claims.

## Platform references

- [Apple: message composer and user approval](https://developer.apple.com/documentation/messageui/mfmessagecomposeviewcontroller)
- [Apple: run a saved shortcut from another app](https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/ios)
- [Apple: Send Message with Show When Run off](https://support.apple.com/en-ca/101583)
- [Apple: Watch buttons and gestures](https://support.apple.com/en-us/105063)
- [Apple: native double-tap integration](https://developer.apple.com/documentation/watchos-apps/enabling-double-tap)
