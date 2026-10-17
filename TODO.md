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

[Demo Photos]([url](https://drive.google.com/drive/folders/1HuXoaYTzwrxl_IqGnw3iEyiH_kPRZIj7?usp=drive_link))
