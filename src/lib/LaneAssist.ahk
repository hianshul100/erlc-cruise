; Tracks the lane ahead and applies bounded steering pulses.
class LaneAssist {
    Active := false
    Status := "Ready"
    RequiresSpeed := false
    ResumeAt := 0
    LastDirection := ""
    SmoothedDemand := 0
    NextPulseAt := 0
    TrustedAt := 0
    TrustedRows := Map()
    ScanWidth := 0
    ScanHeight := 0
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
        this.NextPulseAt := 0
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
        this.SmoothedDemand := 0
        this.TrustedRows.Clear()
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
            this.SmoothedDemand := 0
            this.TrustedRows.Clear()
            this.ResumeAt := now + 400
            return
        }
        if this.HeldKey != "" && now >= this.ReleaseAt
            this.ReleaseSteering()
        if this.HeldKey != "" || now < this.ResumeAt
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
        scan := this.FindDirection(screenX + left, screenY + top, right - left, bottom - top)
        this.ResumeAt := A_TickCount + 50

        Critical("On")
        if !this.Active || WinActive(GameWindow.WinTitle()) != hwnd
            || this.IsSteering() || (this.RequiresSpeed && !this.Engine.Active)
            return
        if !scan || scan.Direction = "" {
            this.LastDirection := ""
            this.SmoothedDemand := 0
            return
        }
        if scan.Direction != this.LastDirection {
            this.LastDirection := scan.Direction
            this.SmoothedDemand := scan.Demand
            return
        }
        this.SmoothedDemand += (scan.Demand - this.SmoothedDemand) * 0.45
        if A_TickCount < this.NextPulseAt
            return

        direction := scan.Direction
        duration := LaneAssist.PulseDuration(this.SmoothedDemand)
        if scan.Estimated
            duration := Min(duration, 65)
        this.HeldKey := direction
        Send("{" direction " down}")
        this.ReleaseAt := A_TickCount + duration
        this.NextPulseAt := this.ReleaseAt + (scan.Estimated ? 85 : 45)
        this.Status := "Steer " StrUpper(direction)
        Logger.Action(Format("Lane assist steered {} for {} ms.", StrUpper(direction), duration))
    }

    static PulseDuration(demand) => Round(Min(115, Max(32, 20 + Abs(demand) * 230)))

    FindDirection(x, y, width, height) {
        if width < 40 || height < 40 {
            this.Status := "Region too small"
            return false
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
            return false
        }
        result := this.ScanRoad(pixels, w, h)
        this.Status := result.Status
        return result
    }

    ; Follow lane centers from the foreground into the distance. The search
    ; follows the previous pair so both markings can move to one side in a bend.
    ScanRoad(pixels, w, h) {
        if w != this.ScanWidth || h != this.ScanHeight {
            this.TrustedRows.Clear()
            this.ScanWidth := w
            this.ScanHeight := h
        }

        anchor := w / 2
        points := []
        measured := Map()
        searchCenter := anchor
        useHistory := A_TickCount - this.TrustedAt <= 240
        for index, fraction in [0.88, 0.78, 0.68, 0.58, 0.48, 0.38, 0.28, 0.18] {
            row := Round((h - 1) * fraction) * w * 4
            prior := useHistory ? this.TrustedRows.Get(index, false) : false
            split := Min(w - 14, Max(13, Round(searchCenter)))
            left := this.FindMark(pixels, row, split - 1, 12, -1)
            right := this.FindMark(pixels, row, split + 1, w - 13, 1)
            estimated := left < 0 || right < 0
            if estimated {
                if !prior || (left < 0 && right < 0)
                    continue
                ; Bridge a dashed marking only with a recent, matching edge.
                if left < 0 && Abs(right - prior.Right) <= prior.Width * 0.22
                    left := right - prior.Width
                else if right < 0 && Abs(left - prior.Left) <= prior.Width * 0.22
                    right := left + prior.Width
                else
                    continue
            }
            laneWidth := right - left
            if laneWidth < w * 0.13 || laneWidth > w * 0.96
                continue

            center := (left + right) / 2
            if points.Length {
                previous := points[-1]
                if laneWidth < previous.Width * 0.55 || laneWidth > previous.Width * 1.2
                    || Abs(center - searchCenter) > previous.Width * 0.4
                    continue
            }
            point := {Y: fraction, X: center, Width: laneWidth, Left: left, Right: right}
            points.Push(point)
            if !estimated
                measured[index] := point
            searchCenter := center
            if points.Length >= 2
                searchCenter += Max(-w * 0.12, Min(w * 0.12, center - points[-2].X))
        }

        if points.Length < 3 || points[1].Y - points[-1].Y < 0.2
            return {Status: "Finding lanes", Direction: "", Demand: 0, Estimated: false}

        trusted := measured.Count >= 3
        if trusted {
            this.TrustedAt := A_TickCount
            this.TrustedRows := measured
        }

        ; Average nearby and distant centers separately so an isolated stripe
        ; cannot dominate the steering demand.
        near := points[1]
        nearX := near.X * 0.7 + points[2].X * 0.3
        farX := points[-1].X * 0.7 + points[-2].X * 0.3
        demand := ((nearX - anchor) * 0.40 + (farX - anchor) * 0.85) / near.Width
        status := trusted ? "Lane detected" : "Tracking dashed line"
        if Abs(demand) < 0.075
            return {Status: status, Direction: "", Demand: 0, Estimated: !trusted}
        direction := demand > 0 ? "d" : "a"
        return {Status: trusted ? (demand > 0 ? "Lane leads right" : "Lane leads left") : status,
            Direction: direction, Demand: demand, Estimated: !trusted}
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
