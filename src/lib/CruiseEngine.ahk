; Maintains the target speed using throttle and brief brake pulses.

class CruiseEngine {
    Active := false
    Starting := false
    RawSpeed := -1
    LaneGuidance := false
    LaneLimit := -1
    LaneReadAt := 0
    Duty := 0
    BrakeUntil := 0
    NextBrakeAt := 0
    Debug := false
    Target := 40
    LastAction := "Ready"

    ; Last status snapshot, consumed by the HUD / UI.
    Status := ""

    __New() {
        this.Reader := SpeedReader()
        this.Input := InputDriver()
        this.Target := Config.GetInt("General", "StartTarget")
        this.TickFn := this.Tick.Bind(this)
        this.ThrottleFn := this.UpdateThrottle.Bind(this)
        this.Note := ""
        this.BuildStatus()
    }

    ; Refreshes the target displayed while cruise is off.
    Reload() {
        if !this.Active
            this.Target := Config.GetInt("General", "StartTarget")
    }

    ; --- timers -------------------------------------------------------------

    StartTimers() {
        SetTimer(this.TickFn, Config.GetInt("General", "UpdateInterval"))
        SetTimer(this.ThrottleFn, 20)
    }

    StopTimers() {
        SetTimer(this.TickFn, 0)
        SetTimer(this.ThrottleFn, 0)
    }

    ; --- public controls ----------------------------------------------------

    Toggle() {
        if this.Active
            return this.Stop("Toggled off")

        if !GameWindow.IsActive() {
            App.Notify("ERLC Cruise Control", "Focus Roblox before clicking Start.")
            return
        }
        if this.Starting || this.Debug
            return

        this.Starting := true
        try {
            this.Start()
        } finally {
            this.Starting := false
        }
    }

    Start() {
        read := this.Reader.ReadOnce()
        if !GameWindow.IsActive() || !gHud.Visible
            return
        if (read.Speed < 0) {
            this.LastAction := "Can't read speed"
            Logger.Warn("Start failed: " read.Raw)
            App.Notify("ERLC Cruise Control", "Could not read the speedometer. Select Speedometer Region with F5.")
            this.BuildStatus(read.Raw)
            return
        }

        if Config.GetBool("General", "LockCurrentSpeedOnToggle")
            this.Target := Config.GetBool("General", "LockCurrentSpeedOnToggle")
            ? read.Speed : this.Target

        this.Reader.Reset(read.Speed)
        this.RawSpeed := read.Speed
        this.Active := true
        this.LastAction := "Cruise ON, target " this.Target
        Logger.Action("Cruise ON (target " this.Target ", speed " read.Speed ").")
        this.BuildStatus()
    }

    Stop(reason := "Cruise off") {
        this.Active := false
        this.SetLaneGuidance(false)
        this.RawSpeed := -1
        this.Duty := 0
        this.Input.ReleaseAll()
        this.LastAction := reason
        Logger.Action("Cruise OFF (" reason ").")
        this.BuildStatus()
    }

    Adjust(delta) {
        if this.Debug {
            this.LastAction := "Debug: target change ignored"
            this.BuildStatus()
            return
        }
        this.Target := Max(0, this.Target + delta)
        this.LastAction := "Target " (delta > 0 ? "increased" : "decreased") " to " this.Target
        Logger.Action("Target adjusted to " this.Target ".")
        this.BuildStatus()
    }

    IncrementUp() {
        this.Adjust(Config.GetInt("General", "Increment"))
    }

    IncrementDown() {
        this.Adjust(-Config.GetInt("General", "Increment"))
    }

    ToggleDebug() {
        this.Debug := !this.Debug
        if this.Debug {
            this.Input.ReleaseAll()
        }
        this.LastAction := this.Debug ? "Debug on (no keys pressed)" : "Debug off"
        Logger.Action(this.LastAction)
        this.BuildStatus()
    }

    ; Called by the ~s handler: a real player brake press cancels cruise.
    OnBrakePressed() {
        if (this.Active && !this.Input.Sheld && !this.Input.InBrakeGuard())
            this.Stop("Braked")
    }

    ; --- loop ---------------------------------------------------------------

    Tick() {
        if !GameWindow.IsActive()
            return
        read := this.Reader.ReadOnce()
        state := this.Reader.Update(read.Speed, read.Raw)

        this.RawSpeed := (state = "error" || state = "jumped") ? -1 : read.Speed
        if this.RawSpeed < 0
            this.Input.ReleaseThrottle()

        if (state = "error") {
            if (this.Active && this.Reader.SecondsSinceRead() > 1.5)
                this.Stop("Lost speed reading")
            this.BuildStatus(read.Raw)
            return
        }
        if (state = "jumped") {
            this.BuildStatus("ignored jump to " read.Speed)
            return
        }

        this.BuildStatus("read " read.Speed)
    }

    SetLaneGuidance(enabled) {
        if enabled = this.LaneGuidance
            return
        this.LaneGuidance := enabled
        this.LaneLimit := -1
        this.LaneReadAt := 0
    }

    ResetLaneReading() {
        this.LaneLimit := -1
        this.LaneReadAt := 0
    }

    UpdateLaneGuidance(curvature) {
        now := A_TickCount
        desired := CruiseEngine.BendLimit(this.Target, curvature)
        if this.LaneLimit < 0 || !this.HasFreshLane()
            this.LaneLimit := desired
        else
            this.LaneLimit := Min(desired, this.LaneLimit + (now - this.LaneReadAt) * 0.012)
        this.LaneReadAt := now
    }

    HasFreshLane() => this.LaneReadAt > 0 && A_TickCount - this.LaneReadAt <= 300

    EffectiveTarget() => this.LaneGuidance && this.HasFreshLane()
        ? Min(this.Target, this.LaneLimit) : this.Target

    static BendLimit(target, curvature) {
        severity := Min(1, Max(0, (curvature - 0.08) / 0.45))
        return Min(target, Max(22, target * (1 - 0.55 * severity)))
    }

    ; Release both keys when the game or a fresh speed reading is unavailable.
    UpdateThrottle() {
        Critical("On")
        if !this.Active
            return
        if !GameWindow.IsActive() {
            this.Stop("Roblox lost focus")
            return
        }

        if this.Debug || this.RawSpeed < 0 || this.Reader.SecondsSinceRead() > 0.5
            || (this.LaneGuidance && !this.HasFreshLane()) {
            this.Duty := 0
            this.BrakeUntil := 0
            this.Input.ReleaseAll()
            return
        }

        now := A_TickCount
        target := this.EffectiveTarget()
        curveLimited := target < this.Target - 1
        overshoot := this.RawSpeed - target
        if overshoot <= 0
            this.BrakeUntil := 0
        if overshoot >= (curveLimited ? 2 : 3) && now >= this.NextBrakeAt {
            this.BrakeUntil := now + (curveLimited ? Min(95, 55 + overshoot * 2) : 60)
            this.NextBrakeAt := now + 350
        }

        if now < this.BrakeUntil {
            this.Duty := 0
            this.Input.ReleaseThrottle()
            this.Input.HoldBrake()
            return
        }

        this.Input.ReleaseBrake()
        ; Ease off before reaching the target when speed is already rising.
        predictedSpeed := this.RawSpeed + Max(0, this.Reader.Accel) * 0.25
        throttle := overshoot < 0
            && (overshoot <= -2 || predictedSpeed < target)
        this.Duty := throttle ? (this.LaneGuidance ? CruiseEngine.ThrottleDuty(-overshoot, curveLimited) : 1) : 0
        if this.Duty >= 1 || (this.Duty > 0 && Mod(now, 160) < this.Duty * 160)
            this.Input.HoldThrottle()
        else
            this.Input.ReleaseThrottle()
    }

    static ThrottleDuty(headroom, curveLimited) {
        if curveLimited
            return Min(0.60, Max(0.25, headroom / 11))
        return headroom >= 5 ? 1 : Max(0.25, headroom / 5)
    }

    ; --- status -------------------------------------------------------------

    BuildStatus(note?) {
        if IsSet(note)
            this.Note := note
        if !this.HasOwnProp("Note")
            this.Note := ""

        this.Status := {
            active: this.Active,
            debug: this.Debug,
            target: this.Target,
            speed: this.Reader.LastSpeed,
            accel: this.Reader.Accel,
            duty: this.Duty,
            brakeDuty: this.Input.BrakeHeld ? 1 : 0,
            action: this.LastAction,
            note: this.Note,
            regionSet: Config.HasRegion()
        }
    }
}
