# Android export

**Status: working.** `build/night-run.apk` builds, is signed, and verifies.

The toolchain below is installed on this Mac. These notes are here so it can
be reproduced on another machine, and so the choices are on the record.

## Installed

| | |
|---|---|
| JDK | 21.0.4 (Temurin) at `/Library/Java/JavaVirtualMachines/temurin-21.jdk` |
| Android SDK | `~/Library/Android/sdk` — platform-tools, build-tools 34.0.0, platforms;android-34 |
| Debug keystore | `~/Library/Android/debug.keystore` (alias `androiddebugkey`, pass `android`) |
| Godot templates | `~/Library/Application Support/Godot/export_templates/4.7.2.stable` |

JDK 21 is worth a note: Godot's docs call for JDK 17, but that requirement is
for the *Gradle* build path. This preset uses `use_gradle_build=false`, which
builds from Godot's prebuilt template and only needs `apksigner` from the SDK
build-tools — that runs fine on 21. If you later switch to a Gradle build (for
plugins, or a custom AndroidManifest), install JDK 17 then.

## Build it

```bash
godot --headless \
  --path game --export-debug "Android" ../build/night-run.apk
```

Install to a device with USB debugging on:

```bash
~/Library/Android/sdk/platform-tools/adb install -r build/night-run.apk
```

## Verified

```
apksigner verify --min-sdk-version 24   -> OK, CN=Android Debug
package                                  com.leap.nightrun, versionCode 1
application-label                        Night Run
native-code                              arm64-v8a, x86_64
min / target sdk                         24 / 36
game data + engine present               assets/.godot/imported/*, libgodot_android.so
```

Two things this caught that reading the config would not have:

- The exporter refuses without **ETC2/ASTC texture compression**, so
  `textures/vram_compression/import_etc2_astc=true` is now in project.godot.
- The first APK declared **portrait**. Godot's orientation enum is
  0 = landscape, 1 = portrait, 4 = sensor landscape — I had written 1 meaning
  "landscape", and the manifest duly said portrait for a side-scroller. It is
  4 now, so the phone can be held either way up.

## Reproducing the setup elsewhere

### 1. Export templates (~1 GB)

```bash
curl -L -o /tmp/godot_templates.tpz \
  https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
mkdir -p ~/Library/Application\ Support/Godot/export_templates/4.7.2.stable
unzip -j /tmp/godot_templates.tpz 'templates/*' \
  -d ~/Library/Application\ Support/Godot/export_templates/4.7.2.stable/
```

### 2. Android SDK command-line tools (~150 MB, then ~700 MB of packages)

No Android Studio needed — the command-line tools are enough.

```bash
mkdir -p ~/Library/Android/sdk/cmdline-tools
curl -L -o /tmp/cmdline-tools.zip \
  https://dl.google.com/android/repository/commandlinetools-mac-11076708_latest.zip
unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools-extract
mv /tmp/cmdline-tools-extract/cmdline-tools ~/Library/Android/sdk/cmdline-tools/latest

cd ~/Library/Android/sdk/cmdline-tools/latest/bin
yes | ./sdkmanager --licenses
./sdkmanager "platform-tools" "build-tools;34.0.0" "platforms;android-34"
```

The NDK is deliberately not in that list — it's only needed for Gradle builds.

### 3. Debug keystore

```bash
keytool -keyalg RSA -genkeypair -alias androiddebugkey \
  -keypass android -keystore ~/Library/Android/debug.keystore \
  -storepass android -dname "CN=Android Debug,O=Android,C=US" \
  -validity 9999 -deststoretype pkcs12
```

## Point Godot at them

In `~/Library/Application Support/Godot/editor_settings-4.7.tres`:

```
export/android/android_sdk_path = "~/Library/Android/sdk"
export/android/debug_keystore = "~/Library/Android/debug.keystore"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
```

## Build

```bash
mkdir -p build
godot --headless \
  --path game --export-debug "Android" ../build/night-run.apk
```

Install to a device with USB debugging on:

```bash
~/Library/Android/sdk/platform-tools/adb install -r build/night-run.apk
```

## Choices baked into the preset, and why

- **arm64-v8a + x86_64 only.** armeabi-v7a is 32-bit and effectively dead on
  anything sold in the last several years; x86_64 is there purely so the
  emulator works.
- **`immersive_mode = true`** — full screen, no system bars over the touch pads.
- **`support_small = false`** — the HUD and the touch pads need room; a watch-
  sized screen isn't a target.
- **`internet = false`** — no permission requested at all, since telemetry is
  disabled. Turn it on only if you deploy `backend/` and enable telemetry,
  because an internet permission on the store listing needs justifying.
- **`export_format = 0` (APK).** Fine for testing and sideloading. Google Play
  requires an AAB — switch to `1` when you're ready to publish, which also
  requires a real signing key rather than the debug one.

## Before it ships

- Test on a real device. I verified the layout in a 19.5:9 render, not on
  hardware — touch target sizes in particular need a thumb, not a measurement.
- The main menu's buttons are still sized for a mouse.
- A release build needs a real upload key, not the debug keystore above.
