//  水墨 · 便箋  —  Quickshell 右缘侧栏
//  放置于 ~/.config/quickshell/ink/shell.qml
//  启动:  quickshell -c ink
//  行为:  鼠标停在屏幕右缘 0.35s 滑出;移开鼠标约 1s 自动收回;
//         编辑中不会自动收回;Esc 退出编辑;数据落盘 notes.json

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    // ═══ 水墨配色(与 chinese-ink / waybar 同源) ═══
    readonly property color ink:      "#1f1c16"
    readonly property color inkSoft:  "#202020"
    readonly property color muted:    "#8a8171"
    readonly property color cinnabar: "#b83227"
    // 宣纸白 · 半透明
    readonly property color paper:     Qt.rgba(0.976, 0.972, 0.960, 0.86)
    readonly property color paperCard: Qt.rgba(1.0, 1.0, 1.0, 0.40)
    readonly property color inkLine:   Qt.rgba(0.08, 0.08, 0.08, 0.30)
    readonly property string zhFont:  "LXGW WenKai"
    readonly property int cornerRadius: 18

    property bool panelOpen: false
    property bool anyEditing: false
    property double pendingFocus: 0     // 新建便签后待聚焦的 created 时间戳

    // ═══ 数据:~/.cache/quickshell/ink/notes.json ═══
    ListModel { id: notesModel }

    FileView {
        id: notesFile
        path: Quickshell.env("HOME") + "/.cache/quickshell/ink/notes.json"
        blockLoading: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.loadNotes()
    }

    function loadNotes() {
        try {
            const arr = JSON.parse(notesFile.text());
            notesModel.clear();
            for (let i = 0; i < arr.length; i++)
                notesModel.append({ body: arr[i].body ?? "", created: arr[i].created ?? Date.now() });
        } catch (e) { /* 首次运行:文件不存在,从空开始 */ }
    }

    function saveNotes() {
        const arr = [];
        for (let i = 0; i < notesModel.count; i++) {
            const n = notesModel.get(i);
            arr.push({ body: n.body, created: n.created });
        }
        notesFile.setText(JSON.stringify(arr, null, 2));
    }

    function addNote() {
        const ts = Date.now();
        root.pendingFocus = ts;
        notesModel.insert(0, { body: "", created: ts });
        list.positionViewAtBeginning();
        saveTimer.restart();
    }

    Timer { id: saveTimer;  interval: 800; onTriggered: root.saveNotes() }
    Timer { id: openTimer;  interval: 350; onTriggered: root.panelOpen = true }
    Timer {
        id: closeTimer
        interval: 1000
        onTriggered: {
            if (!root.anyEditing && !hoverTrack.hovered) {
                root.panelOpen = false;
                root.saveNotes();
            }
        }
    }
    onAnyEditingChanged: if (!anyEditing && !hoverTrack.hovered) closeTimer.restart()

    // 可选:sway 绑键手动开关  →  qs -c ink ipc call panel toggle
    IpcHandler {
        target: "panel"
        function toggle(): void { root.panelOpen = !root.panelOpen }
    }

    // ═══ 天时:Open-Meteo · 十分钟一候 ═══
    // wxAuto = true 时按 IP 自动定位(城市级精度,挂 VPN 会定到出口节点);
    // 定位失败或 wxAuto = false 时,使用下面手填的坐标与地名
    property bool wxAuto: true
    property real wxLat: 52.51
    property real wxLon: 5.47
    property string wxPlace: "莱利斯塔德"

    QtObject {
        id: wx
        property bool ok: false
        property bool loading: true
        property int temp: 0
        property int code: 0
        property int humidity: 0
        property int wind: 0
        property int nowIdx: 0
        property var temps: []
        property var updated: new Date()
    }

    function wxDesc(c) {
        if (c === 0) return "晴";
        if (c === 1) return "晴间多云";
        if (c === 2) return "多云";
        if (c === 3) return "阴";
        if (c === 45 || c === 48) return "雾";
        if (c >= 51 && c <= 57) return "细雨";
        if (c === 61 || c === 66) return "小雨";
        if (c === 63) return "中雨";
        if (c === 65 || c === 67) return "大雨";
        if (c === 71) return "小雪";
        if (c === 73) return "中雪";
        if (c === 75 || c === 77) return "大雪";
        if (c >= 80 && c <= 82) return "阵雨";
        if (c === 85 || c === 86) return "阵雪";
        if (c >= 95) return "雷雨";
        return "未知";
    }

    // 时辰:更新时间以「巳时」「亥时」记
    function shichen(d) {
        const n = ["子","丑","寅","卯","辰","巳","午","未","申","酉","戌","亥"];
        return n[Math.floor(((d.getHours() + 1) % 24) / 2)] + "时";
    }

    // IP 定位:启动时与每 6 小时一次;成功后刷新天气
    function fetchLocation() {
        if (!root.wxAuto) { root.fetchWeather(); return; }
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try {
                    const d = JSON.parse(xhr.responseText);
                    if (d.success !== false && d.latitude !== undefined) {
                        root.wxLat = d.latitude;
                        root.wxLon = d.longitude;
                        if (d.city) root.wxPlace = d.city;
                    }
                } catch (e) { /* 解析失败:沿用现有坐标 */ }
            }
            root.fetchWeather();   // 无论定位成败,都取一次天气
        };
        xhr.open("GET", "https://ipwho.is/");
        xhr.send();
    }

    Timer {   // 每 6 小时重新定位(换网络/换地即自动跟随)
        interval: 21600000; running: root.wxAuto; repeat: true
        onTriggered: root.fetchLocation()
    }

    function fetchWeather() {
        wx.loading = true;
        const url = "https://api.open-meteo.com/v1/forecast"
            + "?latitude=" + root.wxLat + "&longitude=" + root.wxLon
            + "&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m"
            + "&hourly=temperature_2m&forecast_days=1&timezone=auto";
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            wx.loading = false;
            if (xhr.status === 200) {
                try {
                    const d = JSON.parse(xhr.responseText);
                    wx.temp = Math.round(d.current.temperature_2m);
                    wx.code = d.current.weather_code;
                    wx.humidity = Math.round(d.current.relative_humidity_2m);
                    wx.wind = Math.round(d.current.wind_speed_10m);
                    wx.temps = d.hourly.temperature_2m;
                    // 用 API 返回的当地时间取当前小时,不受本机时区影响
                    wx.nowIdx = parseInt(d.current.time.substring(11, 13));
                    wx.updated = new Date();
                    wx.ok = true;
                    wxChart.requestPaint();
                } catch (e) { wx.ok = false; wxRetry.restart(); }
            } else { wx.ok = false; wxRetry.restart(); }
        };
        xhr.open("GET", url);
        xhr.send();
    }

    Component.onCompleted: fetchLocation()   // 启动:先定位,链式取天气
    Timer {   // 十分钟一候(用已定位的坐标)
        interval: 600000; running: true; repeat: true
        onTriggered: root.fetchWeather()
    }
    Timer { id: wxRetry; interval: 90000; onTriggered: root.fetchWeather() }  // 失败 90s 后重试

    // ═══ 右缘触发带(6px 隐形热区) ═══
    PanelWindow {
        anchors { top: true; bottom: true; right: true }
        implicitWidth: 6
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        visible: !root.panelOpen
        WlrLayershell.namespace: "ink-trigger"
        WlrLayershell.layer: WlrLayer.Overlay

        // 悬停等待时浮现的朱砂细痕,提示即将唤出
        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: parent.height * 0.14
            radius: 2
            color: root.cinnabar
            opacity: triggerArea.containsMouse ? 0.7 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        MouseArea {
            id: triggerArea
            anchors.fill: parent
            hoverEnabled: true
            onEntered: openTimer.restart()
            onExited: openTimer.stop()
        }
    }

    // ═══ 便签面板 ═══
    PanelWindow {
        id: panel
        visible: root.panelOpen
        anchors { top: true; bottom: true; right: true }
        implicitWidth: 340
        margins { top: 75; right: 8; bottom: 28 }  // 避开 waybar，并给圆角留出显示空间
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "ink-notes"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.panelOpen ? WlrKeyboardFocus.OnDemand
                                                    : WlrKeyboardFocus.None

        Item {
            id: slide
            anchors.fill: parent
            x: root.panelOpen ? 0 : width
            Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

            // 悬停跟踪:HoverHandler 不与子级 MouseArea 抢事件
            HoverHandler {
                id: hoverTrack
                onHoveredChanged: hovered ? closeTimer.stop() : closeTimer.restart()
            }

            // 宣纸底
            Rectangle {
                anchors.fill: parent
                color: root.paper
                radius: root.cornerRadius
                antialiasing: true
                clip: true
                Rectangle {
                    width: 1
                    height: parent.height - root.cornerRadius * 2
                    y: root.cornerRadius
                    color: root.inkLine
                }  // 左缘淡墨描线
            }

            // ── 头部:朱砂小印 + 题字 + 新箋 + 收起 ──
            Item {
                id: header
                x: 18; y: 16
                width: parent.width - 36
                height: 34

                Rectangle {   // 印
                    id: seal
                    width: 26; height: 26
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.cinnabar
                    radius: 3
                    Text {
                        anchors.centerIn: parent
                        text: "箋"
                        color: "#f5f1e8"
                        font.family: root.zhFont
                        font.pixelSize: 15
                        font.bold: true
                    }
                }

                Text {
                    anchors.left: seal.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "片刻"
                    color: root.ink
                    font.family: root.zhFont
                    font.pixelSize: 17
                    font.letterSpacing: 2
                }

                // 收起
                Rectangle {
                    id: closeBtn
                    width: 26; height: 26
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    color: closeArea.containsMouse ? Qt.rgba(0.11, 0.10, 0.08, 0.08) : "transparent"
                    radius: 10
                    antialiasing: true
                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: closeArea.containsMouse ? root.cinnabar : root.muted
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { root.panelOpen = false; root.saveNotes(); }
                    }
                }

                // 新箋
                Rectangle {
                    id: addBtn
                    width: addLabel.width + 22; height: 26
                    anchors.right: closeBtn.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    color: addArea.containsMouse ? Qt.rgba(0.11, 0.10, 0.08, 0.08) : "transparent"
                    border.color: root.inkLine
                    border.width: 1
                    radius: 2
                    Text {
                        id: addLabel
                        anchors.centerIn: parent
                        text: "＋ 新箋"
                        color: root.ink
                        font.family: root.zhFont
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: addArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.addNote()
                    }
                }
            }

            Rectangle {   // 头部下的一笔墨线
                x: 18
                y: header.y + header.height + 10
                width: parent.width - 36
                height: 1
                color: root.inkLine
            }

            // ── 便签列表 ──
            ListView {
                id: list
                x: 18
                y: header.y + header.height + 22
                width: parent.width - 36
                height: weatherDivider.y - y - 12
                spacing: 10
                clip: true
                model: notesModel

                delegate: Rectangle {
                    width: list.width
                    height: noteCol.height + 22
                    color: root.paperCard
                    border.color: root.inkLine
                    border.width: 1
                    radius: 2

                    // 朱砂左缘,一抹印泥
                    Rectangle { width: 3; height: parent.height; color: root.cinnabar; opacity: 0.85 }

                    Column {
                        id: noteCol
                        x: 14; y: 11
                        width: parent.width - 28
                        spacing: 5

                        Item {
                            width: parent.width
                            height: 15
                            Text {
                                anchors.left: parent.left
                                text: Qt.formatDateTime(new Date(model.created), "M月d日 hh:mm")
                                color: root.muted
                                font.family: root.zhFont
                                font.pixelSize: 11
                            }
                            Text {
                                anchors.right: parent.right
                                text: "✕"
                                color: delArea.containsMouse ? root.cinnabar : Qt.rgba(0.54, 0.51, 0.44, 0.6)
                                font.pixelSize: 12
                                MouseArea {
                                    id: delArea
                                    anchors.fill: parent
                                    anchors.margins: -5
                                    hoverEnabled: true
                                    onClicked: { notesModel.remove(index); saveTimer.restart(); }
                                }
                            }
                        }

                        TextEdit {
                            id: editor
                            width: parent.width
                            text: model.body
                            wrapMode: TextEdit.Wrap
                            color: root.inkSoft
                            font.family: root.zhFont
                            font.pixelSize: 15
                            selectByMouse: true
                            selectionColor: Qt.rgba(0.11, 0.10, 0.08, 0.22)
                            selectedTextColor: "#000000"

                            onTextChanged: {
                                if (text !== model.body) {
                                    model.body = text;
                                    saveTimer.restart();
                                }
                            }
                            onActiveFocusChanged: root.anyEditing = activeFocus
                            Keys.onEscapePressed: editor.focus = false

                            // 新建的便签自动进入编辑
                            Component.onCompleted: {
                                if (model.created === root.pendingFocus) {
                                    root.pendingFocus = 0;
                                    editor.forceActiveFocus();
                                }
                            }

                            Text {   // 占位提示
                                visible: editor.text.length === 0 && !editor.activeFocus
                                text: "落墨于此……"
                                color: root.muted
                                font.family: root.zhFont
                                font.pixelSize: 15
                            }
                        }
                    }
                }
            }

            // 空态(与列表同区域,列表为空时居中显示)
            Text {
                visible: notesModel.count === 0
                anchors.centerIn: list
                text: "空山无墨\n点「新箋」落笔"
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.5
                color: root.muted
                font.family: root.zhFont
                font.pixelSize: 14
            }

            // ── 底部:天时一候 ──
            Rectangle {
                id: weatherDivider
                x: 18
                width: parent.width - 36
                height: 1
                color: root.inkLine
                anchors.bottom: weatherBlock.top
                anchors.bottomMargin: 10
            }

            Item {
                id: weatherBlock
                x: 18
                width: parent.width - 36
                height: 86
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 16

                // 标头:地名 + 时辰更新(点击可手动刷新)
                Item {
                    id: wxHeader
                    width: parent.width
                    height: 14
                    Text {
                        text: "天时 · " + root.wxPlace
                        color: root.muted
                        font.family: root.zhFont
                        font.pixelSize: 11
                        font.letterSpacing: 1
                    }
                    Text {
                        anchors.right: parent.right
                        text: wx.loading ? "观云中…"
                              : (wx.ok ? root.shichen(wx.updated) + "更新" : "取候未得")
                        color: wxRefresh.containsMouse ? root.cinnabar : root.muted
                        font.family: root.zhFont
                        font.pixelSize: 10
                        MouseArea {
                            id: wxRefresh
                            anchors.fill: parent
                            anchors.margins: -5
                            hoverEnabled: true
                            onClicked: root.fetchLocation()
                        }
                    }
                }

                Row {
                    anchors.top: wxHeader.bottom
                    anchors.topMargin: 9
                    width: parent.width
                    height: 54
                    spacing: 12

                    // 左:温度大字 + 天况 + 湿度风力
                    Column {
                        width: 104
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Row {
                            spacing: 8
                            Text {
                                text: wx.ok ? wx.temp + "°" : "--"
                                color: root.ink
                                font.family: root.zhFont
                                font.pixelSize: 26
                                font.bold: true
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: 4
                                text: wx.ok ? root.wxDesc(wx.code) : "…"
                                color: root.ink
                                font.family: root.zhFont
                                font.pixelSize: 14
                            }
                        }
                        Text {
                            text: wx.ok ? "湿 " + wx.humidity + "% · 风 " + wx.wind : ""
                            color: root.muted
                            font.family: root.zhFont
                            font.pixelSize: 10
                        }
                    }

                    // 右:今日温度走势,淡墨一线
                    Item {
                        width: parent.width - 104 - 12
                        height: parent.height

                        Canvas {
                            id: wxChart
                            anchors.fill: parent
                            onVisibleChanged: if (visible) requestPaint()
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);
                                const t = wx.temps;
                                if (!wx.ok || !t || t.length < 2) return;
                                const pad = 5;
                                let mn = Math.min(...t), mx = Math.max(...t);
                                if (mx - mn < 1) { mx += 0.5; mn -= 0.5; }
                                const X = i => pad + (width - 2 * pad) * i / (t.length - 1);
                                const Y = v => pad + (height - 2 * pad) * (1 - (v - mn) / (mx - mn));

                                // 墨线(中点平滑)
                                ctx.beginPath();
                                ctx.moveTo(X(0), Y(t[0]));
                                for (let i = 1; i < t.length; i++) {
                                    const xc = (X(i - 1) + X(i)) / 2;
                                    const yc = (Y(t[i - 1]) + Y(t[i])) / 2;
                                    ctx.quadraticCurveTo(X(i - 1), Y(t[i - 1]), xc, yc);
                                }
                                ctx.lineTo(X(t.length - 1), Y(t[t.length - 1]));
                                ctx.strokeStyle = Qt.rgba(0.11, 0.10, 0.08, 0.62);
                                ctx.lineWidth = 1.3;
                                ctx.stroke();

                                // 曲线下的淡墨晕染
                                ctx.lineTo(X(t.length - 1), height - 2);
                                ctx.lineTo(X(0), height - 2);
                                ctx.closePath();
                                ctx.fillStyle = Qt.rgba(0.11, 0.10, 0.08, 0.05);
                                ctx.fill();

                                // 此刻:朱砂一点
                                const i = Math.min(wx.nowIdx, t.length - 1);
                                ctx.beginPath();
                                ctx.arc(X(i), Y(t[i]), 2.6, 0, Math.PI * 2);
                                ctx.fillStyle = root.cinnabar;
                                ctx.fill();
                            }
                        }

                        // 高低温小注
                        Text {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            text: wx.ok && wx.temps.length ? "高 " + Math.round(Math.max(...wx.temps)) + "°" : ""
                            color: root.muted
                            font.family: root.zhFont
                            font.pixelSize: 9
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            text: wx.ok && wx.temps.length ? "低 " + Math.round(Math.min(...wx.temps)) + "°" : ""
                            color: root.muted
                            font.family: root.zhFont
                            font.pixelSize: 9
                        }

                        // 取数失败
                        Text {
                            visible: !wx.ok && !wx.loading
                            anchors.centerIn: parent
                            text: "云深不知处"
                            color: root.muted
                            font.family: root.zhFont
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }
}
