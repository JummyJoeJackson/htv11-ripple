# Project KAZE — Product Requirements Document

October 16, 2026 · HTV11 hackathon prototype · Consolidated PRD

## 1. What we are building

KAZE starts a call for human help when a person cannot ask for it. A wearer starts a safety session on their iPhone and answers check-ins on an Apple Watch. If they do not respond, request help directly, or enter a duress PIN, the backend alerts their trusted contacts or an accepted temporary helper at a participating venue.

The primary audience is people with Parkinson's, who may experience freezing, falls, medication “off” periods, confusion, or difficulty speaking or reaching a phone. The same flow can support general personal safety. The system only needs to know that no response reached it; it does not determine what happened.

The goal is to shorten the time between a missed response and a person taking responsibility for arranging help, while preserving the wearer's independence, privacy, and control. This is a hackathon prototype, not a validated medical or emergency-response system. It does not detect drugging, intoxication, unconsciousness, or a medical condition.

## 2. Users and components

- **Wearer:** starts and manages sessions, confirms safety, requests help, chooses contacts and sharing permissions, and sets safety and duress PINs.
- **Trusted contact / guardian:** a permanent family member or caregiver who receives alerts and updates assistance status. Use “trusted contact” consistently in the interface.
- **Temporary helper:** authorized, consenting venue staff who accept coverage for a defined period. They are separate from the demo admin.
- **Demo admin:** a presenter who controls authorized demo scenarios from a separate iPhone app.

Build these components:

1. Wearer iPhone app for setup, session control, permissions, invitations, and status.
2. Companion Apple Watch app for prompts, responses, Help, haptics, and status.
3. Separate admin iPhone app for triggering, stopping, and resetting demo scenarios.
4. Backend, database, and persistent job worker for authoritative state, deadlines, access control, messaging, and escalation.
5. Phone-friendly helper enrollment and responder webpages. No app installation or conventional account login is required; access uses verified, scoped links.

## 3. MVP requirements

### Wearer iPhone app

- Configure chosen name, trusted contacts and escalation order, session duration or expected end, grace period, response window, and heartbeat-loss grace period.
- Start, extend, and end sessions. Show the backend-confirmed deadline, connection status, temporary coverage, and incident status. Require a usable trusted fallback before claiming assistance coverage is active.
- Set a safety PIN for explicit cancellation and a separate duress PIN. Entering the duress PIN looks like a normal cancellation locally but silently creates or preserves an alert.
- Choose what each contact or helper may see, including name, venue, location, contact information, and an optional short help card, such as where medication is kept or how to assist.
- Invite a temporary helper by QR code or link; show acceptance, expiry, and a revoke control.
- Send session heartbeats to the backend and track watch reachability. A connected phone must not imply that the wearer or watch has responded.
- Show configuration and actions as pending until the backend confirms them. Operating-system permission requests remain separate from sharing preferences.

### Apple Watch app

- Show one dominant **I'm okay** button, an accessible **Get help** button, readable status, and a visible countdown during a check-in. Keep configuration off the main screen.
- Prompt with a strong haptic and large text. Support safety confirmation through both the large button and native double tap on the supported demo watch.
- Use native double tap only for the visible safety-confirmation action in the MVP. Confirm actual device, OS, and accessibility-setting compatibility before relying on it. Custom wrist gestures are stretch work.
- **Get help** immediately requests assistance through the normal incident pipeline; it does not wait for a check-in. **I'm okay** never requests help.
- Display recognized input as pending until accepted by the backend. Give visual and haptic feedback, and show responder acknowledgment when available.
- A voluntary safety tap outside a pending check-in may update the last confirmation time but must not silently move the registered deadline.
- The watch captures input and displays state; it does not own escalation timers. The controlled demo assumes the watch app is open and connected. Background prompts and wrist-down behavior require separate validation.

### Demo admin iPhone app

- Clearly label **Demo mode**, identify the selected session, and show connection status.
- Trigger a real check-in or direct help incident through the shared backend, with short configurable demo timers.
- Show deadline, last response, delivery attempts, responder progress, and resolution.
- Stop an incident with an explicit operator-stop reason, cancel pending jobs, and update already-contacted demo responders without claiming the wearer is medically safe.
- Reset using a new demo-run identifier so old timers, invitations, and delayed responses cannot affect the next run.
- Authenticate and authorize commands for assigned demo sessions only. Demo administration does not grant ordinary helper access or control over unrelated sessions.

### Helper enrollment and responder webpages

- Enrollment shows the venue and coverage period, verifies possession of the invited phone number, and requires explicit acceptance. Use preapproved demo staff; phone verification alone does not prove employment or training.
- An unaccepted, expired, or revoked helper is never considered active coverage. A QR code alone must not expose private incident information.
- The SMS response link shows permitted identity, alert time and reason, last-known location or map if allowed, help card if provided, and a brief event timeline.
- Provide large actions: **Acknowledge**, **Decline**, **Arranging help**, and **Resolved**, with a short resolution outcome.
- Support both trusted contacts and temporary helpers on the responder page. Show each only the information the wearer has permitted.

## 4. Session timing and alert lifecycle

1. **Register:** the backend stores the session and its deadlines before clients show monitoring as active.
2. **Check-in:** for a planned outing, prompt at the expected end plus the configured grace period. The wearer then has a separate response window. Intermediate check-ins are optional stretch work.
3. **Safe response:** a timely backend-accepted response cancels that check-in's pending escalation. An intermediate check-in continues monitoring; a successful final check-in ends the activity session.
4. **Create incident:** an unanswered check-in, direct Help request, duress PIN, or loss of session heartbeats/watch reachability beyond its configured grace creates the assistance flow. Registered check-in deadlines remain valid regardless of connectivity.
5. **Route:** contact the accepted temporary helper first while coverage is valid, otherwise begin with trusted contacts in their configured order. Show this routing order clearly.
6. **Escalate:** failed submission, decline, or no acknowledgment within the configured window advances to the next eligible contact. Apply configured retries or another delivery channel when available.
7. **Follow up:** acknowledgment records who accepted and when. It does not mean help has arrived. Keep the incident open through assistance being arranged, with a follow-up deadline if progress stops. If nobody responds, keep it unresolved and show that no responder is confirmed.
8. **Late safety / false alarm:** a late **I'm okay** records self-reported safety, suppresses unsent stale escalation, and notifies already-contacted responders. Closing the incident requires explicit safety-PIN cancellation or responder resolution, with a recorded reason. Preserve its history; messages already sent cannot be recalled.
9. **Coverage handoff:** expiry or revocation removes helper access immediately and routes any unresolved incident to trusted contacts. Coverage ending never resolves an incident.

An extension replaces a deadline only after backend confirmation and invalidates old timer jobs. Ending monitoring stops future check-ins but does not silently close an open incident. The duress PIN must not actually cancel escalation or reveal the silent alert on the wearer's screen.

All timings are configurable. Suggested filming settings are a 15-second response window, 15-second acknowledgment window, and 30-second follow-up window. These are demo settings, not medically validated defaults.

## 5. Backend, reliability, and messaging

- The backend owns every deadline, state transition, permission check, escalation, and helper expiry. Use persistent jobs so registered deadlines survive phone/watch disconnection and worker restarts.
- Responses normally flow watch → iPhone → backend. A tested independent watch connection may also be used. No alert deadline may depend on a local phone or watch timer continuing to run.
- A disconnected watch cannot transmit a new SOS, confirm safety, or provide fresh location. Show offline commands as unconfirmed and fetch authoritative state after reconnection.
- Use backend timestamps, state revisions, request deduplication keys, and demo-run identifiers. Repeated taps, retries, or job execution must not create duplicate logical incidents or escalation steps.
- Resolve response-versus-timeout races against current backend state. Recheck incident state and permissions immediately before dispatch; cancel obsolete jobs after an accepted response, extension, cancellation, or reset.
- Track message states separately: queued, submitting, submitted, failed, and unknown. Claim delivered or read only when there is actual evidence. Submission to a messaging service does not prove human receipt.
- Implement one working SMS route first, behind a messaging adapter. A provider such as Twilio or a configured Mac Messages/Shortcuts relay is acceptable for the demo. Select and test the route early; additional channels and SMS-reply acknowledgment are stretch work.
- A Mac relay depends on a connected Mac and configured messaging setup. Surface failures and uncertain results; do not promise exactly-once external delivery. Keep messaging credentials out of clients and use designated demo recipients.

Suggested stack: SwiftUI apps in a shared Xcode workspace; a Node.js or Python API with a database such as Firebase or Supabase; React/Next.js for webpages; a map link or embedded map. Choose vendors based on team familiarity. The requirements do not depend on a particular backend or SMS vendor.

## 6. Minimum state and operations

Keep separate records for users/preferences, ordered contacts, sessions, check-ins, incidents, temporary coverage, delivery attempts, scheduled jobs, and an event history. Include actor, server time, result, revision, and demo-run identifier where relevant.

Do not represent the whole system with one alarm Boolean:

- Monitoring: inactive, registration pending, active, end pending, ended.
- Check-in: scheduled, awaiting response, confirmed, expired, cancelled.
- Incident: open or resolved, with separate responder progress and wearer safety report.
- Responder progress: unassigned, acknowledged, assistance arranged, resolved.
- Delivery and connectivity: independent of incident status.

Backend operations must cover configuration; session start/extend/end; safety confirmation, PIN cancellation, and Help/duress; heartbeats; helper invitation/acceptance/revocation; responder actions; current-state fetch; demo commands; and message-submission results. Authorize every operation. Verification and response tokens must be random, scoped, expiring, and revocable.

## 7. Privacy and accessibility

- Share location and personal details with responders only during an alert and within the wearer's permissions. Enrollment may show coverage terms without exposing private wearer details.
- Enforce expiry and revocation on the backend, including subsequent reads or actions from an already-open page. Explain that information already received cannot be remotely recalled.
- Label location as last known, with its timestamp. Denied or unavailable location must not block a permitted alert; use allowed venue/session information instead.
- Encrypt network traffic, restrict access by role, avoid sensitive diagnostic logs and private details in URLs, and separate demo records from ordinary data. Support clearing demo data; define production retention and automatic deletion before release.
- Use large touch targets, readable text, high contrast, accessible labels, and feedback beyond color or sound alone. Keep a button alternative to every gesture.
- Use consistent plain language and status colors: green safe, yellow awaiting response, red alert, blue responder acknowledged, gray resolved. Always include text labels.
- Validate gestures with intended users, including tremor and accidental confirmations. Team demonstrations alone do not establish accessibility or reliability.

## 8. Stretch and excluded scope

Build stretch features only after the complete MVP works:

- Intermediate check-ins, custom wrist gestures/calibration, gesture-based Help or session control, and a duress gesture.
- Background notifications, richer location updates, safe zones, medication reminders with a “taken” tap, and a user-declared offline window.
- Optional heart-rate-plus-movement or prolonged-stillness triggers that request a check-in; these require separate implementation and validation. Do not interpret vitals medically or misuse a workout session just to keep the app running.
- Additional message channels, SMS “OK” acknowledgment, richer activity history, and optional web-based wearer setup.
- A Gemini incident assistant for plain-language summaries and contact actions, and a permission-based read-only physician history view. AI must not diagnose or make emergency decisions.

Out of scope: real fall/unconsciousness/drugging detection, voice responses, arbitrary gesture training, continuous clinical sensor monitoring, medical interpretation of vitals, automatic emergency-service dispatch or real emergency calls in the demo, Bluetooth helper discovery, silent SMS from the phone, and a public network of unvetted helpers.

## 9. Acceptance checks and demo

The MVP is complete when the following work end to end on the actual demo devices and designated recipient numbers:

1. Start a session; phone, watch, admin, and backend agree on state and deadline.
2. Enroll a temporary helper, verify their number, accept coverage, and show the trusted fallback.
3. Trigger a labeled simulated event from the admin app. The real watch prompt appears, and both the button and native double tap can confirm safety without a stale alert being sent.
4. Leave a check-in unanswered. The backend creates one incident and a real alert reaches the helper. Distinguish observed receipt from submission status.
5. Ignore or decline the helper alert and verify escalation to the next trusted contact. Acknowledge, then separately show arranging help and resolution.
6. Disconnect the phone/watch after registering a deadline and verify backend escalation still runs. Separately exercise heartbeat loss. Offline commands must not claim success.
7. Enter the duress PIN: the wearer sees apparent cancellation while a contact receives the silent alert.
8. Send a late safety response or cancel a false alarm with the safety PIN. Contacted responders receive an update; obsolete escalation jobs do not fire.
9. Revoke or expire helper access while their page is open. Protected access stops and any unresolved incident passes to trusted contacts. Show different sharing permissions for helper and trusted contact.
10. Stop and reset through the admin app. Old timers and delayed responses cannot affect the next run. Exercise duplicate requests, a response/timeout race, failed message submission, and an unauthorized admin command.

Rehearse the core response, escalation, and reset paths repeatedly before recording. Keep a screen recording as backup. Say when an event is simulated, and include a short honesty table in the presentation:

| Category | What to report |
| --- | --- |
| Demonstrated | Only functions actually exercised: watch input, shared backend state, timers, message receipt, escalation, helper workflow, and privacy controls. |
| Simulated | Concerning event, falls or sensor changes, venue/staff setting, and wearer incapacity. |
| Assumed | Helpers are available and willing to respond; participating venues authorize staff. |
| Needs validation | Gesture reliability with Parkinson's symptoms, false alarms, background execution, battery use, delivery reliability, and real responder times. |

## 10. Build order and initial decisions

Confirm Apple Developer provisioning/push requirements, actual watch and phone models and OS versions, native double-tap support, the message route, and verified demo recipients before depending on them. Keep the primary pitch focused on Parkinson's while explaining the general safety use case.

Agree on state models and API operations first. Build the vertical path: admin trigger → watch prompt → accepted tap or timeout → real message. Then add native double tap, configuration/PINs, temporary helper enrollment, escalation, privacy/expiry, and reset. Finish with failure checks and rehearsal before stretch work.

Assign one owner to wearer iPhone/watch work and start that first because Xcode and device provisioning share the available Mac. Parallelize backend/messaging, web/helper workflow, and admin/demo work among the remaining teammates. Freeze the working demo early enough to rehearse it at least twice.
