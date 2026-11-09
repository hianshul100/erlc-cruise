# ERLC Cruise Control by Wayne_Osborn

A portable Windows app for Emergency Response: Liberty County with speed
maintenance and experimental lane assistance.

## Download

[Download the portable Windows app](https://github.com/hianshul100/erlc-cruise/releases/latest)
and run ERLC-Cruise-Control.exe. To update, quit the app and replace that same file. Windows 10 or 11 and WebView2 are required.
To run from source, use 64-bit [AutoHotkey v2](https://www.autohotkey.com/)
and open src/ERLCCruise.ahk.

## Modes

Click the mode label on the HUD to cycle through the three modes, then click
**Start** while Roblox is focused.

| Mode | Behavior |
| --- | --- |
| Maintain Speed | Uses throttle below the target and brief brake pulses when at least 3 mph above it. |
| Lane Assist Only | Nudges the steering near visible white lane markings. |
| Both | Runs both controls and lowers the speed target on clearly detected bends. It coasts when lane tracking is lost. |

For either speed mode, use **Settings → Regions & OCR → Select Speedometer
Region**, or press **F5** in Roblox, and draw a box around the speed digits.
Set the target in **General**. Enable **Lock to current speed when enabling
cruise** to capture the speed at Start instead.

For either lane mode, open **Settings → Regions & OCR → Select Lane Region**.
Use a centered driving camera and box the road ahead so both white lane
markings are visible inside the box. The box is saved separately from the
speedometer and follows the Roblox window. It pauses while you steer
manually and waits briefly after you release the steering key. It can miss
markings or mistake bright objects for them.

Drag the HUD to move it. Saving Settings shows the HUD and keeps it on-screen. **Stop** releases the app's controls. The red **×**
also hides the HUD, and the system tray can bring it back. Switching away from
Roblox stops both controls. The speed band depends on OCR and vehicle response.

ERLC Cruise Control is an independent tool. See [LICENSE](./LICENSE).

The HUD shows **Select Lane Region** if no lane box is saved. While active it
shows whether it is looking for markings, has detected the lane, or has tapped
A or D.

Steering looks ahead along lane markings and varies the duration of its
corrections. It can briefly bridge a missing dashed marking using the last
reliable lane and reduces steering strength while doing so. Keep the near road and the visible bend inside the lane region.
Take over when markings leave the selected view or at abrupt turns.

## API navigation

Open **Settings → Navigation** and click **Connect API**. Enter your ER:LC
private-server key in the masked prompt. If several players have location
data, choose a map location from the list.
The key stays in memory for this session and goes only to the official API.
The API pack and a server key are required. No account or Discord login is used.

The HUD shows your street and postal when available. To save a path, click
**Record Route**, drive it, then choose **Save Recording**. Select the saved
route and click **Follow Route** for compass directions to its next waypoint.
Recordings are stored locally. Their guidance follows saved waypoints.

### Built-in road routing

The internal graph traces major corridors from the official ER:LC fall map.
Connect the API and select your live position. Stop at a listed intersection
and click **Set First Landmark**. Repeat at a distant listed intersection
for **Set Second Landmark**. Then choose a destination and click **Route to
Intersection**. Calibration is saved locally and requires no recorded drive.

Coverage is limited to traced roads and intersections. Routes provide HUD
directions, with no steering or throttle commands from navigation.
Map source: https://apidocs.erlc.gg/official-map-images

### Highway look-ahead

After calibrating the map and connecting the API, the app can recognize
Highway 2 and Highway 55 from the tracked position and direction of travel.
No destination is required. The HUD names the highway and upcoming bend.
Both mode can slow early for a mapped bend when the screen also shows a lane.
A mapped bend only strengthens steering when the screen agrees on direction.
The app follows the current highway and leaves exit choices to the driver.

### Tilted camera

The tilted profile is on by default for a behind-the-car view pitched down
roughly 20–45°. It samples more of the road above the speedometer and
accounts for the perspective narrowing on straight roads. In **Regions &
OCR**, set **Car center in lane box (%)** to where the rear center of the
car appears horizontally within the selected road box. Use 50 for a
centered box. Clear **Tilted camera** to use the original scan profile.

Lane assist waits for a consistent lane before sending inputs. The tilted
profile can pair the solid yellow median edge with white lane dividers.
In Both mode, throttle waits for lane acquisition and is pulsed near the
target or through a bend.
