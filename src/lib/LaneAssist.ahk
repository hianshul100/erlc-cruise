; Nudges toward the lane when two successive road scans agree.
class LaneAssist {
    Active := false
    RequiresSpeed := false
    ResumeAt := 0
    LastDirection := ""
    HeldKey := ""
    ReleaseAt := 0

    __New(engine) {
        this.Engine := engine
        this.UpdateFn := this.Update.Bind(this)
        OnExit((*) => this.Stop())
    }

    Start(requiresSpeed) {
        InstallKeybdHook()
        this.RequiresSpeed := requiresSpeed
        this.ResumeAt := A_TickCount + 400
        this.Active := true
        SetTimer(this.UpdateFn, 20)
    }

    Stop() {
        this.Active := false
        SetTimer(this.UpdateFn, 0)
        this.ReleaseSteering()
        this.LastDirection := ""
    }

    ReleaseSteering() {
        if this.HeldKey = ""
            return
        Send("{" this.HeldKey " up}")
        this.HeldKey := ""
    }

    IsSteering() {
        return GetKeyState("a", "P") || GetKeyState("d", "P")
            || GetKeyState("Left", "P") || GetKeyState("Right", "P")
    }

    Update() {
        if !this.Active
            return
        if !GameWindow.IsActive() || (this.RequiresSpeed && !this.Engine.Active) {
            this.Stop()
            return
        }

        now := A_TickCount
        if this.IsSteering() {
            this.ReleaseSteering()
            this.LastDirection := ""
            this.ResumeAt := now + 400
            return
        }
        if this.HeldKey != "" && now >= this.ReleaseAt
            this.ReleaseSteering()
        if now < this.ResumeAt
            return

        hwnd := WinActive(GameWindow.WinTitle())
        if !hwnd
            return
        try WinGetClientPos(,, &width, &height, hwnd)
        catch
            return
        CoordMode("Pixel", "Client")
        direction := this.FindDirection(width, height)
        confirmed := direction != "" && direction = this.LastDirection
        this.LastDirection := direction
        this.ResumeAt := A_TickCount + 90

        Critical("On")
        if !confirmed || !this.Active || WinActive(GameWindow.WinTitle()) != hwnd
            || this.IsSteering() || (this.RequiresSpeed && !this.Engine.Active)
            return

        this.HeldKey := direction
        Send("{" direction " down}")
        this.ReleaseAt := A_TickCount + 35
        this.ResumeAt := A_TickCount + 350
        this.LastDirection := ""
    }

    FindDirection(width, height) {
        center := width // 2
        far := this.LaneEdges(width, Round(height * 0.64))
        near := this.LaneEdges(width, Round(height * 0.72))
        if !far || !near
            return ""
        if near.Left >= far.Left || near.Right <= far.Right
            return ""

        laneWidth := near.Right - near.Left
        if laneWidth < width * 0.12 || laneWidth > width * 0.65
            return ""
        if center - near.Left < laneWidth * 0.27 && center - far.Left < (far.Right - far.Left) * 0.38
            return "d"
        if near.Right - center < laneWidth * 0.27 && far.Right - center < (far.Right - far.Left) * 0.38
            return "a"
        return ""
    }

    LaneEdges(width, y) {
        center := width // 2
        try {
            if PixelSearch(&left, &unused, center - 1, y, Round(width * 0.12), y, 0xEEEEEE, 26)
                && PixelSearch(&right, &unused, center + 1, y, Round(width * 0.88), y, 0xEEEEEE, 26)
                return { Left: left, Right: right }
        } catch {
            return false
        }
        return false
    }
}
