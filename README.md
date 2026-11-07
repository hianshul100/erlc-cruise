# ERLC Cruise Control

A Windows cruise-control app for Emergency Response: Liberty County. It reads
a selected speedometer region with offline OCR and holds W below a chosen
speed. It releases W at the limit and lets the vehicle coast.

## Download

[Download the portable Windows app](https://github.com/hianshul100/erlc-cruise/releases/latest).
Run ERLC-Cruise-Control.exe, then follow steps 3 through 5 below.

## Run from source

1. Install [64-bit AutoHotkey v2](https://www.autohotkey.com/) on Windows 10 or 11.
2. Download and extract this repository, then run src/ERLCCruise.ahk.
3. Set the starting target speed in the General settings and save.
4. With Roblox focused, press **F5** and select the speedometer digits.
5. Click **Start** on the floating HUD to engage cruise.

## Floating HUD

The HUD starts in the top-right corner. Drag its background to move it. The
app remembers its position and keeps it visible when you switch apps.

- **Start** engages cruise while Roblox is focused. The button changes to **Stop**.
- **Stop** releases W and returns the button to **Start**.
- The red **×** stops cruise and hides the HUD. Use **Toggle HUD** in the system tray to reopen it.
- Switching away from Roblox turns cruise off. Click **Start** again after returning.

The target is a throttle cutoff. The vehicle can coast above it, for example
downhill. Configuration and logs are stored in %APPDATA%\ERLCCruise.

ERLC Cruise Control is an independent tool. See [LICENSE](./LICENSE).
