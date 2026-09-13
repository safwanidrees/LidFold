<div align="center">

# LidFold

**The screen bends. Nothing underneath moves.**

A tiny macOS menu bar app for MacBooks with a lid angle sensor. As you
close the lid, the display appears to hinge forward over a desktop that
never actually moves — blurring and darkening the further it swings,
tracking the real hinge angle in real time. Open the lid back up and it
sharpens again.

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue?style=for-the-badge)](#requirements)

[![Download for macOS](https://img.shields.io/badge/Download-macOS-000000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/safwanidrees/LidFold/releases/latest/download/LidFold.dmg)

_(Or build it yourself from source — see below.)_

</div>

---

## Requirements

- macOS 14 or later
- A MacBook with a lid angle sensor: MacBook Air (M2 and later), 14/16-inch
  MacBook Pro (2021 and later), or the 2019 16-inch MacBook Pro
- Screen Recording permission, so it can see the desktop to fold it —
  nothing is ever stored or sent anywhere

## Install

1. Download **[LidFold.dmg](https://github.com/safwanidrees/LidFold/releases/latest)**
   from the latest release.
2. Open it and drag **LidFold** into **Applications**.
3. Launch it. Since it isn't notarized by Apple, the first launch needs
   one extra step: right-click the app → **Open** → **Open** again (or
   allow it under System Settings → Privacy & Security if macOS blocks it).
4. Grant Screen Recording when prompted, then quit and reopen the app once
   — Screen Recording specifically requires a fresh launch to take effect.
5. Close the lid slowly to see it. No supported Mac handy? Use the menu
   bar's **Preview Fold** instead.

## What it does

- **Enabled** — turn the fold on or off.
- **Preview Fold** — plays one close-and-reopen without touching the lid.
- **Starts at / Frost / Darkness** — three sliders, live, right in the
  menu: the hinge angle the fold triggers at, how much it blurs, and how
  dark the far edge goes.
- **Launch at Login**.
- The menu bar icon itself tracks the live hinge angle, tilting closed as
  you close the lid.

That's the whole app — no settings window, no presets, no background
services beyond watching the sensor.

## Build from source

Requires Xcode 16+ (Swift 6 toolchain) on macOS.

```sh
git clone https://github.com/safwanidrees/LidFold.git
cd LidFold
Scripts/build.sh --run     # release build, signed, launched
swift test                 # unit tests for the geometry and state machine
```

`Scripts/build.sh` produces `build/LidFold.app`, signed with a local
"Apple Development" identity from your keychain rather than ad-hoc. That
matters for Screen Recording specifically: macOS ties that grant to the
signer's Team ID, and an ad-hoc signature has none, so every rebuild would
look like a new app and silently lose the permission you already granted.
A real identity keeps the grant across rebuilds. Run
`security find-identity -v -p codesigning` to see what's on your Mac, and
override with `SIGN_IDENTITY="..."` if you want to use a different one (or
`SIGN_IDENTITY="-"` for plain ad-hoc signing).

### Packaging a release

```sh
Scripts/package-dmg.sh
```

Builds and packages `dist/LidFold.dmg`. To publish a new version: bump
`CFBundleShortVersionString` in `Resources/Info.plist`, run the script
above, then draft a GitHub release tagged `vX.Y.Z` and attach
`dist/LidFold.dmg` — the filename has to stay exactly `LidFold.dmg` for
the download button at the top of this page to keep working.

## How it's put together

A plain Swift package, no external dependencies, four small targets:

| Target          | What                                                                                          |
| --------------- | --------------------------------------------------------------------------------------------- |
| `LidFoldModel`  | Geometry, curve, spring, angle tracking, the fold state machine. Pure functions, unit tested. |
| `LidFoldSensor` | Reads the hinge angle from the built-in sensor over IOKit HID.                                |
| `LidFoldRender` | The Metal shader that draws the fold on a captured screenshot.                                |
| `LidFold`       | The app itself, in MVVM layers — see below.                                                   |

Inside `LidFold`:

| Folder       | What                                                                                                                                                           |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Model/`     | `AppPreferences` — the settings that persist between launches.                                                                                                 |
| `ViewModel/` | `FoldViewModel` runs the fold end to end; `StatusMenuViewModel` and `OnboardingViewModel` expose the observable state and commands their views bind to.        |
| `View/`      | The menu bar (`StatusBarView`, `MenuBarIcon`, `MenuSliderControl`), the onboarding screen, and the fold's overlay window (`FoldOverlayWindow`).                |
| `Services/`  | Screen capture, the hinge-angle poller, launch-at-login, permissions, and other system integration — consumed by the view models, never by the views directly. |

### The illusion

The hinge runs along `x`; `y` is up; `z` points at the viewer. The moment
the fold triggers, the current desktop is treated as a fixed plane sitting
in space. As the lid keeps closing, each point on the glass shows whatever
a stationary eye would see of that plane by looking _through_ the tilting
glass — trace a ray from the eye through every corner of the plane, find
where it crosses the glass, and warp the picture onto that quadrilateral
with a homography. At the trigger angle the quadrilateral matches the
screen exactly, so nothing visibly snaps into place when the fold begins.

Because the glass tilts toward the eye as it closes, it covers a shrinking
slice of that fixed plane — the far edge climbs above the top of the glass
and the sides pull inward, the same foreshortening any flat surface shows
as it turns away from a viewer. That's the whole trick: one plane held
fixed, one pane of glass swinging in front of it.

### The look

One full-screen Metal pass. The captured screenshot sits on a black margin
inside a mipmapped texture with a Gaussian pyramid built over it. Per
pixel: trace back into the source picture through the inverse homography,
then scale both blur radius and darkening by distance from the hinge, so
the top blurs away first while the area nearest the hinge stays sharp
longest.

Motion is never stepped: the sensor is polled quickly only when something
is about to happen (closing past the arming point, or already folding),
and a critically damped spring smooths its output up to display refresh
rate, so a ~10 Hz sensor reading still produces 60/120 Hz motion. Opening
plays the identical curve backward from wherever the hinge currently sits.
The three menu sliders adjust `FoldAppearanceModel`; everything else (span,
perspective depth, eye distance) is a fixed constant in
`LidFoldModel/FoldAppearance.swift`.

## Limitations

- Built-in display only; external-only (clamshell) setups get no effect.
- Three tunable knobs in the menu; the rest of the look is fixed (edit
  `FoldAppearance.swift` and rebuild for anything deeper).
- No self-update mechanism — download or build the new version to update.
- Signed with a free personal "Apple Development" identity, not a paid
  Developer ID, and not notarized — macOS Gatekeeper will warn on first
  launch (the right-click → Open, or System Settings → Privacy & Security
  → Open Anyway, step above is expected, not a sign anything's wrong).

## License

MIT — see [LICENSE](LICENSE).
