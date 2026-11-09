"use strict";

// ---------------------------------------------------------------------------
// HUD renderer.
//
// AHK pushes a status snapshot with PostWebMessageAsJson as
//   { type: "state", state: { ... } }
// and a field-visibility config with
//   { type: "config", fields: { ShowTarget, ShowSpeed, ... } }
// This script just paints the DOM.
// ---------------------------------------------------------------------------

const el = (id) => document.getElementById(id);

const COLORS = {
    off: "#6b6b6b",
    on: "#00e676",
    debug: "#ffd740",
    red: "#ff5252",
    white: "#ffffff",
    green: "#00e676",
    amber: "#ffd740",
    orange: "#ff9100",
    dim: "#9e9e9e",
    faint: "#6b6b6b",
};

function applyFields(fields) {
    if (!fields) return;
    const map = {
        ShowTarget: "target-block",
        ShowSpeed: "speed-block",
        ShowThrottle: "throttle-block",
        ShowBrake: "brake-block",
        ShowAccel: "accel-block",
        ShowAction: "action-block",
    };
    Object.keys(map).forEach((key) => {
        const node = el(map[key]);
        if (node) node.classList.toggle("hidden", !fields[key]);
    });
    reportHeight();
}

function reportHeight() {
    if (!(window.chrome && window.chrome.webview && typeof ahk !== "undefined" && typeof ahk.Resize === "function")) return;
    requestAnimationFrame(() => {
        const h = Math.ceil(document.querySelector(".hud").getBoundingClientRect().height);
        try { ahk.Resize(h); } catch { /* ignore */ }
    });
}

function render(state) {
    const navigation = el("navigation-readout");
    const hasNavigation = Boolean(state.navigation);
    if (navigation.hidden === hasNavigation) {
        navigation.hidden = !hasNavigation;
        reportHeight();
    }
    if (hasNavigation && navigation.textContent !== state.navigation) {
        navigation.textContent = state.navigation;
        navigation.title = state.navigation;
    }

    const mode = el("hud-mode");
    const modeChanged = mode.textContent !== state.mode;
    if (modeChanged) mode.textContent = state.mode;
    mode.disabled = !!state.active;
    const speedControls = el("speed-controls");
    const hideSpeed = state.mode === "Lane Assist Only";
    if (Boolean(speedControls.hidden) !== hideSpeed) {
        speedControls.hidden = hideSpeed;
        reportHeight();
    }
    reportHeight();

    const laneSetup = el("lane-setup");
    if (Boolean(laneSetup.hidden) === Boolean(state.laneNeedsRegion)) {
        laneSetup.hidden = !state.laneNeedsRegion;
        reportHeight();
    }

    const toggle = el("toggle-cruise");
    toggle.textContent = state.active ? "Stop" : "Start";
    toggle.setAttribute("aria-pressed", state.active ? "true" : "false");

    const status = el("status");
    status.title = state.laneBoundaries || "";
    const dot = el("dot");

    if (state.debug && !state.laneActive) {
        status.textContent = "DEBUG";
        status.style.color = COLORS.debug;
        dot.classList.remove("on");
    } else if (state.active) {
        status.textContent = state.laneActive ? (state.laneStatus === "Lane detected" ? state.laneName || state.laneStatus : state.laneStatus) : "ACTIVE";
        status.style.color = COLORS.on;
        dot.classList.add("on");
    } else {
        status.textContent = "READY";
        status.style.color = COLORS.dim;
        dot.classList.remove("on");
    }

    const limited = state.speedActive && Number.isFinite(state.effectiveTarget)
        && state.effectiveTarget < state.target;
    el("target").textContent = limited ? state.effectiveTarget + " bend" : state.target;

    const speedEl = el("speed");
    if (state.speed < 0) {
        speedEl.textContent = "--";
        speedEl.style.color = COLORS.faint;
    } else {
        speedEl.textContent = Math.round(state.speed);
        if (!state.speedActive) {
            speedEl.style.color = COLORS.white;
        } else {
            const diff = Math.abs(state.target - state.speed);
            speedEl.style.color = diff <= 2 ? COLORS.green : diff <= 6 ? COLORS.amber : COLORS.orange;
        }
    }

    const tPct = Math.round(state.duty * 100);
    el("throttle-pct").textContent = tPct + "%";
    el("throttle-fill").style.width = tPct + "%";

    const bPct = Math.round(state.brakeDuty * 100);
    el("brake-pct").textContent = bPct + "%";
    el("brake-fill").style.width = bPct + "%";

    const sign = state.accel >= 0 ? "+" : "";
    el("accel-block").textContent = "ACCEL  " + sign + (Math.round(state.accel * 10) / 10) + " mph/s";
    el("action-block").textContent = state.action || "";
}

if (window.chrome && window.chrome.webview) {
    window.chrome.webview.addEventListener("message", (event) => {
        let msg = event.data;
        if (typeof msg === "string") {
            try { msg = JSON.parse(msg); } catch { return; }
        }
        if (!msg) return;
        if (msg.type === "state") {
            if (msg.fields) applyFields(msg.fields);
            if (msg.state) render(msg.state);
        } else if (msg.type === "config") {
            applyFields(msg.fields);
        }
    });
    window.addEventListener("load", reportHeight);
}

el("toggle-cruise").addEventListener("click", () => {
    if (typeof ahk !== "undefined") ahk.ToggleCruise();
});
el("close-hud").addEventListener("click", () => {
    if (typeof ahk !== "undefined") ahk.CloseHud();
});

el("hud-mode").addEventListener("click", () => {
    if (typeof ahk !== "undefined") ahk.CycleMode();
});

el("lane-setup").addEventListener("click", async () => {
    if (typeof ahk !== "undefined") await ahk.LaneSetup();
});
