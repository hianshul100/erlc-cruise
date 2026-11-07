; Reads one player's position from the official private-server API.
; Navigation supplies HUD directions and never sends driving inputs.
class Navigation {
    Key := ""
    PlayerId := ""
    Request := ""
    NextRead := 0
    Position := false
    LastRead := 0
    Status := "Disconnected"
    Recording := false
    Following := 0
    NextPoint := 1
    Hint := ""

    __New() {
        this.Routes := []
        this.RouteFile := Paths.AppDataDir "\routes.json"
        try {
            saved := JSON.parse(FileRead(this.RouteFile, "UTF-8"), false, false)
            if saved is Array
                this.Routes := saved
        }
        this.PollFn := this.Poll.Bind(this)
    }

    Connect(playerId) {
        if this.Recording
            return "Save or cancel the current recording before reconnecting."
        if !RegExMatch(playerId, "^\d{1,20}$")
            return "Enter your numeric Roblox user ID."
        prompt := InputBox("Enter the ER:LC private-server key. It stays in memory for this session.",
            "ER:LC Navigation", "Password w440")
        if prompt.Result != "OK" || Trim(prompt.Value) = ""
            return "Connection cancelled."
        this.Disconnect()
        this.Key := Trim(prompt.Value)
        this.PlayerId := playerId
        this.Status := "Connecting"
        this.NextRead := 0
        SetTimer(this.PollFn, 250)
        return "Connecting to the ER:LC API."
    }

    Disconnect() {
        SetTimer(this.PollFn, 0)
        if this.Request
            try this.Request.Abort()
        this.Request := ""
        this.Key := ""
        this.Position := false
        this.LastRead := 0
        this.Following := 0
        this.Hint := ""
        this.Status := "Disconnected"
    }

    Poll() {
        if this.Key = ""
            return
        if this.Request {
            try {
                if !this.Request.WaitForResponse(0)
                    return
                this.HandleResponse(this.Request)
            } catch {
                this.Position := false
                this.Status := "API unavailable. Retrying."
                this.NextRead := A_TickCount + 5000
            }
            this.Request := ""
            return
        }
        if A_TickCount < this.NextRead
            return
        this.NextRead := A_TickCount + 3000
        try {
            request := ComObject("WinHttp.WinHttpRequest.5.1")
            request.SetTimeouts(2500, 2500, 2500, 4500)
            request.Open("GET", "https://api.erlc.gg/v2/server?Players=true", true)
            request.Option[6] := false ; Keep the server key on the official host.
            request.SetRequestHeader("Accept", "application/json")
            request.SetRequestHeader("server-key", this.Key)
            request.Send()
            this.Request := request
        } catch {
            this.Position := false
            this.Status := "API unavailable. Retrying."
            this.NextRead := A_TickCount + 5000
        }
    }

    HandleResponse(request) {
        status := request.Status
        if status != 200 {
            this.Position := false
            if status = 401 || status = 403 {
                this.Disconnect()
                this.Status := "API denied access. Check the private-server key."
            } else if status = 429 {
                retry := ""
                try retry := request.GetResponseHeader("Retry-After")
                this.NextRead := A_TickCount + 1000 * (IsNumber(retry) ? Max(1, Number(retry)) : 60)
                this.Status := "API rate limit. Waiting."
            } else {
                this.NextRead := A_TickCount + 10000
                this.Status := "API returned HTTP " status ". Retrying."
            }
            return
        }
        point := Navigation.ReadPlayer(request.ResponseText, this.PlayerId)
        previous := this.LivePosition()
        this.Position := point
        if !point {
            this.Status := "Player location unavailable on this server."
            return
        }
        this.LastRead := A_TickCount
        this.Status := "Connected"
        if this.Recording && this.Recording.Length < 1500
            this.RecordPoint(point)
        if this.Following
            this.Advance(point, previous)
    }

    static ReadPlayer(body, playerId) {
        data := JSON.parse(body, false, false)
        if !IsObject(data) || !data.HasOwnProp("Players") || !(data.Players is Array)
            return false
        for player in data.Players {
            if !IsObject(player) || !player.HasOwnProp("Player") || !RegExMatch(player.Player, ":" playerId "$")
                continue
            if !player.HasOwnProp("Location") || !IsObject(player.Location)
                return false
            loc := player.Location
            if !loc.HasOwnProp("LocationX") || !loc.HasOwnProp("LocationZ")
                || !IsNumber(loc.LocationX) || !IsNumber(loc.LocationZ)
                return false
            return {X: Number(loc.LocationX), Z: Number(loc.LocationZ),
                Street: loc.HasOwnProp("StreetName") ? loc.StreetName : "",
                Postal: loc.HasOwnProp("PostalCode") ? loc.PostalCode : ""}
        }
        return false
    }

    LivePosition() {
        return this.Position && A_TickCount - this.LastRead <= 9000 ? this.Position : false
    }

    ToggleRecording() {
        if !this.Recording {
            point := this.LivePosition()
            if !point
                return "Wait for a live player position before recording."
            this.Following := 0
            this.Recording := [point]
            return "Recording. Drive the route, then click Save Recording."
        }
        if this.Recording.Length < 2
            return "Drive farther and wait for another reading before saving."
        prompt := InputBox("Name this route.", "Save ER:LC Route", "w320", "Route " (this.Routes.Length + 1))
        if prompt.Result != "OK" || Trim(prompt.Value) = ""
            return "Recording is still active."
        route := {Name: SubStr(Trim(prompt.Value), 1, 80), Points: this.Recording.Clone()}
        routes := this.Routes.Clone()
        routes.Push(route)
        temp := this.RouteFile ".tmp"
        try {
            file := FileOpen(temp, "w", "UTF-8-RAW")
            try file.Write(JSON.stringify(routes))
            finally file.Close()
            FileMove(temp, this.RouteFile, 1)
        } catch {
            return "Could not save the route. The recording is still available."
        }
        this.Routes := routes
        this.Recording := false
        return "Route saved."
    }

    RecordPoint(point) {
        if Navigation.Distance(point, this.Recording[-1]) >= 20
            this.Recording.Push(point)
    }

    Follow(index) {
        if !IsInteger(index) || index < 1 || index > this.Routes.Length
            return "Choose a saved route."
        if this.Recording
            return "Save or cancel the current recording first."
        point := this.LivePosition()
        if !point
            return "Wait for a live player position."
        this.Following := Integer(index)
        this.NextPoint := 1
        this.Advance(point, false)
        return "Following " this.Routes[index].Name "."
    }

    StopRoute() {
        this.Following := 0
        this.Hint := ""
        return "Guidance stopped."
    }

    CancelRecording() {
        this.Recording := false
        return "Recording discarded."
    }

    Advance(point, previous) {
        route := this.Routes[this.Following]
        while this.NextPoint <= route.Points.Length {
            target := route.Points[this.NextPoint]
            reached := Navigation.Distance(point, target) <= 55
            if !reached && previous && Navigation.Distance(point, previous) < 550
                reached := Navigation.Passed(previous, point, target)
            if !reached
                break
            this.NextPoint++
        }
        if this.NextPoint > route.Points.Length {
            this.Following := 0
            this.Hint := "Arrived"
            return
        }
        target := route.Points[this.NextPoint]
        this.Hint := Format("{} · {} units · {}/{}", Navigation.Guide(previous, point, target),
            Round(Navigation.Distance(point, target)), this.NextPoint, route.Points.Length)
    }

    static Passed(from, to, target) {
        dx := to.X - from.X, dz := to.Z - from.Z
        length := dx * dx + dz * dz
        if length = 0
            return false
        t := ((target.X - from.X) * dx + (target.Z - from.Z) * dz) / length
        return t >= 0 && t <= 1 && Navigation.Distance(target, {X: from.X + t * dx, Z: from.Z + t * dz}) <= 55
    }

    static Distance(a, b) => Sqrt((a.X - b.X) ** 2 + (a.Z - b.Z) ** 2)

    static Guide(previous, current, target) {
        if !previous || Navigation.Distance(previous, current) < 12
            || Navigation.Distance(previous, current) >= 550
            return Navigation.Direction(current, target)
        dx := current.X - previous.X, dz := current.Z - previous.Z
        tx := target.X - current.X, tz := target.Z - current.Z
        dot := dx * tx + dz * tz
        cross := dx * tz - dz * tx
        if Abs(cross) <= Abs(dot) * 0.45
            return dot >= 0 ? "Ahead" : "Waypoint behind"
        return cross > 0 ? "Right ahead" : "Left ahead"
    }

    static Direction(a, b) {
        dx := b.X - a.X, dz := b.Z - a.Z
        if Abs(dx) > Abs(dz) * 2
            return dx > 0 ? "East" : "West"
        if Abs(dz) > Abs(dx) * 2
            return dz > 0 ? "South" : "North"
        return (dz >= 0 ? "South" : "North") (dx >= 0 ? "east" : "west")
    }

    HudText() {
        if this.Key = ""
            return ""
        point := this.LivePosition()
        if !point
            return this.Status = "Connected" ? "Waiting for fresh location" : this.Status
        place := Trim(point.Street " " point.Postal)
        if place = ""
            place := Format("X {} · Z {}", Round(point.X), Round(point.Z))
        if this.Recording
            return place " · Recording " this.Recording.Length
        if this.Hint != ""
            return place " · " this.Hint
        return place
    }

    State() {
        names := []
        for route in this.Routes
            names.Push(route.Name)
        return {status: this.Status, location: this.HudText(), connected: this.Key != "",
            playerId: this.PlayerId, recording: !!this.Recording, following: !!this.Following, routes: names}
    }
}
