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

    ; Store normalized client coordinates, independent of the speedometer box.
    static SaveRegion(selection, x, y, width, height) {
        if selection.W < 100 || selection.H < 60 || selection.X < x || selection.Y < y
            || selection.X + selection.W > x + width || selection.Y + selection.H > y + height
            return false
        Config.Set("Lane", "Region", Format("{},{},{},{}",
            Round((selection.X - x) * 10000 / width), Round((selection.Y - y) * 10000 / height),
            Round((selection.X + selection.W - x) * 10000 / width),
            Round((selection.Y + selection.H - y) * 10000 / height)))
        return true
    }

    static ReadRegion() {
        value := Config.Get("Lane", "Region")
        if !RegExMatch(value, "^\d{1,5},\d{1,5},\d{1,5},\d{1,5}$")
            return false
        parts := StrSplit(value, ",")
        x1 := Integer(parts[1]), y1 := Integer(parts[2])
        x2 := Integer(parts[3]), y2 := Integer(parts[4])
        if x2 > 10000 || y2 > 10000 || x1 >= x2 || y1 >= y2
            return false
        return {X1: x1, Y1: y1, X2: x2, Y2: y2}
    }

    Start(requiresSpeed) {
        this.Region := LaneAssist.ReadRegion()
        if !this.Region
            return
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
        r := this.Region
        left := Round(width * r.X1 / 10000)
        right := Min(width - 1, Round(width * r.X2 / 10000))
        top := Round(height * r.Y1 / 10000)
        bottom := Min(height - 1, Round(height * r.Y2 / 10000))
        direction := this.FindDirection(left, top, right, bottom)
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

    FindDirection(left, top, right, bottom) {
        width := right - left
        height := bottom - top
        if width < 40 || height < 25
            return ""
        center := left + width // 2
        far := this.LaneEdges(left, center, right, top + Round(height * 0.30))
        near := this.LaneEdges(left, center, right, top + Round(height * 0.78))
        if !far || !near
            return ""
        if near.Left >= far.Left || near.Right <= far.Right
            return ""

        laneWidth := near.Right - near.Left
        if laneWidth < width * 0.12 || laneWidth > width * 0.98
            return ""
        if center - near.Left < laneWidth * 0.27 && center - far.Left < (far.Right - far.Left) * 0.38
            return "d"
        if near.Right - center < laneWidth * 0.27 && far.Right - center < (far.Right - far.Left) * 0.38
            return "a"
        return ""
    }

    LaneEdges(leftBound, center, rightBound, y) {
        try {
            if PixelSearch(&left, &unused, center - 1, y, leftBound, y, 0xEEEEEE, 26)
                && PixelSearch(&right, &unused, center + 1, y, rightBound, y, 0xEEEEEE, 26)
                return { Left: left, Right: right }
        } catch {
            return false
        }
        return false
    }
}
