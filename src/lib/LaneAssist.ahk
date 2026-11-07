; Nudges toward the lane when two successive road scans agree.
class LaneAssist {
    Active := false
    Status := "Ready"
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
        this.Status := "Finding lanes"
        this.Active := true
        SetTimer(this.UpdateFn, 20)
    }

    Stop() {
        this.Active := false
        this.Status := "Ready"
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
            this.Status := "Manual steering"
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
        try WinGetClientPos(&screenX, &screenY, &width, &height, hwnd)
        catch
            return
        r := this.Region
        left := Round(width * r.X1 / 10000)
        right := Min(width - 1, Round(width * r.X2 / 10000))
        top := Round(height * r.Y1 / 10000)
        bottom := Min(height - 1, Round(height * r.Y2 / 10000))
        direction := this.FindDirection(screenX + left, screenY + top, right - left, bottom - top)
        confirmed := direction != "" && direction = this.LastDirection
        this.LastDirection := direction
        this.ResumeAt := A_TickCount + 90

        Critical("On")
        if !confirmed || !this.Active || WinActive(GameWindow.WinTitle()) != hwnd
            || this.IsSteering() || (this.RequiresSpeed && !this.Engine.Active)
            return

        this.Status := "Steer " StrUpper(direction)
        Logger.Action("Lane assist tapped " StrUpper(direction) ".")
        this.HeldKey := direction
        Send("{" direction " down}")
        this.ReleaseAt := A_TickCount + 35
        this.ResumeAt := A_TickCount + 350
        this.LastDirection := ""
    }

    FindDirection(x, y, width, height) {
        if width < 40 || height < 40 {
            this.Status := "Region too small"
            return ""
        }
        scale := Min(1, Max(40 / height, 360 / width))
        w := Ceil(width * scale)
        h := Ceil(height * scale)
        try {
            bitmap := OCR.CreateHBitmap(x, y, width, height, , scale)
            pixels := Buffer(w * h * 4, 0)
            info := Buffer(40, 0)
            NumPut("UInt", 40, "Int", w, "Int", -h, "UShort", 1, "UShort", 32, info)
            if !DllCall("gdi32\GetDIBits", "Ptr", bitmap.DC, "Ptr", bitmap.Ptr,
                "UInt", 0, "UInt", h, "Ptr", pixels, "Ptr", info, "UInt", 0, "Int")
                throw Error("Screen capture returned no rows")
        } catch {
            this.Status := "Road view unavailable"
            return ""
        }
        result := this.ScanRoad(pixels, w, h)
        this.Status := result.Status
        return result.Direction
    }

    ; Scan several rows so a gap in a dashed line does not reject the frame.
    ScanRoad(pixels, w, h) {
        center := w // 2
        pairs := 0, leftVotes := 0, rightVotes := 0
        for fraction in [0.18, 0.28, 0.38, 0.48, 0.58, 0.68, 0.78, 0.88] {
            row := Round((h - 1) * fraction) * w * 4
            left := this.FindMark(pixels, row, center - 1, 12, -1)
            right := this.FindMark(pixels, row, center + 1, w - 13, 1)
            if left < 0 || right < 0
                continue
            laneWidth := right - left
            if laneWidth < w * 0.16 || laneWidth > w * 0.96
                continue
            pairs++
            offset := ((left + right) / 2 - center) / laneWidth
            if offset > 0.14
                rightVotes++
            else if offset < -0.14
                leftVotes++
        }

        if pairs < 2
            return {Status: "Finding lanes", Direction: ""}
        if rightVotes >= 2 && rightVotes * 2 > pairs
            return {Status: "Near left line", Direction: "d"}
        if leftVotes >= 2 && leftVotes * 2 > pairs
            return {Status: "Near right line", Direction: "a"}
        return {Status: "Lane detected", Direction: ""}
    }

    ; A marking is a narrow bright stripe relative to the road around it.
    FindMark(pixels, row, start, limit, step) {
        x := start
        while (step > 0 ? x <= limit : x >= limit) {
            offset := row + x * 4
            mark := this.Luma(pixels, offset)
            for radius in [4, 8, 12] {
                left := this.Luma(pixels, offset - radius * 4)
                right := this.Luma(pixels, offset + radius * 4)
                if mark >= Max(left, right) + 17 && Abs(left - right) <= 40
                    return x
            }
            x += step
        }
        return -1
    }

    Luma(pixels, offset) {
        return (29 * NumGet(pixels, offset, "UChar")
            + 150 * NumGet(pixels, offset + 1, "UChar")
            + 77 * NumGet(pixels, offset + 2, "UChar")) >> 8
    }
}
