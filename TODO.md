# Todo
- We will just let the shortcuts happen, not worth spending time fixing, ignore for now. Currently for the iphone app, when messaging a contact, it opens the shortcuts app and brings you to it asking for permission to run. Try to find a workaround (maybe via mac?)
- UI for App could use a redo, currently looks just like Apple's UI
- For morning: get ur gestures to work, currently watch app is not updating, wifi issue?
- Medication timing for smarter check ins. Wearer enters their med times on the iphone and check ins happen near when a dose usually wears off (the "off" period, when moving and using the phone is hardest). One "Took my meds" tap on the watch, a missed tap starts a gentle check in. No sensors needed so should be easy to build.
- Steps during a walk session to spot sudden stops. Read steps with CMPedometer, if steps stop suddenly for a few minutes start a check in. Catches a freeze or fall without claiming to detect one. Easy to demo by just standing still. Need to check if steps still update when the watch screen is off.
- Tremor and dyskinesia context. Apple Watch has a Movement Disorder API but it needs Apple's approval, so simulate it and put it on the honesty slide. Only use it as context in the alert like "tremor was high in the last hour", never as a trigger or a diagnosis.
- Smarter alert text. With the wearer's permission add one short context line, like "Last steps 4 min ago. Last meds 1:00 PM. Help card: I may look confused. Meds in left pocket." so the helper arrives knowing what to expect.
- Built for Parkinson's bodies. Touch and double tap first since voice can get soft, big targets and hold actions for tremor. Optional rhythmic haptic beat during a check in, rhythm cues are a known freezing strategy but frame it as comfort only.
- able to be used off line

- Multiple gestures
  - pinch
  - clench
  - double pinch
  - double clench
  - pinch + clench
  - double pinch + clench
  - clench + pinch
  - clench + double pinch
  - double clench + pinch
  - double clench + double pinch

```
Yes—replying by text is feasible, and we can do it without giving Ripple access to your inbox. For your current setup, an iPhone Shortcuts automation is the most practical approach.
I checked the code:
- [ShortcutSender.swift (line 5)](/Users/juggin/Projects/htv11-winners/apps/RippleWearer/ShortcutSender.swift:5) sends alerts through your existing Ripple Alert shortcut.
- [Engine+Web.swift (line 39)](/Users/juggin/Projects/htv11-winners/server/Sources/RippleEngine/Engine+Web.swift:39) records a contact’s acknowledgement when they use the link.
- [AlarmCoordinator.swift (line 372)](/Users/juggin/Projects/htv11-winners/RippleKit/Sources/RippleKit/AlarmCoordinator.swift:372) already handles displaying the responder and notifying other contacts. We could reuse that behavior for text replies.
Ripple cannot simply request permission to read your Messages inbox. Apple’s SMS-filter extension excludes saved contacts and iMessage; its separate carrier-messaging API requires becoming the default messaging app and has EU restrictions. Neither fits this feature. Apple message-filter documentation, carrier-messaging documentation.
The Shortcuts approach would work like this:
1. Ripple texts your contact: “Please check on Justin. Reply RIPPLE ACCEPT 4821 if you’re responding.”
2. An automation on your iPhone detects a message from that contact containing RIPPLE ACCEPT.
3. The shortcut passes the responder’s identity and alert code to a new Ripple action.
4. Ripple validates them against the active alert, then shows “Sam is responding” on your phone and Watch.
Apple supports message automations filtered by sender and phrase, including automatic execution. Your contact would just reply normally—no app or shortcut needed on their phone. Message triggers, automatic execution.
“On the way” could work too, but a distinct phrase plus an alert code helps prevent an unrelated conversation or delayed reply from acknowledging the wrong alert. We could keep the processing narrow so Ripple receives only the acknowledgement information.
The tradeoffs are manual automation setup on your phone and physical testing with the phone locked. It also depends on your phone functioning.
```

[Demo Photos]([url](https://drive.google.com/drive/folders/1HuXoaYTzwrxl_IqGnw3iEyiH_kPRZIj7?usp=drive_link))
