; Reads the speedometer and holds W while cruise is active below the limit.

class CruiseEngine {
    Active := false
    Starting := false
    RawSpeed := -1
    Duty := 0
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

    ; Re-reads all tuning from Config and applies live changes.
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
            App.Notify("ERLC Cruise Control", "Could not read the speedometer. Select the speed digits with F5.")
            this.BuildStatus(read.Raw)
            return
        }

        if Config.GetBool("General", "LockCurrentSpeedOnToggle")
            this.Target := read.Speed

        this.Reader.Reset(read.Speed)
        this.RawSpeed := read.Speed
        this.Active := true
        this.LastAction := "Cruise ON, target " this.Target
        Logger.Action("Cruise ON (target " this.Target ", speed " read.Speed ").")
        this.BuildStatus()
    }

    Stop(reason := "Cruise off") {
        this.Active := false
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

    ; Release W if Roblox loses focus or the reading is no longer usable.
    UpdateThrottle() {
        Critical("On")
        if !this.Active
            return
        if !GameWindow.IsActive() {
            this.Stop("Roblox lost focus")
            return
        }

        throttle := !this.Debug && this.RawSpeed >= 0 && this.RawSpeed < this.Target
            && this.Reader.SecondsSinceRead() <= 0.5
        this.Duty := throttle ? 1 : 0
        if throttle
            this.Input.HoldThrottle()
        else
            this.Input.ReleaseThrottle()
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
            brakeDuty: 0,
            action: this.LastAction,
            note: this.Note,
            regionSet: Config.HasRegion()
        }
    }
}
