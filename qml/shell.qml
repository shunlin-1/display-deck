// Display Deck — native Quickshell/QML monitor manager for niri.
// A normal niri-managed FloatingWindow with real compositor blur (KDE-blur protocol).
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    // ---- theme (overridden from colors.json) ----
    property color cSurface:   "#181211"
    property color cSurface2:  "#251e1d"
    property color cSurface3:  "#2f2725"
    property color cOutline:   "#534342"
    property color cText:      "#ede0de"
    property color cMuted:     "#a99693"
    property color cPrimary:   "#ffb3ae"
    property color cOnPrimary: "#5f1414"
    property color cAmber:     "#e2c28c"
    property color cError:     "#ffb4ab"
    readonly property var palette: ["#ffb3ae","#e2c28c","#a0d0c9","#bdc7dc","#dabde2","#b1d26c","#e7bdb9","#a6c8ff"]
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    // translucent variant of a theme colour
    function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // ---- state ----
    property var modelList: []
    property string sel: ""
    property int activeCount: 0
    property bool identifyOn: false
    property int rev: 0                        // bump to force binding refresh
    property int fitRev: 0                      // bump only to re-fit the canvas scale

    readonly property var scales: ["1.0","1.25","1.333","1.5","1.75","2.0","2.5","3.0"]
    readonly property var rotations: [["normal","Normal"],["90","90° ↺"],["180","180°"],["270","270° ↺"],
        ["flipped","Flipped"],["flipped-90","Flipped 90°"],["flipped-180","Flipped 180°"],["flipped-270","Flipped 270°"]]
    readonly property var xformMap: ({"Normal":"normal","90":"90","180":"180","270":"270",
        "Flipped":"flipped","Flipped90":"flipped-90","Flipped180":"flipped-180","Flipped270":"flipped-270"})

    function byName(n) { for (var i=0;i<modelList.length;i++) if (modelList[i].name===n) return modelList[i]; return null }
    function current() { return byName(sel) }

    component OutputModel: QtObject {
        property string name; property string make
        property var modes: []; property var resolutions: []
        property bool enabled: true
        property string res; property string mode
        property string scalev: "1.0"; property string transform: "normal"
        property int x: 0; property int y: 0; property int w: 0; property int h: 0
        property bool vrrSupported: false; property string vrr: "off"
        property int num: 0; property color color: "#ffb3ae"
    }
    Component { id: outComp; OutputModel {} }

    // ---- theme load ----
    FileView {
        id: colorsFile
        path: root.configDir + "/niri/colors.json"
        onLoaded: root.applyTheme(text())
    }
    FileView {
        id: colorsFile2
        path: root.configDir + "/noctalia/colors.json"
        onLoaded: if (colorsFile.text() === "") root.applyTheme(text())
    }
    function applyTheme(txt) {
        try {
            var t = JSON.parse(txt)
            if (t.mSurface) cSurface = t.mSurface
            if (t.mSurfaceVariant) { cSurface2 = t.mSurfaceVariant; cSurface3 = Qt.lighter(t.mSurfaceVariant,1.25) }
            if (t.mOutline) cOutline = t.mOutline
            if (t.mOnSurface) cText = t.mOnSurface
            if (t.mPrimary) cPrimary = t.mPrimary
            if (t.mOnPrimary) cOnPrimary = t.mOnPrimary
            if (t.mTertiary) cAmber = t.mTertiary
            if (t.mError) cError = t.mError
        } catch(e) {}
    }

    // ---- niri data ----
    function mapXform(j) { return xformMap[String(j)] || "normal" }
    function modeStr(m) { return m.w + "x" + m.h + "@" + (m.r/1000).toFixed(3) }
    // modes matching a "WxH" resolution, highest refresh first
    function modesForRes(m, res) { return m.modes.filter(function(x){ return (x.w+"x"+x.h)===res }).sort(function(a,b){ return b.r-a.r }) }

    Process {
        id: loadProc
        command: ["niri","msg","--json","outputs"]
        stdout: StdioCollector { onStreamFinished: root.parseOutputs(text) }
    }
    function reload() { loadProc.running = true }

    function parseOutputs(txt) {
        var d; try { d = JSON.parse(txt) } catch(e) { return }
        var names = Object.keys(d).sort()
        var list = []
        for (var idx=0; idx<names.length; idx++) {
            var n = names[idx], o = d[n], log = o.logical
            var modes = o.modes.map(function(m){ return {w:m.width,h:m.height,r:m.refresh_rate} })
            var sorted = modes.slice().sort(function(a,b){ return (b.w-a.w)||(b.h-a.h) })
            var ress = []
            sorted.forEach(function(m){ var k=m.w+"x"+m.h; if (ress.indexOf(k)<0) ress.push(k) })
            var ci = o.current_mode
            var cur = (ci!==null && ci!==undefined && modes[ci]) ? modes[ci] : modes[0]
            var sc = log ? Number(log.scale) : 1
            // niri reports the FLOORED integer logical size, but its overlap check uses the true
            // fractional size (res/scale). Pack with ceil so an adjacent box is never smaller than
            // reality — otherwise edge-to-edge placements overlap by <1px and niri silently rejects
            // the position (auto-shoving the output elsewhere). Account for rotation like computeSize.
            var rot = mapXform(log ? log.transform : "Normal")
            var lw0 = Math.ceil((cur?cur.w:0)/sc), lh0 = Math.ceil((cur?cur.h:0)/sc)
            if (["90","270","flipped-90","flipped-270"].indexOf(rot) >= 0) { var tt=lw0; lw0=lh0; lh0=tt }
            var obj = outComp.createObject(root, {
                name: n, make: ((o.make||"")+" "+(o.model||"")).trim(),
                modes: modes, resolutions: ress, enabled: !!log,
                res: cur ? (cur.w+"x"+cur.h) : ress[0],
                mode: cur ? modeStr(cur) : "",
                scalev: log ? String(sc) : "1.0",
                transform: rot,
                x: log ? log.x : 0, y: log ? log.y : 0,
                w: lw0,
                h: lh0,
                vrrSupported: !!o.vrr_supported, vrr: o.vrr_enabled ? "on" : "off",
                num: idx+1, color: palette[idx % palette.length]
            })
            list.push(obj)
        }
        // give off-at-load monitors a spot to the right of the enabled cluster so they stay in the layout
        var en = list.filter(function(m){return m.enabled})
        if (en.length) {
            var ox = Math.max.apply(null, en.map(function(m){return m.x+m.w})) + 60
            var baseY = Math.min.apply(null, en.map(function(m){return m.y}))
            for (var k=0;k<list.length;k++) { var dm=list[k]
                if (!dm.enabled) { dm.x = ox; dm.y = baseY; ox += dm.w + 20 } }
        }
        for (var j=0;j<modelList.length;j++) modelList[j].destroy()
        modelList = list
        if (!current()) { var f = list.find(function(m){return m.enabled}) || list[0]; sel = f ? f.name : "" }
        activeCount = list.filter(function(m){return m.enabled}).length
        rev++; fitRev++
    }

    function computeSize(m) {
        var p = m.res.split("x"); var w = Number(p[0]), h = Number(p[1])
        var s = Number(m.scalev) || 1
        var lw = Math.ceil(w/s), lh = Math.ceil(h/s)   // ceil, not round: see parseOutputs note on niri overlap rejection
        if (["90","270","flipped-90","flipped-270"].indexOf(m.transform) >= 0) { var t=lw; lw=lh; lh=t }
        return [lw,lh]
    }
    // rotation / resolution / scale change a screen's logical size — re-fit the canvas so
    // a now-taller (portrait) or larger screen isn't clipped by the stage (fitRev, not just rev)
    function recalcSize(m) { var s = computeSize(m); m.w = s[0]; m.h = s[1]; rev++; fitRev++ }

    // pack all enabled screens edge-to-edge (left→right by current order), then re-fit/center the view
    function tidyLayout() {
        var on = modelList.filter(function(m){return m.enabled}).slice().sort(function(a,b){ return (a.x-b.x)||(a.y-b.y) })
        var cx = 0
        for (var i=0;i<on.length;i++){ on[i].x = cx; on[i].y = 0; cx += on[i].w }
        rev++; fitRev++
    }

    // snap + collision (logical px)
    function snap(m, nx, ny) {
        var TH = 40, bx = nx, by = ny
        for (var i=0;i<modelList.length;i++) { var o=modelList[i]; if (o===m || !o.enabled) continue
            var ex=[[nx,o.x],[nx+m.w,o.x+o.w],[nx,o.x+o.w],[nx+m.w,o.x]]
            for (var a=0;a<ex.length;a++) if (Math.abs(ex[a][0]-ex[a][1])<TH) bx = nx+(ex[a][1]-ex[a][0])
            var ey=[[ny,o.y],[ny+m.h,o.y+o.h],[ny,o.y+o.h],[ny+m.h,o.y]]
            for (var b=0;b<ey.length;b++) if (Math.abs(ey[b][0]-ey[b][1])<TH) by = ny+(ey[b][1]-ey[b][0])
        }
        return [bx,by]
    }
    function resolveCollision(m, nx, ny) {
        for (var it=0; it<12; it++) { var hit=false
            for (var i=0;i<modelList.length;i++) { var o=modelList[i]; if (o===m || !o.enabled) continue
                var ix=Math.min(nx+m.w,o.x+o.w)-Math.max(nx,o.x)
                var iy=Math.min(ny+m.h,o.y+o.h)-Math.max(ny,o.y)
                if (ix>0.5 && iy>0.5) {
                    if (ix<iy) nx += ((nx+m.w/2)<(o.x+o.w/2)? -ix : ix)
                    else       ny += ((ny+m.h/2)<(o.y+o.h/2)? -iy : iy)
                    hit=true
                }
            }
            if (!hit) break
        }
        return [Math.round(nx),Math.round(ny)]
    }

    // ---- apply + save ----
    Process { id: applyProc }
    function applyAndSave() {
        var cmds=[], blocks=["// Generated by Display Deck. Safe to regenerate."]
        for (var i=0;i<modelList.length;i++) { var m=modelList[i]
            if (!m.enabled) { cmds.push("niri msg output '"+m.name+"' off"); blocks.push('output "'+m.name+'" {\n    off\n}'); continue }
            cmds.push("niri msg output '"+m.name+"' on")
            if (m.mode) cmds.push("niri msg output '"+m.name+"' mode '"+m.mode+"'")
            if (m.scalev) cmds.push("niri msg output '"+m.name+"' scale "+m.scalev)
            cmds.push("niri msg output '"+m.name+"' transform "+m.transform)
            cmds.push("niri msg output '"+m.name+"' position set -- "+m.x+" "+m.y)
            cmds.push("niri msg output '"+m.name+"' vrr "+(m.vrr==="on"?"on":(m.vrr==="on-demand"?"on --on-demand":"off")))
            var b='output "'+m.name+'" {\n    mode "'+m.mode+'"\n    scale '+m.scalev
            if (m.transform!=="normal") b+='\n    transform "'+m.transform+'"'
            b+='\n    position x='+m.x+' y='+m.y
            if (m.vrr==="on") b+='\n    variable-refresh-rate'
            else if (m.vrr==="on-demand") b+='\n    variable-refresh-rate on-demand=true'
            b+='\n}'; blocks.push(b)
        }
        var kdl = blocks.join("\n\n")+"\n"
        var mk = root.configDir + "/niri/monitor.kdl"
        var script = cmds.join("; ") + "; cp '" + mk + "' '" + mk + ".bak' 2>/dev/null; printf '%s' \"$1\" > '" + mk + "'"
        applyProc.command = ["bash","-c", script, "nd", kdl]
        applyProc.running = true
    }

    // ---- identify (transparent per-screen corner panels) ----
    function toggleIdentify() { identifyOn = !identifyOn }

    Component.onCompleted: reload()

    // ===== reusable UI =====
    component DeckUI: Item {
        id: ui
        // ---- header ----
        Rectangle {
            id: header; height: 56; color: "transparent"
            anchors { left: parent.left; right: parent.right; top: parent.top }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.cOutline }

            // drag the window by its header (declared first so the buttons on top still get clicks)
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.SizeAllCursor
                onPressed: deckWin.startSystemMove()
            }

            // identify toggle (LEFT corner)
            Rectangle {
                id: idBtn; width: 122; height: 32; radius: 6
                anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                color: root.identifyOn ? root.tint(root.cAmber,0.18) : "transparent"
                border.color: root.identifyOn ? root.cAmber : root.cOutline
                Row {
                    anchors.centerIn: parent; spacing: 8
                    Rectangle { width:12; height:12; radius:6; anchors.verticalCenter: parent.verticalCenter
                        color: "transparent"; border.color: root.identifyOn?root.cAmber:root.cMuted; border.width: 1.5
                        Rectangle { anchors.centerIn: parent; width:5; height:5; radius:3; color: root.identifyOn?root.cAmber:root.cMuted } }
                    Text { text: "IDENTIFY"; color: root.identifyOn?root.cAmber:root.cMuted; font.family: root.fontFamily
                        font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.5; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleIdentify() }
            }

            Row {
                anchors.centerIn: parent; spacing: 10
                Rectangle { width:8; height:8; radius:4; color: root.cPrimary; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "DISPLAY DECK"; color: root.cText; font.family: root.fontFamily; font.pixelSize: 14
                    font.bold: true; font.letterSpacing: 3; anchors.verticalCenter: parent.verticalCenter }
            }

            // right: active count
            Row {
                anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                Text { text: root.activeCount+"/"+root.modelList.length+" active"; color: root.cMuted
                    font.family: root.fontFamily; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
            }
        }

        // ---- main: canvas + panel ----
        RowLayout {
            anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: footer.top }
            spacing: 0

            // layout canvas
            Item {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 360
                Rectangle { anchors.fill: parent; anchors.rightMargin: 0; color: "transparent"
                    Rectangle { anchors.right: parent.right; width:1; height: parent.height; color: root.cOutline } }
                // compact LAYOUT label + a (?) that reveals drag hints on hover (saves toolbar space)
                Row {
                    id: layoutHdr
                    z: 10                          // lift above the stage so the tooltip isn't clipped/covered
                    anchors { left: parent.left; top: parent.top; leftMargin: 16; topMargin: 11 }
                    spacing: 7
                    Text { text: "LAYOUT"; color: root.cMuted; font.family: root.fontFamily
                        font.pixelSize: 10; font.letterSpacing: 1.5; anchors.verticalCenter: parent.verticalCenter }
                    Rectangle {
                        id: hintBtn
                        width: 15; height: 15; radius: 8; anchors.verticalCenter: parent.verticalCenter
                        color: hintMA.containsMouse ? root.tint(root.cAmber,0.18) : "transparent"
                        border.color: hintMA.containsMouse ? root.cAmber : root.cOutline
                        Text { anchors.centerIn: parent; text: "?"; font.family: root.fontFamily; font.pixelSize: 9; font.bold: true
                            color: hintMA.containsMouse ? root.cAmber : root.cMuted }
                        MouseArea { id: hintMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor }
                        // hover tooltip
                        Rectangle {
                            visible: hintMA.containsMouse
                            anchors { left: parent.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
                            width: hintCol.width + 22; height: hintCol.height + 14; radius: 6
                            color: root.cSurface3; border.color: root.cAmber
                            Column {
                                id: hintCol; anchors.centerIn: parent; spacing: 3
                                Row { spacing: 6
                                    Text { text: "Left-drag"; color: root.cAmber; font.family: root.fontFamily; font.pixelSize: 10; font.bold: true }
                                    Text { text: "move a screen"; color: root.cText; font.family: root.fontFamily; font.pixelSize: 10 } }
                                Row { spacing: 6
                                    Text { text: "Right-drag"; color: root.cAmber; font.family: root.fontFamily; font.pixelSize: 10; font.bold: true }
                                    Text { text: "pan the view"; color: root.cText; font.family: root.fontFamily; font.pixelSize: 10 } }
                            }
                        }
                    }
                }
                // top-right pill buttons
                Row {
                    id: toolPills
                    anchors { right: parent.right; top: parent.top; rightMargin: 14; topMargin: 8 }
                    spacing: 8
                    PillButton { text: "◎ CENTER"; onClicked: stage.fit() }       // clear pan + re-fit, centering every screen
                    PillButton { text: "⊹ RESET";  onClicked: root.tidyLayout() }  // pack screens edge-to-edge, then re-fit
                }

                Item {
                    id: stage
                    clip: true
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16; topMargin: 38; bottomMargin: 16 }
                    // fit is STORED, recomputed only on load/resize — never during a drag, so moving
                    // one screen far away can't rescale or shrink the others
                    property real sc: 1
                    property real minX: 0
                    property real minY: 0
                    property real offX: 0
                    property real offY: 0
                    property real panX: 0   // right-drag view offset (px), cleared on fit/center
                    property real panY: 0
                    function fit() {
                        var on = root.modelList            // include disabled so they stay visible
                        if (!on.length) return
                        var aX=1e9,aY=1e9,bX=-1e9,bY=-1e9
                        for (var i=0;i<on.length;i++){ var m=on[i]
                            aX=Math.min(aX,m.x); aY=Math.min(aY,m.y)
                            bX=Math.max(bX,m.x+m.w); bY=Math.max(bY,m.y+m.h) }
                        var pad=20, sw=width-pad*2, sh=height-pad*2
                        var s=Math.min(sw/Math.max(1,bX-aX), sh/Math.max(1,bY-aY))*0.94
                        sc=s; minX=aX; minY=aY
                        offX=pad+(sw-(bX-aX)*s)/2; offY=pad+(sh-(bY-aY)*s)/2
                        panX=0; panY=0
                    }
                    onWidthChanged: fit()
                    onHeightChanged: fit()
                    Component.onCompleted: fit()
                    Connections { target: root; function onFitRevChanged(){ stage.fit() } }
                    // right-drag anywhere on the stage to pan the view. Sits BELOW the screen
                    // delegates; their MouseAreas only accept LeftButton, so right-clicks fall
                    // through to here even when they land on a screen.
                    MouseArea {
                        id: panArea
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor
                        property real px; property real py; property real spx; property real spy
                        onPressed: function(e){ px=e.x; py=e.y; spx=stage.panX; spy=stage.panY }
                        onPositionChanged: function(e){ if(!pressed) return
                            stage.panX = spx + (e.x - px); stage.panY = spy + (e.y - py) }
                    }
                    Repeater {
                        model: root.modelList
                        delegate: Rectangle {
                            required property var modelData
                            opacity: modelData.enabled ? 1.0 : 0.4   // disabled stays in the layout, greyed, still clickable
                            x: stage.offX + stage.panX + (modelData.x - stage.minX) * stage.sc
                            y: stage.offY + stage.panY + (modelData.y - stage.minY) * stage.sc
                            width: modelData.w * stage.sc
                            height: modelData.h * stage.sc
                            radius: 4
                            color: root.sel===modelData.name ? root.tint(root.cAmber,0.12) : root.tint(root.cSurface2,0.92)
                            // amber (theme tertiary) stroke throughout — full on the selected screen, softened on the rest
                            border.color: root.sel===modelData.name ? root.cAmber : root.tint(root.cAmber,0.45)
                            border.width: root.sel===modelData.name ? 2 : 1.5
                            Rectangle { x:5; y:5; width: Math.max(18,numT.width+8); height:18; radius:4; color: modelData.color
                                Text { id:numT; anchors.centerIn: parent; text: modelData.num; color:"#181211"; font.bold:true; font.pixelSize:11; font.family: root.fontFamily } }
                            Column { anchors.centerIn: parent; spacing: 1
                                Text { text: modelData.name; color: root.cText; font.bold:true; font.pixelSize:12; font.family: root.fontFamily; horizontalAlignment: Text.AlignHCenter; anchors.horizontalCenter: parent.horizontalCenter }
                                Text { text: modelData.enabled ? modelData.res : "OFF"; color: root.cMuted; font.pixelSize:10; font.family: root.fontFamily; horizontalAlignment: Text.AlignHCenter; anchors.horizontalCenter: parent.horizontalCenter } }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.SizeAllCursor
                                property real sx; property real sy; property int ox; property int oy
                                onPressed: function(e){ root.sel = modelData.name
                                    var p = mapToItem(stage, e.x, e.y); sx=p.x; sy=p.y; ox=modelData.x; oy=modelData.y }
                                onPositionChanged: function(e){
                                    if (!pressed) return
                                    var p = mapToItem(stage, e.x, e.y)
                                    var nx = Math.round(ox + (p.x - sx)/stage.sc)
                                    var ny = Math.round(oy + (p.y - sy)/stage.sc)
                                    var s = root.snap(modelData, nx, ny); s = root.resolveCollision(modelData, s[0], s[1])
                                    modelData.x = s[0]; modelData.y = s[1]; root.rev++
                                }
                            }
                        }
                    }
                }
            }

            // control panel
            Flickable {
                Layout.fillHeight: true; Layout.preferredWidth: 300; Layout.minimumWidth: 280
                contentWidth: width; contentHeight: panelCol.height; clip: true
                Column {
                    id: panelCol; width: parent.width; spacing: 12
                    padding: 18
                    property var m: { root.rev; root.sel; return root.current() }

                    Row { spacing: 8
                        Text { text: panelCol.m ? panelCol.m.name : "—"; color: root.cText; font.bold:true; font.pixelSize:15; font.letterSpacing:2; font.family: root.fontFamily }
                        Rectangle { visible: !!panelCol.m; height:18; radius:9; width: badgeT.width+14; anchors.verticalCenter: parent.verticalCenter
                            color:"transparent"; border.color: panelCol.m&&panelCol.m.enabled?root.cPrimary:root.cOutline
                            Text { id: badgeT; anchors.centerIn:parent; text: panelCol.m&&panelCol.m.enabled?"ACTIVE":"OFF"; font.pixelSize:9; font.letterSpacing:1; font.family: root.fontFamily; color: panelCol.m&&panelCol.m.enabled?root.cPrimary:root.cMuted } } }
                    Text { text: panelCol.m ? panelCol.m.make : ""; color: root.cMuted; font.pixelSize:11; font.family: root.fontFamily }

                    FieldRow { label: "Enabled"
                        Switch2 { checked: panelCol.m ? panelCol.m.enabled : false
                            onToggled: function(v){ if (panelCol.m){ panelCol.m.enabled=v; if(v) root.recalcSize(panelCol.m); root.activeCount=root.modelList.filter(function(x){return x.enabled}).length; root.rev++ } } } }
                    FieldRow { label: "Resolution"; enabled2: panelCol.m && panelCol.m.enabled
                        Dropdown { items: panelCol.m ? panelCol.m.resolutions : []; value: panelCol.m ? panelCol.m.res : ""
                            onPicked: function(v){ if(panelCol.m){ panelCol.m.res=v; var f=root.modesForRes(panelCol.m, v)[0]; panelCol.m.mode=f?root.modeStr(f):""; root.recalcSize(panelCol.m) } } } }
                    FieldRow { label: "Refresh"; enabled2: panelCol.m && panelCol.m.enabled
                        Dropdown { items: panelCol.hzList(); value: panelCol.m ? panelCol.m.mode : ""; labels: panelCol.hzLabels()
                            onPicked: function(v){ if(panelCol.m) panelCol.m.mode=v } } }
                    FieldRow { label: "Scale"; enabled2: panelCol.m && panelCol.m.enabled
                        Dropdown { items: root.scales; value: panelCol.m ? panelCol.m.scalev : ""
                            onPicked: function(v){ if(panelCol.m){ panelCol.m.scalev=v; root.recalcSize(panelCol.m) } } } }
                    FieldRow { label: "Rotation"; enabled2: panelCol.m && panelCol.m.enabled
                        Dropdown { items: root.rotations.map(function(r){return r[0]}); labels: root.rotations.map(function(r){return r[1]}); value: panelCol.m ? panelCol.m.transform : ""
                            onPicked: function(v){ if(panelCol.m){ panelCol.m.transform=v; root.recalcSize(panelCol.m) } } } }
                    FieldRow { label: "Position"; enabled2: panelCol.m && panelCol.m.enabled
                        Row { width: parent.width; spacing: 8
                            NumBox { width: (parent.width-8)/2; prefix:"X"; value: panelCol.m?panelCol.m.x:0; onCommitted: function(v){ if(panelCol.m){panelCol.m.x=v; root.rev++} } }
                            NumBox { width: (parent.width-8)/2; prefix:"Y"; value: panelCol.m?panelCol.m.y:0; onCommitted: function(v){ if(panelCol.m){panelCol.m.y=v; root.rev++} } } } }
                    FieldRow { label: "VRR"; enabled2: panelCol.m && panelCol.m.enabled && panelCol.m.vrrSupported
                        Dropdown { items: ["off","on","on-demand"]; labels: ["Off","On","On-demand"]; value: panelCol.m?panelCol.m.vrr:"off"
                            onPicked: function(v){ if(panelCol.m) panelCol.m.vrr=v } } }

                    function hzList(){ return m ? root.modesForRes(m, m.res).map(function(x){return root.modeStr(x)}) : [] }
                    function hzLabels(){ return m ? root.modesForRes(m, m.res).map(function(x){return (x.r/1000).toFixed(3)+" Hz"}) : [] }
                }
            }
        }

        // ---- footer ----
        Rectangle {
            id: footer; height: 52; color: "transparent"
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            Rectangle { anchors.top: parent.top; width: parent.width; height:1; color: root.cOutline }
            Rectangle {
                width: applyT.width+40; height: 34; radius: 6; color: root.cPrimary
                anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                Text { id: applyT; anchors.centerIn: parent; text: "APPLY"; color: root.cOnPrimary; font.bold:true; font.pixelSize:11; font.letterSpacing:1.5; font.family: root.fontFamily }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.applyAndSave() }
            }
        }
    }

    // ---- small UI components ----
    // compact toolbar pill (CENTER / RESET); amber stroke + tint on hover
    component PillButton: Rectangle {
        property string text: ""
        signal clicked()
        width: pillT.width + 18; height: 22; radius: 11
        color: pillMA.containsMouse ? root.tint(root.cAmber,0.16) : "transparent"
        border.color: pillMA.containsMouse ? root.cAmber : root.cOutline
        Text { id: pillT; anchors.centerIn: parent; text: parent.text; font.family: root.fontFamily; font.pixelSize: 9; font.letterSpacing: 1
            color: pillMA.containsMouse ? root.cAmber : root.cMuted }
        MouseArea { id: pillMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }
    component FieldRow: RowLayout {
        property string label; property bool enabled2: true
        default property alias content: holder.data
        width: parent ? parent.width - 36 : 240
        opacity: enabled2 ? 1 : 0.4; enabled: enabled2
        spacing: 10
        Text { text: parent.label; color: root.cMuted; font.pixelSize: 11; font.family: root.fontFamily; Layout.preferredWidth: 76 }
        Item { id: holder; Layout.fillWidth: true; implicitHeight: childrenRect.height }
    }
    component Switch2: Rectangle {
        property bool checked: false
        signal toggled(bool v)
        width: 42; height: 22; radius: 11
        color: checked ? root.tint(root.cPrimary,0.30) : root.cSurface3
        border.color: checked ? root.cPrimary : root.cOutline
        Rectangle { width:14; height:14; radius:7; y: 3; x: parent.checked ? 23 : 3
            color: parent.checked ? root.cPrimary : root.cMuted; Behavior on x { NumberAnimation { duration: 120 } } }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.toggled(!parent.checked) }
    }
    component NumBox: Rectangle {
        property string prefix; property int value: 0
        signal committed(int v)
        width: 96; height: 32; radius: 4; color: root.cSurface; border.color: root.cOutline
        Row { anchors.fill: parent; anchors.leftMargin: 8; spacing: 4
            Text { text: prefix; color: root.cMuted; font.pixelSize: 11; font.family: root.fontFamily; anchors.verticalCenter: parent.verticalCenter }
            TextInput { id: ti; width: parent.width-28; anchors.verticalCenter: parent.verticalCenter
                text: value; color: root.cText; font.pixelSize: 12; font.family: root.fontFamily
                selectByMouse: true; validator: IntValidator {}
                onEditingFinished: committed(parseInt(text)||0) } }
    }
    component Dropdown: Rectangle {
        property var items: []; property var labels: null; property string value: ""
        signal picked(string v)
        function labelFor(v){ if(!labels) return v; var i=items.indexOf(v); return (i>=0&&i<labels.length)?labels[i]:v }
        width: parent ? parent.width : 180; height: 32; radius: 4; color: root.cSurface; border.color: root.cOutline
        Text { anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            text: parent.labelFor(parent.value); color: root.cText; font.pixelSize: 12; font.family: root.fontFamily; elide: Text.ElideRight; width: parent.width-30 }
        Text { anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } text: "▾"; color: root.cMuted; font.pixelSize: 11 }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: pop.open() }
        Popup {
            id: pop; y: parent.height+4; width: parent.width; padding: 1
            background: Rectangle { color: root.cSurface3; border.color: root.cAmber; radius: 4 }
            contentItem: ListView { implicitHeight: Math.min(contentHeight, 220); model: items.length; clip: true
                delegate: Rectangle { width: pop.width-2; height: 28; color: ma.containsMouse ? root.tint(root.cAmber,0.18) : "transparent"
                    Text { anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
                        text: labelFor(items[index]); color: root.cText; font.pixelSize: 12; font.family: root.fontFamily }
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { picked(items[index]); pop.close() } } } }
        }
    }

    // ===== main window: a normal niri-managed toplevel (Super+Shift+T, focus, Mod+drag) =====
    FloatingWindow {
        id: deckWin
        title: "Display Deck"
        implicitWidth: 880
        implicitHeight: 560
        minimumSize: Qt.size(820, 520)        // never squish below usable
        color: "transparent"                   // transparent like the terminal (niri has no blur)
        Component.onCompleted: visible = true

        // real compositor blur via niri's KDE-blur protocol (same as kitty) — must attach to the window
        BackgroundEffect.blurRegion: deckBlur
        Region {
            id: deckBlur
            Region { x: 0; y: 0; width: deckWin.width; height: deckWin.height; radius: 14 }
        }

        Rectangle {
            id: content
            anchors.fill: parent
            radius: 14                              // match the blur region's rounded corners
            color: root.tint(root.cSurface, 0.6)   // translucent over REAL blur
            border.width: 1                         // thin amber (theme tertiary) frame stroke
            border.color: root.tint(root.cAmber, 0.55)
            focus: true
            clip: true                              // keep children inside the rounded frame
            Rectangle { anchors.fill: parent; radius: 14; gradient: Gradient {
                GradientStop { position: 0.0; color: root.tint(root.cAmber,0.05) }
                GradientStop { position: 1.0; color: "transparent" } } }
            DeckUI { anchors.fill: parent }
            Keys.onEscapePressed: Qt.quit()
        }
    }

    // ===== identify: a small frosted panel in each monitor's top-left corner =====
    Variants {
        model: root.identifyOn ? Quickshell.screens : []
        delegate: PanelWindow {
            id: idp
            required property var modelData
            property var om: root.byName(modelData.name)
            screen: modelData
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors { bottom: true; left: true }
            margins { bottom: 26; left: 26 }
            implicitWidth: 248; implicitHeight: 118
            color: "transparent"
            Rectangle {
                anchors.fill: parent; radius: 16; clip: true
                color: root.tint(root.cSurface,0.42)
                Row {
                    anchors.centerIn: parent; spacing: 16
                    Rectangle { width: 56; height: 56; radius: 12; anchors.verticalCenter: parent.verticalCenter
                        color: idp.om ? idp.om.color : root.cAmber
                        Text { anchors.centerIn: parent; text: idp.om ? idp.om.num : "?"; color: "#181211"
                            font.bold: true; font.pixelSize: 30; font.family: root.fontFamily } }
                    Column { anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        Text { text: modelData.name; color: root.cText; font.bold: true; font.pixelSize: 18; font.family: root.fontFamily }
                        Text { text: modelData.width + "×" + modelData.height; color: root.cMuted; font.pixelSize: 12; font.family: root.fontFamily } }
                }
            }
        }
    }
}
