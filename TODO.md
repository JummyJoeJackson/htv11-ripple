# Todo
- Voice phrase to dismiss is sketchy on the watch. Need to press a microphone button, hopefully there is a way to just turn on the microphone when an alert begins.
  - **Done, needs testing on the Watch.** The mic turns on by itself during any alarm and the iPhone recognizes the speech (watchOS has no speech recognition). Default phrase is now "I am currently fine". The mic button is only a fallback.
- Can’t hold down green button for 2 seconds for duress call
  - **By design.** Green is monitoring with no alarm open, so holding asks "Stop monitoring?". Duress is the hold on yellow, red or blue. To ask for help from green, swipe up twice. If the hold fails during an alarm too, that's a bug.
- We will just let the shortcuts happen, not worth spending time fixing, ignore for now. Currently for the iphone app, when messaging a contact, it opens the shortcuts app and brings you to it asking for permission to run. Try to find a workaround (maybe via mac?)
- UI for App logo for apple watch and iphone would be nice, currently just blank
  - **Done.** Ripple icons for the iPhone, Watch and admin app (orange, so it's easy to tell apart).
- UI for App could use a redo, currently looks just like Apple's UI
- Not too sure why but nearing the end of the countdown, the watch usually disconnects. Is there a reason for this? Making too many requests?
  - **Likely cause:** the screen dims, watchOS suspends the app, and the iPhone can't reach it. **Fixed, needs testing:** while monitoring, the Watch app now keeps running with the screen off (a mindfulness extended runtime session, up to 1 hour; it restarts the next time the app is in front).
- For morning: get ur gestures to work, currently watch app is not updating, wifi issue?
- Medication timing for smarter check ins. Wearer enters their med times on the iphone and check ins happen near when a dose usually wears off (the "off" period, when moving and using the phone is hardest). One "Took my meds" tap on the watch, a missed tap starts a gentle check in. No sensors needed so should be easy to build.
- Steps during a walk session to spot sudden stops. Read steps with CMPedometer, if steps stop suddenly for a few minutes start a check in. Catches a freeze or fall without claiming to detect one. Easy to demo by just standing still. Need to check if steps still update when the watch screen is off.
- Tremor and dyskinesia context. Apple Watch has a Movement Disorder API but it needs Apple's approval, so simulate it and put it on the honesty slide. Only use it as context in the alert like "tremor was high in the last hour", never as a trigger or a diagnosis.
- Smarter alert text. With the wearer's permission add one short context line, like "Last steps 4 min ago. Last meds 1:00 PM. Help card: I may look confused. Meds in left pocket." so the helper arrives knowing what to expect.
- Built for Parkinson's bodies. Touch and double tap first since voice can get soft, big targets and hold actions for tremor. Optional rhythmic haptic beat during a check in, rhythm cues are a known freezing strategy but frame it as comfort only.

[Demo Photos]([url](https://drive.google.com/drive/folders/1HuXoaYTzwrxl_IqGnw3iEyiH_kPRZIj7?usp=drive_link))
