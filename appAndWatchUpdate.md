# Update Ripple on your iPhone and Apple Watch

Use these steps after saving your code changes. Running from Xcode installs the updated app over the existing copy and keeps its saved data when you use the same signing team and bundle IDs.

## 1. Connect your devices

1. Plug your **iPhone 15 Pro** into your Mac and unlock it. Tap **Trust** if asked.
2. Keep your paired **Apple Watch Series 9** nearby and unlocked, with Bluetooth and Wi-Fi enabled.
3. Keep your existing working network setup for Ripple's backend.

## 2. Open the configured Xcode project

1. In Finder, press **Command + Shift + G**.
2. Paste this path, press Return, and open the project in Xcode:

   ```text
   /tmp/ripple-device-hub/phone-install-stage/apps/Ripple.xcodeproj
   ```

3. Wait for Xcode to finish loading and resolving packages.

This local project already has your personal signing settings. Its source folders link to `/Users/juggin/Projects/htv11-winners`, so saved changes in that repository are picked up automatically.

## 3. Update and run the iPhone app

1. In Xcode's top toolbar, select the **RippleWearer** scheme.
2. Next to it, select your **physical iPhone 15 Pro** as the run destination.
3. Click the **Run triangle**, or press **Command + R**.
4. Wait for the build and installation to finish. Ripple should open on your iPhone.

## 4. Update and run the Watch app

1. Change the scheme to **RippleWatch**.
2. Select your **physical Apple Watch Series 9** as the run destination.
3. Press **Command + R** and wait for Ripple to open on the Watch. Watch installation can take longer than the phone installation.
4. If Xcode stopped the iPhone app when switching schemes, open Ripple again on your iPhone.

Run both schemes after changes so both devices receive the latest code. If you change the **Build** number under each target's **General** tab, use the same number for RippleWearer and RippleWatch.

## 5. Check that everything is connected

1. Leave Ripple open on both devices.
2. On the iPhone, check the **Connections** card: **Apple Watch: Connected**, **Watch settings: Up to date**, and **Backend: Online**.
3. If settings have not synced, open **Settings → Watch sync → Send to Watch again** in Ripple.

For the next update, save your changes and repeat sections 3–5.

## If something gets stuck

- **Device missing:** Open the run-destination menu and choose **Manage Devices…**. Check the device's connection status and follow any trust or Developer Mode prompts. Older Xcode versions use **Window → Devices and Simulators**.
- **Signing error:** In each target's **Signing & Capabilities**, keep automatic signing enabled and your existing personal team selected. Keep these bundle IDs: `com.justinmui.htv11.ripple.wearer` and `com.justinmui.htv11.ripple.wearer.watchkitapp`.
- **Backend unreachable:** Check that the existing Ripple backend is running and reachable from the iPhone. The last working server address was `http://172.20.10.2:8080` through the USB hotspot setup; it depends on that network being available. The Watch reaches the backend through the phone.
- **Project path missing:** The configured project lives in `/tmp`, which macOS may clear. Restore that local signing setup before using these steps again.

Keep the installed apps and existing pairing. Avoid **Set up again** in Ripple when updating, since it clears the phone's registration. Rebuilding does not require sending a test alert.

Apple's reference: [Run an app on a device](https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html).
