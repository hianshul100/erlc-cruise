# ERLC Cruise Control

A portable Windows app for Emergency Response: Liberty County with speed
maintenance and experimental lane assistance.

## Download

[Download the portable Windows app](https://github.com/hianshul100/erlc-cruise/releases/latest)
and run ERLC-Cruise-Control.exe. Windows 10 or 11 and WebView2 are required.
To run from source, use 64-bit [AutoHotkey v2](https://www.autohotkey.com/)
and open src/ERLCCruise.ahk.

## Modes

Click the mode label on the HUD to cycle through the three modes, then click
**Start** while Roblox is focused.

| Mode | Behavior |
| --- | --- |
| Maintain Speed | Uses throttle below the target and brief brake pulses when at least 3 mph above it. |
| Lane Assist Only | Nudges the steering near visible white lane markings. |
| Both | Runs speed maintenance and lane assistance together. |

For either speed mode, use **Settings → OCR & Region → Select Speedometer
Region**, or press **F5** in Roblox, and draw a box around the speed digits.
Set the target in **General**. Enable **Lock to current speed when enabling
cruise** to capture the speed at Start instead.

Lane assist uses a separate screen scan. Use a centered driving camera and a
road with visible white markings on both sides. It pauses while you steer
manually and waits briefly after you release the steering key. It can miss
markings or mistake bright objects for them.

Drag the HUD to move it. **Stop** releases the app's controls. The red **×**
also hides the HUD, and the system tray can bring it back. Switching away from
Roblox stops both controls. The speed band depends on OCR and vehicle response.

ERLC Cruise Control is an independent tool. See [LICENSE](./LICENSE).
