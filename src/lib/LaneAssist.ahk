; Tracks the lane ahead and applies bounded steering pulses.
class LaneAssist {
    Active := false
    Status := "Ready"
    RequiresSpeed := false
    ResumeAt := 0
    LastDirection := ""
    Acquired := false
    AcquireSince := 0
    AcquireFrames := 0
    LastLaneAt := 0
    LastLane := false
    LaneName := ""
    SmoothedDemand := 0
    NextPulseAt := 0
    TrustedAt := 0
    TrustedRows := Map()
    ScanWidth := 0
    ScanHeight := 0
    TiltedCamera := false
    CameraCenter := 0.5
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
        this.TiltedCamera := Config.GetBool("Lane", "TiltedCamera")
        this.CameraCenter := Max(0.2, Min(0.8, Config.GetInt("Lane", "CameraCenter") / 100))
        InstallKeybdHook()
        this.RequiresSpeed := requiresSpeed
        if requiresSpeed
            this.Engine.SetLaneGuidance(true)
        this.ResumeAt := A_TickCount + 400
        this.NextPulseAt := 0
        this.ResetAcquisition()
        this.Active := true
        SetTimer(this.UpdateFn, 20)
    }

    Stop() {
        if this.RequiresSpeed
            this.Engine.SetLaneGuidance(false)
        this.Active := false
        this.ResetAcquisition()
        this.Status := "Ready"
        SetTimer(this.UpdateFn, 0)
        this.ReleaseSteering()
    }

    ResetAcquisition() {
        this.Acquired := false
        this.AcquireSince := 0
        this.AcquireFrames := 0
        this.LastLaneAt := 0
        this.LastLane := false
        this.LaneName := ""
        this.LastDirection := ""
        this.SmoothedDemand := 0
        this.TrustedRows.Clear()
        this.Status := "Finding lane"
    }

    AcceptLane(scan, now) {
        if this.LastLaneAt && now - this.LastLaneAt > 360
            this.ResetAcquisition()
        if !scan || !scan.Trusted
            return this.Acquired
        if this.LastLane {
            width := this.LastLane.Width
            if Abs(scan.Center - this.LastLane.Center) > width * 0.38
                || scan.Width < width * 0.58 || scan.Width > width * 1.65
                this.ResetAcquisition()
        }
        this.LastLane := scan
        this.LastLaneAt := now
        if !this.AcquireFrames
            this.AcquireSince := now
        this.AcquireFrames++
        if this.AcquireFrames >= 5 && now - this.AcquireSince >= 1250
            this.Acquired := true
        if this.Acquired
            this.LaneName := scan.LaneName
        else
            this.Status := "Finding lane"
        return this.Acquired
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
            if this.RequiresSpeed && this.Acquired
                this.Engine.SetLaneGuidance(false)
            this.ReleaseSteering()
            this.LastDirection := ""
            this.SmoothedDemand := 0
            this.ResetAcquisition()
            this.Status := "Manual steering"
            this.ResumeAt := now + 400
            return
        }
        if this.HeldKey != "" && now >= this.ReleaseAt
            this.ReleaseSteering()
        if this.HeldKey != "" || now < this.ResumeAt
            return
        if this.RequiresSpeed
            this.Engine.SetLaneGuidance(true)

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
        if !this.AcceptLane(scan, A_TickCount) {
            if this.RequiresSpeed
                this.Engine.ResetLaneReading()
            return
        }

        highway := IsSet(gNavigation) ? gNavigation.LiveHighway() : false
        if this.RequiresSpeed && scan && scan.Trusted
            this.Engine.UpdateLaneGuidance(highway
                ? Max(scan.Curvature, highway.Curvature) : scan.Curvature)
        if !scan || scan.Direction = "" {
            this.LastDirection := ""
            this.SmoothedDemand := 0
            return
        }
        demand := scan.Demand
        if highway && scan.Trusted && scan.Direction = highway.Turn
            demand *= 1 + Min(0.22, highway.Curvature)
        if scan.Direction != this.LastDirection {
            this.LastDirection := scan.Direction
            this.SmoothedDemand := demand
            return
        }
        this.SmoothedDemand += (demand - this.SmoothedDemand) * 0.45
        if A_TickCount < this.NextPulseAt
            return

        direction := scan.Direction
        duration := LaneAssist.PulseDuration(this.SmoothedDemand)
        if scan.Estimated
            duration := Min(duration, 48)
        this.HeldKey := direction
        Send("{" direction " down}")
        this.ReleaseAt := A_TickCount + duration
        this.NextPulseAt := this.ReleaseAt + (scan.Estimated ? 120 : 75)
        this.Status := "Steer " StrUpper(direction)
        Logger.Action(Format("Lane assist steered {} for {} ms.", StrUpper(direction), duration))
    }

    static PulseDuration(demand) => Round(Min(90, Max(24, 15 + Abs(demand) * 175)))

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

        anchor := w * (this.TiltedCamera ? this.CameraCenter : 0.5)
        points := []
        measured := Map()
        leftYellow := 0, rightYellow := 0, leftVisible := 0, rightVisible := 0
        searchCenter := anchor
        useHistory := A_TickCount - this.TrustedAt <= 240
        rows := this.TiltedCamera
            ? [0.77, 0.73, 0.69, 0.65, 0.61, 0.57, 0.53, 0.49, 0.45, 0.41, 0.37, 0.33, 0.29, 0.25, 0.21, 0.17]
            : [0.88, 0.78, 0.68, 0.58, 0.48, 0.38, 0.28, 0.18]
        for index, fraction in rows {
            row := Round((h - 1) * fraction) * w * 4
            prior := useHistory ? this.TrustedRows.Get(index, false) : false
            split := Min(w - 14, Max(13, Round(searchCenter)))
            left := this.FindMark(pixels, row, split - 1, 12, -1)
            right := this.FindMark(pixels, row, split + 1, w - 13, 1)
            leftColor := left >= 0 ? this.MarkColor(pixels, row + left * 4) : ""
            rightColor := right >= 0 ? this.MarkColor(pixels, row + right * 4) : ""
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
            if laneWidth < w * (points.Length ? 0.065 : 0.12) || laneWidth > w * 0.96
                continue

            center := (left + right) / 2
            if this.TiltedCamera && !points.Length && Abs(center - anchor) > laneWidth * 0.25
                continue
            if points.Length {
                previous := points[-1]
                minRatio := this.TiltedCamera ? Max(0.32, 0.72 - (previous.Y - fraction)) : 0.55
                if laneWidth < previous.Width * minRatio || laneWidth > previous.Width * 1.2
                    || Abs(center - searchCenter) > previous.Width * 0.4
                    continue
            }
            point := {Y: fraction, X: center, Width: laneWidth, Left: left, Right: right}
            points.Push(point)
            leftVisible += leftColor != ""
            rightVisible += rightColor != ""
            leftYellow += leftColor = "yellow"
            rightYellow += rightColor = "yellow"
            if !estimated
                measured[index] := point
            searchCenter := center
            if points.Length >= 2
                searchCenter += Max(-w * 0.12, Min(w * 0.12, center - points[-2].X))
        }

        if points.Length < 3 || points[1].Y - points[-1].Y < 0.2
            return {Status: "Finding lanes", Direction: "", Demand: 0, Estimated: false, Trusted: false}

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
        bend := farX - nearX
        if this.TiltedCamera {
            ; A tilted straight road still converges toward its vanishing point.
            ; Compare the distant lane to the line implied by the near and mid widths.
            mid := points[Ceil(points.Length / 2)]
            far := points[-1]
            widthChange := near.Width - mid.Width
            if points.Length >= 5 && widthChange >= near.Width * 0.16 {
                expectedFar := near.X + (mid.X - near.X)
                    * Min(2.6, Max(0, (near.Width - far.Width) / widthChange))
                bend := far.X - expectedFar
            }
        }
        demand := this.TiltedCamera
            ? ((nearX - anchor) * 0.95 + bend * 0.75) / near.Width
            : ((nearX - anchor) * 0.40 + (farX - anchor) * 0.85) / near.Width
        curvature := Abs(bend) / near.Width
        name := leftYellow >= 2 && leftYellow * 2 >= leftVisible && rightYellow = 0
            ? "Leftmost lane" : "Lane tracked"
        if rightYellow >= 2
            return {Status: "Finding lane", Direction: "", Demand: 0, Estimated: false, Trusted: false}
        leftStyle := this.BoundaryStyle(pixels, w, h, points, "Left")
        rightStyle := this.BoundaryStyle(pixels, w, h, points, "Right")
        status := trusted ? "Lane detected" : "Tracking dashed line"
        threshold := curvature >= 0.13 ? 0.065 : 0.105
        direction := Abs(demand) < threshold ? "" : demand > 0 ? "d" : "a"
        return {Status: status, Direction: direction, Demand: demand, Estimated: !trusted,
            Trusted: trusted, Curvature: curvature, LaneName: name, Center: nearX, Width: near.Width,
            LeftStyle: leftStyle, RightStyle: rightStyle}
    }

    BoundaryStyle(pixels, w, h, points, side) {
        hits := 0, samples := 0, interval := 1
        Loop 24 {
            fraction := points[1].Y - (points[1].Y - points[-1].Y) * (A_Index - 1) / 23
            while interval < points.Length - 1 && fraction < points[interval + 1].Y
                interval++
            a := points[interval], b := points[interval + 1]
            blend := (a.Y - fraction) / (a.Y - b.Y)
            x := Round(a.%side% + (b.%side% - a.%side%) * blend)
            margin := Max(3, Min(8, Round(a.Width * 0.09)))
            left := Max(12, x - margin), right := Min(w - 13, x + margin)
            if left > right
                continue
            row := Round((h - 1) * fraction) * w * 4
            hits += this.FindMark(pixels, row, left, right, 1) >= 0
            samples++
        }
        if hits < 3
            return "unknown"
        if hits >= samples * 0.82
            return "solid"
        return "dashed"
    }

    MarkColor(pixels, offset) {
        b := NumGet(pixels, offset, "UChar")
        g := NumGet(pixels, offset + 1, "UChar")
        r := NumGet(pixels, offset + 2, "UChar")
        if r >= 80 && g >= 45 && r >= g && g - b >= 23 && r - b >= 42
            return "yellow"
        return Max(r, g, b) - Min(r, g, b) <= 62 ? "white" : ""
    }

    ; A marking is a narrow bright stripe relative to the road around it.
    FindMark(pixels, row, start, limit, step) {
        x := start
        while (step > 0 ? x <= limit : x >= limit) {
            offset := row + x * 4
            mark := this.Luma(pixels, offset)
            if this.TiltedCamera && (mark < 55 || this.MarkColor(pixels, offset) = "") {
                x += step
                continue
            }
            for radius in [4, 8, 12] {
                left := this.Luma(pixels, offset - radius * 4)
                right := this.Luma(pixels, offset + radius * 4)
                if mark >= Max(left, right) + 17 && Abs(left - right) <= (this.TiltedCamera ? 30 : 40)
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
