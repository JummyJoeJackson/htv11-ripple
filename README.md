# Temporary Read.md 

**Calls for human help when a person can't ask for it themselves.**

KAZE is a safety check-in system built for people living with Parkinson's, who may face freezing episodes, falls, medication "off" periods, confusion, or trouble speaking or reaching a phone. The wearer starts a safety session on their iPhone and answers check-ins on their Apple Watch. If they don't respond, ask for help, or enter a duress PIN, KAZE alerts a trusted contact or a temporary helper nearby.

KAZE doesn't try to work out *what* happened. It only needs to know that no response came in. The goal is to shorten the gap between **"can't act"** and **"someone knows,"** while leaving the wearer in control of their independence and privacy.

> Hackathon prototype built for Hack the Valley 11. This is not a validated medical or emergency-response system, and it does not detect falls, unconsciousness, intoxication, or any medical condition.

## How it works

1. **Start a session.** The wearer heads out, for example to a community centre on their own, and starts a session on their iPhone. The backend registers the deadline before the app shows monitoring as active.
2. **Check in.** When a check-in is due, the watch buzzes and shows one large **I'm okay** button. The wearer can tap it or use the watch's native double-tap gesture.
3. **No response means an alert.** If the check-in goes unanswered, the backend opens an incident and sends an SMS to the first responder: an accepted temporary helper at the venue if there is one, otherwise trusted contacts in the order the wearer chose.
4. **Escalate.** If a responder declines or doesn't acknowledge in time, the alert moves to the next person.
5. **Resolve.** Responders mark progress (Acknowledged → Arranging help → Resolved) on a web page that needs no app install and no login. If the wearer's "I'm okay" arrives late, everyone already contacted is updated.

The wearer can also press **Get help** at any time to send an alert immediately.

## Key features

- **Server-owned timers.** Deadlines and escalation run on the backend, so an alert still fires if the phone or watch dies or loses signal. Silence is the signal: if session heartbeats stop, the backend starts the assistance flow on its own.
- **Temporary helpers.** Venue staff who have consented can cover a wearer for a set period, which helps when family is too far away to respond quickly. Their access expires automatically and the wearer can revoke it with one tap.
- **Safety PIN and duress PIN.** The safety PIN cancels a false alarm. The duress PIN looks exactly like a cancellation on screen but silently keeps the alert going.
- **False-alarm handling.** A late "I'm okay" or a safety-PIN cancellation notifies every responder already contacted. The incident history is kept.
- **Privacy by permission.** Trusted contacts and helpers see only what the wearer allows. Location is shared only during an alert and is labelled "last known" with a timestamp.
- **Accessible by design.** Every gesture has a button alternative. The app uses large touch targets, high contrast, strong haptics, and status colours that always come with text labels.

## Components

| Component | Role |
| --- | --- |
| **Wearer iPhone app** (SwiftUI) | Setup, contacts, PINs, sharing permissions, session control, helper invitations, heartbeats |
| **Apple Watch app** (SwiftUI) | Check-in prompts, **I'm okay** and **Get help** buttons, double tap, haptics, status. The watch never owns a timer. |
| **Backend + job worker** | Authoritative state, deadlines, escalation, access control, SMS through a messaging adapter |
| **Helper web pages** | Phone-friendly enrollment and responder views that work through verified, scoped links |
| **Demo admin iPhone app** | Labelled demo mode for triggering, stopping, and resetting scenarios |

## What's real and what's simulated

| Demonstrated | Simulated | Assumed | Needs validation |
| --- | --- | --- | --- |
| Watch input, shared backend state, timers, real SMS delivery, escalation, helper workflow, privacy controls | The concerning event, falls or sensor changes, the venue and staff setting, the wearer's incapacity | Helpers are available and willing to respond, and participating venues authorize their staff | Gesture reliability with Parkinson's symptoms, false-alarm rates, background execution, battery use, delivery reliability, real responder times |

## Future work

Intermediate check-ins, custom wrist gestures, background notifications, user-declared offline windows, medication reminders, acknowledging alerts by replying to the SMS, extra message channels, and an AI incident summary that never diagnoses or makes emergency decisions.

## Documentation

The full product requirements are in [PROJECT_KAZE_PRD.md](PROJECT_KAZE_PRD.md).

## License

See [LICENSE](LICENSE).
