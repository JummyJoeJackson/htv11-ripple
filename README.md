# Ripple

**Gets a person help when they can't respond to an alarm on their Apple Watch.**

Ripple is a safety check-in system built for people living with Parkinson's, who can suddenly be unable to move, speak, or reach their phone during a fall, a freeze, or a medication "off" period. The wearer sets everything up on their iPhone and answers check-ins with one large circle on their Apple Watch. If they don't respond, or hold the circle to signal duress, their iPhone texts the contacts they chose.

Ripple doesn't try to work out *what* happened. A missed response means only that no response was received. The goal is to shorten the gap between **"can't act"** and **"someone knows,"** while leaving the wearer in control of their independence and privacy.

> Hackathon prototype built for Hack the Valley 11 (Kaze track). This is not a validated medical or emergency-response system, and it does not detect falls, unconsciousness, intoxication, or any medical condition. Demo alarms are simulated.

## How it works

1. **Turn on monitoring.** The wearer taps **Start** on the Watch circle. Check-ins can run on a timer, or a demo admin can start one.
2. **Check in.** When an alarm starts, the Watch buzzes, turns yellow and shows **I'm okay** with a countdown. The wearer taps the circle, double taps, or says their voice phrase to dismiss it. The Watch listens for the phrase by itself during an alarm. Nothing is sent.
3. **No response means a text.** If the countdown runs out, the wearer's iPhone texts **Tier 1** contacts from the wearer's own number, through a shortcut called **Ripple Alert**. Each text has a link: "I'm checking on [Name]."
4. **Escalate.** If nobody taps the link within the acknowledge window, **Tier 2** is texted. When someone does tap it, the Watch shows "[Contact] is responding" and everyone else already texted is told who's checking.
5. **Okay now.** If the wearer taps **I'm okay now**, everyone already texted gets an "okay now" text and pending escalation stops.

Holding the circle for 2 seconds is **duress**: the Watch shows the normal "Dismissed" screen while the alert still goes out.

**Swipe combos** help when movement is shaky. Swiping up on the circle twice asks for help: contacts are texted straight away, even when monitoring is off. Swiping down twice during an alarm means "I'm okay". It takes two swipes in the same direction, so a single shaky movement can't trigger either one.

**Pinch and clench** work through Apple's AssistiveTouch, which recognises the gestures. With the circle highlighted, a clench means "I'm okay". A double clench opens the Action Menu, where **Get help** asks for help.

## Key features

- **The phone sends first.** Texts come from the wearer's iPhone and messaging account, so contacts need no app, account or portal.
- **A declared backup.** If the phone goes quiet, the backend sends the alert by SMS after a 30-second grace period, marked "Sent by Ripple backup." When the phone comes back it doesn't repeat what the backup already sent.
- **Tiers.** Each contact is in Tier 1 (texted first) or Tier 2 (texted if nobody in Tier 1 acknowledges in time).
- **Temporary contacts.** Someone nearby can agree to be a contact for one hour by scanning a QR code. They join Tier 1 until the session ends or the wearer removes them; after that they get nothing.
- **Duress.** A 2-second hold looks exactly like a dismissal on the Watch and the iPhone, and the alert text is the normal one, so nothing reveals it.
- **Privacy by permission.** Location is off by default and set per contact. Ripple takes one location fix when an alarm starts and never tracks in the background. An optional help card, written by the wearer, is added to alerts only if they turn it on.
- **Hard to trigger by accident.** Stopping monitoring needs a hold and a confirmation. Double tap and voice can only dismiss; duress is touch only. Swipe combos need two swipes in the same direction. Tremor that moves back and forth doesn't count as a swipe, and a finger bouncing off the glass counts once.
- **Accessible by design.** Every gesture has a touch alternative. Status colours always come with text: green Monitoring, yellow Check in, red Alert sent, blue Contact responding, gray Off.

## Components

| Component | Role |
| --- | --- |
| **Wearer iPhone app** (SwiftUI) | Contacts and tiers, location permissions, temporary contacts, help card, timings, dismiss methods, Watch sync. Runs the alarm and sends texts through the Ripple Alert shortcut. |
| **Apple Watch app** (SwiftUI) | One large circle with a status label and countdown. Tap, hold, native double tap and voice phrase. During an alarm the microphone listens for the phrase and streams to the iPhone, which recognizes it (watchOS has no speech recognition). Keeps the last settings it received. |
| **Ripple server** (Swift, Vapor) | Mirrors each alarm, holds the backup deadline, sends backup SMS through Twilio, hosts the acknowledge and consent pages, and relays demo admin commands. |
| **Web pages** | A one-button acknowledge page and a consent page for temporary contacts. No app, account or login. |
| **Demo admin iPhone app** (SwiftUI) | Labelled Demo admin. Triggers alarms, cuts the phone connection, expires temporary contacts, disables alarms, resets the demo, and shows per-recipient message status. |
| **RippleKit** (Swift package) | Shared models, message wording, tier rules and the alarm state machine used by every app and the server |

## What's real and what's simulated

| Demonstrated | Simulated | Assumed | Needs validation |
| --- | --- | --- | --- |
| Watch input, alarms, real texts to teammates, tiers, the acknowledge link, duress, okay now texts, backup SMS, location permissions, contact expiry | Alarm triggers, the wearer being unable to respond, phone failure | Contacts read their texts and act on them, and the wearer keeps their phone charged and nearby | Sending from a locked phone, gestures, swipe combos, pinch and clench, and voice with Parkinson's tremor, accidental duress rate, false-alarm rate, battery use, real response times |

## Future work

Sending from a locked or backgrounded phone, background Watch prompts, physical-button dismissal, inviting temporary contacts from the Watch, acknowledging by replying to the text, and extra message channels.

## Documentation

- Product requirements: [PROJECT_KAZE_PRD.md](PROJECT_KAZE_PRD.md)
- How to run it on a Mac, iPhone and Apple Watch: [docs/RUNNING.md](docs/RUNNING.md)
- Implementation plan: [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)

## License

See [LICENSE](LICENSE).
