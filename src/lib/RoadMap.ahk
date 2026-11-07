; Internal road centerlines digitized from the official ER:LC fall map.
; Coordinates are on a 1600 × 1600 reference image. Only shared points connect.
class RoadMap {
    __New() {
        this.Nodes := Map()
        this.Edges := []
        this.Destinations := Map(
            "Freedom Ave / Riverside Drive", "678,1137",
            "Independence Pkwy / Riverside Drive", "678,1012",
            "Colonial Drive / Spring Creek Road", "824,507",
            "Oak Valley Drive / Lakeway Street", "528,205",
            "Maple Street / Oak Valley Drive", "1218,394",
            "Freedom Avenue east end", "1089,1137",
            "North end of Highway 55", "1134,126",
            "Aviator Lane / Riverside Drive", "718,371",
            "Academy Place / Valley Drive", "306,865",
            "Bulletin Avenue / Virginia Avenue", "1028,924"
        )
        ; Interchanges and bridge crossings are linked only where a road
        ; visibly joins another road. Overpasses do not form intersections.
        this.AddRoad("1134,126 1134,210 1134,395 1133,475 1119,522 1090,557 1034,612 971,676 909,739 848,798 786,855 749,901 737,950 737,1012 737,1137")
        this.AddRoad("226,476 286,522 356,565 411,591 463,606 540,616 608,631 642,644 690,672 742,708 787,742 821,774 848,798")
        this.AddRoad("528,205 568,230 624,263 681,299 709,327 718,371 724,423 728,507 717,546 692,574 655,600 642,625")
        this.AddRoad("642,625 632,643 632,685 640,733 648,784 649,838 660,899 674,955 678,1012 678,1065 678,1137")
        this.AddRoad("642,625 660,646 690,672")
        this.AddRoad("528,205 549,165 579,132 624,117 669,117 717,130 773,138 818,157 858,173 893,167 918,180 948,198 974,194 998,169 1021,151 1047,149 1068,167 1090,198 1112,208 1134,211")
        this.AddRoad("1134,211 1164,215 1191,234 1210,264 1218,295 1218,394 1218,482 1211,531 1195,569 1168,600 1128,625 1088,641 1052,670 1009,713 965,751 923,780")
        this.AddRoad("528,205 499,189 474,178 447,182 404,196 366,218 337,258 312,301 289,347 287,395 287,469 286,523 308,572 329,619 352,670 370,714 378,739 367,775 338,816 311,850 306,865 306,934 306,1010 322,1028 345,1028")
        this.AddRoad("728,507 770,507 824,507 849,508 874,528 899,553 906,580 906,633 906,693")
        this.AddRoad("824,507 824,442 824,389 832,361 853,352 921,352 984,352 1000,352 1000,374 1014,394 1069,394 1134,394 1168,394 1218,394")
        this.AddRoad("678,1012 618,1012 577,1012 525,1012 487,1012 448,1012 410,1012 375,1014 345,1028")
        this.AddRoad("345,1028 345,1072 345,1137 410,1137 448,1137 487,1137 525,1137 580,1137 634,1137 678,1137 737,1137 764,1137 808,1137 851,1137 887,1137 928,1137 974,1137 1028,1137 1089,1137")
        this.AddRoad("410,1012 410,1064 410,1137")
        this.AddRoad("448,1012 448,1092 448,1137")
        this.AddRoad("487,1012 487,1092 487,1137")
        this.AddRoad("525,1012 525,1092 525,1137")
        this.AddRoad("448,1092 487,1092 525,1092 575,1092 580,1137")
        this.AddRoad("678,1012 711,1012 736,1012 764,1012 808,1012 851,1012 887,1012 928,1012 974,1012 1028,1012 1079,1012 1094,1032 1094,1119 1089,1137")
        this.AddRoad("764,1012 764,1071 764,1137")
        this.AddRoad("808,1012 808,1071 808,1137")
        this.AddRoad("851,1012 851,1071 851,1137")
        this.AddRoad("887,1137 887,1071 887,1012 887,954 899,931 923,924 978,924 1028,924 1028,967 1028,1012 1028,1067 1028,1137")
        this.AddRoad("764,1071 808,1071 851,1071 887,1071 928,1071 974,1071 1028,1067 1094,1067 1094,1119")
        this.AddRoad("928,1012 928,1071 928,1137")
        this.AddRoad("974,1012 974,1071 974,1137")
        this.AddRoad("306,865 356,865 356,894 414,894 448,894 487,894 536,894 574,894 591,880 591,822 573,794 524,794 470,794 414,794 414,842 414,894")
        this.AddRoad("306,934 355,934 410,937 448,937 500,937 550,937 577,925 591,880")
        this.AddRoad("448,937 448,975 448,1012")
        this.AddRoad("923,780 950,813 974,841 1005,872 1028,900 1028,924")
    }

    AddRoad(polyline) {
        previous := ""
        for id in StrSplit(polyline, " ") {
            if !this.Nodes.Has(id) {
                xy := StrSplit(id, ",")
                this.Nodes[id] := {X: Integer(xy[1]), Z: Integer(xy[2]), Links: Map()}
            }
            if previous != "" && !this.Nodes[previous].Links.Has(id) {
                distance := Navigation.Distance(this.Nodes[previous], this.Nodes[id])
                this.Nodes[previous].Links[id] := distance
                this.Nodes[id].Links[previous] := distance
                this.Edges.Push([previous, id, distance])
            }
            previous := id
        }
    }

    ; Two separated landmarks establish the conversion from map to API units.
    static Calibrate(first, second) {
        mx := second.Map.X - first.Map.X, mz := second.Map.Z - first.Map.Z
        wx := second.World.X - first.World.X, wz := second.World.Z - first.World.Z
        length := mx * mx + mz * mz
        if length < 250 ** 2
            return false
        scale := (mx * wx + mz * wz) / length
        if scale <= 0 || Abs(mx * wz - mz * wx) > length * scale * 0.08
            return false
        return {Scale: scale,
            X: (first.World.X + second.World.X - scale * (first.Map.X + second.Map.X)) / 2,
            Z: (first.World.Z + second.World.Z - scale * (first.Map.Z + second.Map.Z)) / 2}
    }

    Plan(world, destination, transform) {
        if !transform || !this.Destinations.Has(destination)
            return []
        mapPoint := {X: (world.X - transform.X) / transform.Scale,
            Z: (world.Z - transform.Z) / transform.Scale}
        best := 18, snap := false
        for edge in this.Edges {
            a := this.Nodes[edge[1]], b := this.Nodes[edge[2]], distance := edge[3]
            dx := b.X - a.X, dz := b.Z - a.Z
            fraction := Max(0, Min(1, ((mapPoint.X - a.X) * dx + (mapPoint.Z - a.Z) * dz) / distance ** 2))
            projected := {X: a.X + dx * fraction, Z: a.Z + dz * fraction}
            gap := Navigation.Distance(mapPoint, projected)
            if gap < best {
                best := gap
                snap := {Edge: edge, Fraction: fraction}
            }
        }
        if !snap
            return []

        finish := this.Destinations[destination]
        distances := Map(finish, 0), next := Map(), settled := Map()
        while true {
            current := "", closest := 1.0e20
            for id, cost in distances {
                if !settled.Has(id) && cost < closest
                    current := id, closest := cost
            }
            if current = ""
                break
            settled[current] := true
            for id, length in this.Nodes[current].Links {
                cost := closest + length
                if !distances.Has(id) || cost < distances[id]
                    distances[id] := cost, next[id] := current
            }
        }

        edge := snap.Edge
        aCost := distances.Get(edge[1], 1.0e20) + snap.Fraction * edge[3]
        bCost := distances.Get(edge[2], 1.0e20) + (1 - snap.Fraction) * edge[3]
        if Min(aCost, bCost) >= 1.0e20
            return []
        current := aCost <= bCost ? edge[1] : edge[2]
        points := []
        loop {
            node := this.Nodes[current]
            points.Push({X: node.X * transform.Scale + transform.X, Z: node.Z * transform.Scale + transform.Z})
            if current = finish
                return points
            current := next[current]
        }
    }
}
