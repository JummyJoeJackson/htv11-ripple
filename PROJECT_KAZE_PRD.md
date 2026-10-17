# Ripple: Product Requirements Document

October 16, 2026 · HTV11 prototype · Kaze track

## Purpose

Ripple gets a person help when they cannot respond to an alarm on their Apple Watch. The primary audience is people with Parkinson's, who can suddenly be unable to move, speak, or reach their phone during a fall, a freeze, or a medication "off" period. The wearer configures everything on their iPhone, uses a one circle Watch interface, and has trusted contacts texted at their phone numbers. A separate iPhone app controls alarms during demonstrations.

A missed response means only that no response was received. The prototype does not diagnose a condition or detect falls, intoxication, drugging, or unconsciousness. Demo alarm triggers are simulated.

The design covers all seven Kaze demo scenarios: safe, no response, duress, connectivity failure, unacknowledged alert, false alarm, and privacy.

## The three apps

### 1. Wearer's iPhone app: configuration

- Add, edit, and remove permanent contacts by name and phone number.
- Place each contact in **Tier 1** (texted first) or **Tier 2** (texted if nobody in Tier 1 acknowledges in time).
- Per contact toggle: **Share my location in alerts.** Off by default.
- Invite someone to be a temporary contact for a one-hour session. Record their consent, show when the session expires, and allow early removal. An expired or removed contact must not receive new alerts. Temporary contacts join Tier 1 while active.
- Optional **help card**: a short note added to alert texts, written by the wearer, such as "I have Parkinson's. I may look confused. My medication is in my left pocket." Off by default.
- Configure preferred supported Watch gestures and a voice phrase for dismissing alarms. Touch remains available as the fallback.
- Configure check-in timing, the response countdown, and the acknowledge window before Tier 2 is texted. Short timers may be used for demos.
- Optional **medication times**: the times the wearer usually takes each dose, used to schedule check-ins (see [Parkinson's-aware check-ins](#parkinsons-aware-check-ins)). Off by default.
- Optional **context line** in alert texts, with separate toggles for last steps, last medication, and help card. Off by default.
- Send configuration to the paired Watch and show whether synchronization succeeded. The Watch should retain the last successfully received configuration.
- Show basic monitoring, alarm, connection, backend, and message status. This app is primarily for setup, not a complicated live dashboard.

All app preferences live here. Apple-controlled accessibility settings and permissions may still require the user's action in system settings; app configuration cannot override them.

### 2. Apple Watch app: one large circle

The main screen contains one large circle, a short status label, and a countdown when an alarm is pending. No contact lists or configuration forms belong on the main screen.

Use these default circle actions so every action is unambiguous and hard to trigger by accident:

| Current state | Circle label | Tap | Hold 2 seconds |
| --- | --- | --- | --- |
| Monitoring off | Start | Enables monitoring. | Same as tap. |
| Monitoring on, no alarm | Stop | Shows "Hold to stop." Nothing else. | Asks "Stop monitoring?" and disables it on confirm. |
| Alarm awaiting response | I'm okay | Cancels this alarm and keeps monitoring enabled. | **Duress.** Shows the normal "Dismissed" screen while the alert still sends. |
| Contact alert already sent | I'm okay now | Ends this alarm and texts "okay now" to everyone already alerted. | **Duress.** Shows the normal screen while escalation continues. |

Give clear visual and haptic feedback. Use readable text and color together: green Monitoring, yellow Check in, red Alert sent, blue Contact responding, gray Off. A strong haptic starts each alarm and repeats at 10 seconds left. When a contact acknowledges, the Watch shows "[Contact] is responding."

The duress screen must look identical to a real dismissal. Nothing on the Watch, iPhone, or alert text reveals that duress was used.

Desired ways to dismiss an alarm:

- **Touch:** press the circle; required baseline.
- **Apple gestures:** use a supported gesture, such as native double tap, for the visible dismiss action. Preferences are selected on the iPhone and synced to the Watch. Only offer gestures actually implemented on the test device.
- **Voice:** recognize the configured phrase through a supported voice mechanism. Validate foreground microphone/listening or Siri/Shortcuts integration on the actual Watch; do not assume an always-listening custom wake phrase works in the background.
- **Physical button, if possible:** investigate supported hardware input. Standard side-button and Digital Crown presses have system functions and are not ordinary app buttons. Do not make them a required cancellation method unless a supported route is demonstrated.

Duress is touch only (the 2 second hold), so a misheard voice phrase or a stray double tap can never trigger or hide it. Native double tap supports one primary action per scene, and its control must be visible. It does not provide arbitrary custom gesture recognition. Voice and gesture failures must leave the touch fallback available.

Inviting a temporary contact from the Watch is optional. It may show a simple invitation shortcut or QR code if practical, but must not add a Watch setup workflow.

### 3. Second iPhone app: demo admin

This app exists solely to simplify testing and presentations:

- Select the paired/authorized demo wearer.
- Trigger an alarm and its response countdown on the wearer's Watch.
- **Cut phone connection:** tells the wearer iPhone to stop sending heartbeats, to demonstrate the backup sender.
- **Expire temporary contact now.**
- Disable the current alarm.
- Reset the demo and adjust short demo countdowns.
- Show basic current state, per-recipient message status, and whether a command reached the wearer device.

Admin commands must exercise the same alarm behavior as the wearer app. Resetting must clear old pending countdowns, acknowledge windows, and backend deadlines so they cannot fire in the next run. Label this app Demo admin; it is not a caregiver app.

## Parkinson's-aware check-ins

These features decide *when* to check in and what context to send. None of them detects a fall, a freeze, or any condition, and none of them sends an alert on its own. Each one only starts a normal check-in, and the wearer answers it the usual way.

### Medication-timed check-ins

- The wearer enters their usual medication times on the iPhone.
- Check-ins are scheduled near when a dose usually wears off. That's the "off" period, when moving and using the phone is hardest.
- At each dose time the Watch shows one **Took my meds** tap. A missed tap starts a gentle check-in with the normal countdown.
- No sensors are needed. The app stores only the dose times and the time of the last tap.

### Sudden stop during a walk

- The wearer can start a **walk session** from the Watch.
- During the session, read step counts with CMPedometer.
- If steps stop suddenly for a few minutes, start a check-in. This catches a possible freeze or fall without claiming to detect one.
- Uses real step data and is easy to demo by standing still. Validate whether step updates continue while the Watch screen is off.

### Tremor and dyskinesia context (simulated)

- Apple Watch has a Movement Disorder API that records tremor and dyskinesia, but it requires Apple's approval. Simulate the data for the demo and list it as simulated in the honesty table.
- Use it only as context, such as "tremor was high in the last hour" in the alert. Never use it as a trigger or a diagnosis.

### Context line in the alert

With the wearer's permission, the alert text adds one short context line built from data the app already has:

> "Last steps 4 min ago. Last meds 1:00 PM. Help card: I may look confused. Meds in left pocket."

The contact arrives knowing what to expect. Each part appears only if the wearer turned it on, and the line never states a diagnosis or a cause.

### Built for Parkinson's bodies

- Touch and double tap come first, since voice can get soft. Voice stays optional.
- Big targets and hold actions, so tremor doesn't cause accidental taps.
- Optional **rhythmic haptic beat** during a check-in. Rhythm cues are a known strategy for freezing; present it as comfort only, not treatment.

## Phone-number messaging

**Every alert goes to a configured phone number, sent first from the wearer's iPhone and messaging account.** Contacts do not need an app, account, email address, or portal. For testing, the user's iPhone sends actual messages to teammates' phones.

- Send an individual message to each currently eligible Tier 1 contact: Tier 1 permanent contacts plus accepted, unexpired one-hour contacts.
- Include the location link only for contacts with location sharing on. Take one location fix at alert time; never track location in the background.
- Include the help card only if the wearer turned it on.
- Prevent duplicate sends for the same alarm and recipient. Cancelling an alarm stops pending, unsent messages; it cannot retract a message already sent.
- Show pending, submitted, failed, or unknown status accurately. Confirm actual receipt on teammates' phones during the demo.
- Messages may use SMS or iMessage according to the phone's configuration.
- Do not claim a diagnosis or confirmed emergency in any message.

Message templates:

| Event | Message |
| --- | --- |
| Alert | "RIPPLE ALERT: [Name] did not respond to their Watch check-in at [time]. Please call or check on them. [Note, if on] Reply "Ripple accept [code]" if you are able to check in on [Name]. [Location link, if allowed]" |
| Escalation to Tier 2 | "RIPPLE ALERT: [Name] did not respond at [time] and no one has confirmed yet. Please call or check on them. Reply "Ripple accept [code]" if you are able to check in on [Name]. [Location link, if allowed]" |
| Someone responding | "Halo: [Contact] is checking on [Name]." |
| Okay now | "Halo: [Name] says they're okay now ([time]). No action needed." |

A duress alert uses the normal Alert text so the message never reveals duress if the wearer's phone is seen.

### Escalation and acknowledgment

Each alert text asks the contact to reply **Ripple accept [code]**, with a distinct four-digit code for each recipient of the active alarm. A Messages automation on the wearer's iPhone passes matching replies to Ripple. Contacts need no app or shortcut. The alert, optional note, reply instruction, and optional location are separated by blank lines, with the Maps URL last.

1. Alert texts go to Tier 1.
2. A valid reply records who responded and when. The Watch and iPhone show "[Contact] is responding," and other alerted contacts get the "Someone responding" text.
3. If no one replies within the acknowledge window, Tier 2 gets the escalation text.
4. If the wearer taps "I'm okay now" at any point, everyone already texted gets the "Okay now" text and pending escalation stops.

Acknowledging means someone took responsibility. It does not mean help has arrived. Replies for a closed alarm, an unknown code, or a contact not yet texted are ignored. Reply acceptance depends on the wearer's iPhone receiving the reply and running its automation; a separate backup SMS number does not forward replies to that automation.

### Chosen demo approach: Apple Shortcuts

A native iPhone app built in Xcode can launch a saved shortcut on the same iPhone through Apple's documented Shortcuts URL scheme. Use a user-installed shortcut named **Halo Alert** as the demo messaging path.

One-time setup on the wearer's iPhone:

1. Create **Halo Alert** in Shortcuts and add a **Send Message** action.
2. For the first test, use one teammate's phone number and a short test message. For integration, the app supplies the message text and currently eligible recipients as text input, excluding expired or removed contacts. Each recipient may get a different message (location on or off), so the payload pairs each number with its own text. The shortcut must parse that payload and repeat Send Message with one recipient per iteration to avoid a group message.
3. Turn **Show When Run** off on Send Message so it can send without presenting the message composer.
4. Run the shortcut manually once and approve any required permissions before the demo.

From the foreground iPhone app, launch the installed shortcut with:

```swift
let url = URL(string: "shortcuts://run-shortcut?name=Halo%20Alert&input=text&text=\(encodedPayload)")!
UIApplication.shared.open(url)
```

This opens Shortcuts to run the workflow. Successfully opening the URL does not prove that a message was sent or received.

The intended flow is **Watch countdown expires → wearer iPhone app launches Halo Alert → shortcut messages eligible contacts**. Start with the wearer's iPhone unlocked and the app in the foreground. App-to-shortcut launching is documented; automatic activation while the phone is locked or the app is suspended remains unverified and must be tested separately.

Apple's standard in-app message composer still requires someone to tap Send; it is not the chosen automatic messaging route. Prove the Shortcuts path early on the actual phone. If it still requires interaction, label that as a demo limitation.

### Backup sender for phone failure

Phone-originated messages depend on the wearer's phone being available. To cover the Kaze connectivity failure scenario, a small backend acts as a declared backup, never a silent replacement:

- When an alarm starts, the iPhone registers it with the backend: alarm id, deadline, eligible recipients and their messages.
- While the alarm is open, the iPhone sends a heartbeat every 10 seconds and reports each outcome: dismissed, alert submitted, acknowledged, escalated.
- **If the deadline plus a 30 second grace passes with no report, or heartbeats stop,** the backend sends the alert by SMS through Twilio, marked "sent by backup."
- The backend holds the acknowledge window. If the phone is gone, the backend sends the Tier 2 escalation itself.
- The phone always sends first. The status screen shows which path sent each message.

The backend stores only alarm ids, timestamps, phone numbers, and message text for open alarms. Demo data is deleted on reset.

## Simple system flow

1. Configure contacts, tiers, location permissions, response methods, and alarm timing on the wearer iPhone; synchronize with the Watch.
2. Enable monitoring using the Watch circle.
3. An enabled check-in timer, a medication-time check-in, a sudden stop during a walk session, or a demo-admin command starts an alarm, haptic, and response countdown. The iPhone registers the alarm with the backend.
4. A tap or a supported configured response cancels the current alarm before messages are sent. A 2 second hold dismisses on screen but continues as duress.
5. If the countdown expires unanswered, the wearer's iPhone app launches Halo Alert to text Tier 1.
6. The acknowledge window runs. No acknowledgment means Tier 2 is texted.
7. If the phone goes silent at any point, the backend sends the remaining messages by SMS.
8. "I'm okay now" ends the alarm and texts everyone already alerted. Resetting the demo cancels all remaining work. Duplicate commands must not restart an alarm or create duplicate alerts.

Use SwiftUI for the three apps and WatchConnectivity for paired iPhone–Watch configuration and actions. Keep shared state minimal: monitoring on/off, current alarm/countdown, duress flag (never displayed), configuration version, contacts with tiers, location permission, and expiry times, acknowledgment status, per-recipient message status with sending path, and, if enabled, medication times, the last "Took my meds" tap, and the time of the last steps. A lightweight backend connects the admin phone to the wearer phone, hosts the temporary-contact consent page, and holds the backup deadline.

## MVP and demo checks

The core scope is the three apps, configuration sync, one-circle Watch UI with guarded Stop and duress hold, working touch and supported Apple-gesture dismissal, permanent and one-hour phone contacts with tiers and location permissions, a real phone-to-phone messaging path, reply acknowledgement with Tier 2 escalation, "okay now" follow-up texts, and the backend backup sender. Voice dismissal is a desired input to validate; help card, physical-button dismissal, and Watch invitations are conditional extras. The Parkinson's-aware check-ins (medication timing, walk-session step stops, the alert context line, and the rhythmic haptic) are extras that build on the core alarm; simulated tremor context is presentation only.

Demonstrate all seven Kaze scenarios with 15 second demo timers:

| Scenario | Demo steps | What judges see |
| --- | --- | --- |
| Safe | Admin triggers an alarm. Wearer taps. Trigger again; wearer double taps. | Watch returns to green. No texts sent. |
| No response | Trigger and let it expire. | Tier 1 teammate's phone receives the alert with a location link. |
| Unacknowledged alert | Tier 1 does not reply. | Tier 2 teammate receives the escalation text after the acknowledge window. |
| False alarm | After texts go out, wearer taps "I'm okay now." | Everyone already texted receives "okay now." |
| Duress | Trigger; wearer holds the circle 2 seconds. | Watch shows a normal "Dismissed" screen. Tier 1 still receives the alert. |
| Connectivity failure | Trigger, then admin cuts the phone connection. | Backend sends the alert by SMS after the grace period. |
| Privacy | One contact has location off; admin expires the temporary contact. | Only the location-on contact gets a map link. The expired contact gets nothing. |

Then show reset without an old alarm returning. Demonstrate voice only when it actually works, and clearly label any manual message confirmation or simulated behavior.

If the extras are built, also show: skip the "Took my meds" tap and see a gentle check-in start; start a walk session, stand still, and see a check-in start; and let one alert expire so a teammate receives the context line.

Present this honesty table:

| Category | What to report |
| --- | --- |
| Demonstrated | Watch input, alarms, real texts to teammates, tiers, reply acknowledgements, duress, okay now texts, backup SMS, location permissions, contact expiry. If built: medication-timed check-ins, step-stop check-ins from real step data, the alert context line. |
| Simulated | Alarm triggers, the wearer being unable to respond, phone failure, tremor and dyskinesia data. |
| Assumed | Contacts read texts and act on them. The wearer keeps the phone charged and nearby. The wearer enters accurate medication times. |
| Needs validation | Locked-phone sending, gestures and voice with Parkinson's tremor, accidental duress rate, false alarm rate, battery use, real response times, step-stop thresholds and background step updates, whether rhythmic haptics feel comforting. |

No helper portals, venue-staff network, physician view, AI assistant, fall or freeze detection, or medical interpretation are required for this MVP. Medication times and step data only schedule or start check-ins. Test background behavior, locked-phone operation, voice recognition, and gesture accessibility separately before making reliability claims.

## Platform references

- [Apple: message composer and user approval](https://developer.apple.com/documentation/messageui/mfmessagecomposeviewcontroller)
- [Apple: run a saved shortcut from another app](https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/ios)
- [Apple: Send Message with Show When Run off](https://support.apple.com/en-ca/101583)
- [Apple: Watch buttons and gestures](https://support.apple.com/en-us/105063)
- [Apple: native double-tap integration](https://developer.apple.com/documentation/watchos-apps/enabling-double-tap)
- [Twilio: send an SMS](https://www.twilio.com/docs/messaging/quickstart)
- [Apple: CMPedometer](https://developer.apple.com/documentation/coremotion/cmpedometer)
- [Apple: CMMovementDisorderManager](https://developer.apple.com/documentation/coremotion/cmmovementdisordermanager)
