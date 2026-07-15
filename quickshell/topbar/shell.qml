//@ pragma UseQApplication

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.I3
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower

ShellRoot {
    id: root

    property bool powerOpen: false
    property var powerPopupScreen: null
    readonly property int popupCloseDelay: 2500
    property int memoryPercent: 0
    property string poemText: "山水有清音"
    property date now: new Date()
    property var workspaceNumbers: [1, 2, 3, 4, 5, 6, 7, 8]
    property var player: {
        const players = Mpris.players.values;
        for (let i = 0; i < players.length; i++)
            if (players[i].isPlaying) return players[i];
        return players.length > 0 ? players[0] : null;
    }
    property var sink: Pipewire.defaultAudioSink
    property var battery: UPower.displayDevice
    readonly property real batteryPercent: battery ? battery.percentage * 100 : 0
    property var wifiDevice: {
        const devices = Networking.devices.values;
        let fallback = null;
        for (let i = 0; i < devices.length; i++) {
            if (devices[i].type !== DeviceType.Wifi) continue;
            if (!fallback) fallback = devices[i];
            if (devices[i].connected) return devices[i];
        }
        return fallback;
    }
    property var wiredDevice: {
        const devices = Networking.devices.values;
        for (let i = 0; i < devices.length; i++)
            if (devices[i].type === DeviceType.Wired && devices[i].connected) return devices[i];
        return null;
    }
    property var activeNetwork: {
        if (!wifiDevice) return null;
        const networks = wifiDevice.networks.values;
        for (let i = 0; i < networks.length; i++)
            if (networks[i].connected) return networks[i];
        return null;
    }
    property bool wifiOpen: false
    property string wifiStage: "list"
    property var selectedNetwork: null
    property string wifiError: ""
    property var wifiPopupScreen: null
    property bool bluetoothOpen: false
    property var bluetoothPopupScreen: null
    property var selectedBluetoothDevice: null
    property string bluetoothError: ""
    property bool calendarOpen: false
    property var calendarPopupScreen: null
    property int calendarMonthOffset: 0

    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    FileView {
        id: poemCache
        path: Quickshell.env("HOME") + "/.cache/quickshell/topbar/poem.json"
        blockLoading: true
        atomicWrites: true
        printErrors: false
    }

    function cachedPoem() {
        try { return JSON.parse(poemCache.text()); }
        catch (e) { return {}; }
    }

    function refreshPoem() {
        const cached = root.cachedPoem();
        if (cached.content) root.poemText = cached.content;
        // 与旧脚本一致：缓存未满 30 分钟时不访问网络。
        if (cached.content && Date.now() - Number(cached.fetchedAt || 0) < 1800000) return;
        if (cached.token) root.requestPoem(cached.token, false);
        else root.fetchPoemToken();
    }

    function fetchPoemToken() {
        const tokenRequest = new XMLHttpRequest();
        tokenRequest.onreadystatechange = () => {
            if (tokenRequest.readyState !== XMLHttpRequest.DONE || tokenRequest.status !== 200) return;
            try {
                const token = JSON.parse(tokenRequest.responseText).data;
                if (!token) return;
                root.requestPoem(token, true);
            } catch (e) { console.warn("Failed to parse poetry token", e); }
        };
        tokenRequest.open("GET", "https://v2.jinrishici.com/token");
        tokenRequest.send();
    }

    function requestPoem(token, tokenIsFresh) {
        const sentenceRequest = new XMLHttpRequest();
        sentenceRequest.onreadystatechange = () => {
            if (sentenceRequest.readyState !== XMLHttpRequest.DONE) return;
            if (sentenceRequest.status !== 200) {
                if (!tokenIsFresh) root.fetchPoemToken();
                return;
            }
            try {
                const response = JSON.parse(sentenceRequest.responseText);
                if (response.status === "success" && response.data.content) {
                    const content = response.data.content.replace(/[\r\n\t]+/g, " ");
                    root.poemText = content;
                    poemCache.setText(JSON.stringify({
                        content: content,
                        fetchedAt: Date.now(),
                        token: token
                    }));
                } else if (!tokenIsFresh) root.fetchPoemToken();
            } catch (e) { console.warn("Failed to parse poetry response", e); }
        };
        sentenceRequest.open("GET", "https://v2.jinrishici.com/sentence");
        sentenceRequest.setRequestHeader("X-User-Token", token);
        sentenceRequest.send();
    }
    Process {
        id: memoryPoll
        command: ["sh", "-c", "awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf \"%d%%\",(t-a)*100/t}' /proc/meminfo"]
        stdout: StdioCollector { onStreamFinished: root.memoryPercent = parseInt(text) || 0 }
    }
    Timer {
        interval: 3000; running: true; repeat: true
        onTriggered: memoryPoll.running = true
    }
    Timer { interval: 60000; running: true; repeat: true; onTriggered: root.now = new Date() }
    Timer { interval: 600000; running: true; repeat: true; onTriggered: root.refreshPoem() }
    Timer {
        id: workspaceRefreshTimer
        interval: 60
        onTriggered: {
            I3.refreshWorkspaces();
            workspaceRebuildTimer.restart();
        }
    }
    Timer {
        id: workspaceRebuildTimer
        interval: 90
        onTriggered: root.rebuildWorkspaces()
    }
    Component.onCompleted: {
        workspaceRefreshTimer.restart();
        root.refreshPoem();
        memoryPoll.running = true;
    }

    function run(args) { Quickshell.execDetached(args); }
    function volume(delta) {
        if (!root.sink || !root.sink.audio) return;
        root.sink.audio.volume = Math.max(0, Math.min(1.5, root.sink.audio.volume + delta));
    }
    function batteryIcon(p) {
        const icons = ["󰁺","󰁻","󰁼","󰁽","󰁾","󰁿","󰂀","󰂁","󰂂","󰁹"];
        const charging = ["󰢜","󰂆","󰂇","󰂈","󰢝","󰂉","󰢞","󰂊","󰂋","󰂅"];
        if (root.battery && root.battery.state === UPowerDeviceState.FullyCharged) return "󰂅";
        if (root.battery && root.battery.state === UPowerDeviceState.Charging)
            return charging[Math.max(0, Math.min(9, Math.floor(p / 10)))];
        if (!UPower.onBattery) return "";
        return icons[Math.max(0, Math.min(9, Math.floor(p / 10)))];
    }
    function memoryIcon() {
        const icons = ["󰪞", "󰪟", "󰪠", "󰪡", "󰪢", "󰪣", "󰪤", "󰪥"];
        return icons[Math.max(0, Math.min(7, Math.floor(root.memoryPercent / 12.5)))];
    }
    function volumeIcon() {
        if (!root.sink || !root.sink.audio || root.sink.audio.muted) return "";
        const volume = root.sink.audio.volume;
        return volume < 0.34 ? "" : (volume < 0.67 ? "" : "");
    }
    function calendarBaseDate() {
        const now = root.now;
        return new Date(now.getFullYear(), now.getMonth() + root.calendarMonthOffset, 1);
    }
    function calendarCellDate(index) {
        const base = root.calendarBaseDate();
        const mondayFirst = (base.getDay() + 6) % 7;
        return new Date(base.getFullYear(), base.getMonth(), index - mondayFirst + 1);
    }
    function workspaceIcon(number) {
        const icons = ["", "󰲠", "󰲢", "󰲤", "󰲦", "󰲨", "󰲪", "󰲬", "󰲮", "󰲰", "󰿬"];
        return number >= 1 && number <= 10 ? icons[number] : "";
    }
    function workspaceByNumber(number) {
        const workspaces = I3.workspaces.values;
        for (let i = 0; i < workspaces.length; i++)
            if (Number(workspaces[i].number) === number) return workspaces[i];
        return null;
    }
    function networkIcon() {
        if (root.wiredDevice) return "󰌘";
        if (!Networking.wifiEnabled || !root.wifiDevice) return "󰤮";
        if (!root.activeNetwork) return "󰤯";
        const strength = root.activeNetwork.signalStrength;
        if (strength >= 0.8) return "󰤨";
        if (strength >= 0.6) return "󰤥";
        if (strength >= 0.4) return "󰤢";
        if (strength >= 0.2) return "󰤟";
        return "󰤯";
    }
    function bluetoothIcon() {
        const adapter = Bluetooth.defaultAdapter;
        if (!adapter || !adapter.enabled) return "󰂲";
        const devices = adapter.devices.values;
        for (let i = 0; i < devices.length; i++)
            if (devices[i].connected) return "";
        return "󰂯";
    }
    function closeBluetooth() {
        root.bluetoothOpen = false;
        root.bluetoothPopupScreen = null;
        root.selectedBluetoothDevice = null;
        root.bluetoothError = "";
        if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = false;
    }
    function closeCalendar() {
        root.calendarOpen = false;
        root.calendarPopupScreen = null;
    }
    function closePower() {
        root.powerOpen = false;
        root.powerPopupScreen = null;
    }
    function closeOtherPopups(except) {
        if (except !== "wifi") root.closeWifi();
        if (except !== "bluetooth") root.closeBluetooth();
        if (except !== "calendar") root.closeCalendar();
        if (except !== "power") root.closePower();
    }
    function toggleCalendar(screen) {
        const opening = !root.calendarOpen || root.calendarPopupScreen !== screen;
        root.closeOtherPopups("calendar");
        if (!opening) return root.closeCalendar();
        root.calendarPopupScreen = screen;
        root.calendarOpen = true;
    }
    function togglePower(screen) {
        const opening = !root.powerOpen || root.powerPopupScreen !== screen;
        root.closeOtherPopups("power");
        if (!opening) return root.closePower();
        root.powerPopupScreen = screen;
        root.powerOpen = true;
    }
    function toggleWifi(screen) {
        const opening = !root.wifiOpen || root.wifiPopupScreen !== screen;
        root.closeOtherPopups("wifi");
        if (!opening) return root.closeWifi();
        root.wifiPopupScreen = screen;
        root.wifiOpen = true;
        root.wifiStage = "list";
        root.selectedNetwork = null;
        root.wifiError = "";
        if (root.wifiDevice) root.wifiDevice.scannerEnabled = true;
    }
    function toggleBluetooth(screen) {
        const opening = !root.bluetoothOpen || root.bluetoothPopupScreen !== screen;
        root.closeOtherPopups("bluetooth");
        if (!opening) return root.closeBluetooth();
        root.bluetoothPopupScreen = screen;
        root.bluetoothOpen = true;
        root.bluetoothError = "";
        if (Bluetooth.defaultAdapter)
            Bluetooth.defaultAdapter.discovering = Bluetooth.defaultAdapter.enabled;
    }
    function toggleBluetoothDevice(device) {
        root.selectedBluetoothDevice = device;
        root.bluetoothError = "";
        if (device.connected) device.disconnect();
        else if (device.paired) device.connect();
        else device.pair();
    }
    function openWifi(network) {
        root.selectedNetwork = network;
        root.wifiError = "";
        root.wifiStage = network.connected ? "connected" : "password";
    }
    function connectWifi(password) {
        if (!root.selectedNetwork) return;
        root.wifiError = "";
        root.wifiStage = "connecting";
        if (root.selectedNetwork.known && password.length === 0)
            root.selectedNetwork.connect();
        else if (root.selectedNetwork.security === WifiSecurityType.Open)
            root.selectedNetwork.connect();
        else
            root.selectedNetwork.connectWithPsk(password);
    }
    function disconnectWifi() {
        if (!root.selectedNetwork) return;
        root.wifiError = "";
        root.wifiStage = "disconnecting";
        root.selectedNetwork.disconnect();
    }
    function closeWifi() {
        root.wifiOpen = false;
        root.wifiPopupScreen = null;
        root.wifiStage = "list";
        root.selectedNetwork = null;
        root.wifiError = "";
        if (root.wifiDevice) root.wifiDevice.scannerEnabled = false;
    }
    function rebuildWorkspaces() {
        const numbers = [1, 2, 3, 4, 5, 6, 7, 8];
        const values = I3.workspaces.values;
        for (let i = 0; i < values.length; i++) {
            const number = Number(values[i].number);
            if (number > 0 && numbers.indexOf(number) < 0) numbers.push(number);
        }
        numbers.sort((a, b) => a - b);
        root.workspaceNumbers = numbers;
    }

    Connections {
        target: I3
        function onRawEvent(event) { workspaceRefreshTimer.restart(); }
        function onConnected() { workspaceRefreshTimer.restart(); }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: barWindow
            required property var modelData
            screen: modelData
            anchors { top: true; left: true; right: true }
            implicitHeight: 50
            margins { top: 2; left: 10; right: 10 }
            color: "transparent"
            exclusionMode: ExclusionMode.Auto
            WlrLayershell.namespace: "ink-topbar"
            WlrLayershell.layer: WlrLayer.Top

            RowLayout {
                anchors.fill: parent
                spacing: 8

                InkCard {
                    id: poemCard
                    Layout.preferredWidth: Math.min(420, Math.max(180,
                        poemMark.implicitWidth + poemTextLabel.implicitWidth + 47))
                    radius: 16
                    Canvas {
                        parent: poemCard
                        anchors.fill: parent
                        onPaint: {
                            const ctx = getContext("2d");
                            const inset = 1.5;
                            const corner = 16;
                            ctx.clearRect(0, 0, width, height);
                            ctx.strokeStyle = Theme.cinnabar;
                            ctx.lineWidth = 3;
                            ctx.lineCap = "round";
                            ctx.beginPath();
                            ctx.moveTo(corner, inset);
                            ctx.quadraticCurveTo(inset, inset, inset, corner);
                            ctx.lineTo(inset, height - corner);
                            ctx.quadraticCurveTo(inset, height - inset, corner, height - inset);
                            ctx.stroke();
                        }
                    }
                    Row {
                        id: poemLabel
                        anchors.fill: parent
                        spacing: 7
                        BarText {
                            id: poemMark
                            height: parent.height
                            text: "詩"
                            color: Theme.cinnabar
                            font.family: Theme.chineseFont
                            font.weight: Font.Bold
                        }
                        BarText {
                            id: poemTextLabel
                            height: parent.height
                            width: parent.width - poemMark.width - parent.spacing
                            text: root.poemText
                            color: Theme.ink
                            font.family: Theme.chineseFont
                            elide: Text.ElideRight
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // 旧版 center3：媒体与音量共用一张卡片。
                InkCard {
                    Layout.preferredWidth: mediaControls.implicitWidth + 20
                    Row {
                        id: mediaControls
                        anchors.centerIn: parent
                        spacing: 10

                        Item {
                            width: 112; height: 32; clip: true
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                BarText {
                                    width: 17; height: 32
                                    text: !root.player ? "󰝛" : (root.player.isPlaying ? "" : "")
                                    color: Theme.ink
                                    font.pixelSize: 17
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                Item {
                                    id: mediaViewport
                                    width: 88; height: 28; clip: true
                                    readonly property string title: root.player
                                        ? (root.player.trackTitle || root.player.identity)
                                        : "No media"
                                    readonly property bool needsScroll: firstMediaTitle.implicitWidth > width
                                    onTitleChanged: {
                                        marqueeRow.x = 0;
                                        if (needsScroll) Qt.callLater(() => mediaScroll.restart());
                                    }
                                    Row {
                                        id: marqueeRow
                                        height: parent.height
                                        spacing: 0
                                        BarText {
                                            id: firstMediaTitle
                                            height: parent.height
                                            text: mediaViewport.title
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.verticalCenterOffset: 3
                                        }
                                        BarText {
                                            id: mediaSeparator
                                            height: parent.height
                                            text: "  ·  "
                                            visible: mediaViewport.needsScroll
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.verticalCenterOffset: 3
                                        }
                                        BarText {
                                            height: parent.height
                                            text: mediaViewport.title
                                            visible: mediaViewport.needsScroll
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.verticalCenterOffset: 3
                                        }
                                    }
                                    NumberAnimation {
                                        id: mediaScroll
                                        target: marqueeRow
                                        property: "x"
                                        from: 0
                                        to: -(firstMediaTitle.implicitWidth + mediaSeparator.implicitWidth)
                                        duration: Math.max(1600, (firstMediaTitle.implicitWidth + mediaSeparator.implicitWidth) * 70)
                                        easing.type: Easing.Linear
                                        loops: Animation.Infinite
                                        running: mediaViewport.needsScroll
                                        paused: mediaViewport.needsScroll && root.player
                                            ? !root.player.isPlaying
                                            : false
                                    }
                                }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.player) root.player.togglePlaying() }
                        }

                        Item {
                            width: volumeRow.implicitWidth
                            height: 34
                            Row {
                                id: volumeRow
                                height: parent.height
                                spacing: 5
                                BarText {
                                    width: 20; height: parent.height
                                    text: root.volumeIcon()
                                    font.pixelSize: 18
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                BarText {
                                    height: parent.height
                                    text: root.sink && root.sink.audio && !root.sink.audio.muted ? Math.round(root.sink.audio.volume * 100) + "%" : ""
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.sink && root.sink.audio)
                                    root.sink.audio.muted = !root.sink.audio.muted
                                onWheel: function(wheel) {
                                    if (wheel.angleDelta.y === 0) return;
                                    root.volume(wheel.angleDelta.y > 0 ? 0.03 : -0.03);
                                    wheel.accepted = true;
                                }
                            }
                        }
                    }
                }

                // 旧版 center2：时钟、电池、内存、托盘、电源。
                InkCard {
                    Layout.preferredWidth: rightStatusRow.implicitWidth + 20
                    Row {
                        id: rightStatusRow
                        anchors.centerIn: parent
                        spacing: 10

                        BarText {
                            id: clock
                            height: 34
                            text: Qt.formatDateTime(root.now, "MM/dd HH:mm")
                            font.weight: Font.Bold
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -5
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    if (mouse.button === Qt.MiddleButton) root.calendarMonthOffset = 0;
                                    else root.toggleCalendar(modelData);
                                }
                                onWheel: wheel => root.calendarMonthOffset += wheel.angleDelta.y > 0 ? -1 : 1
                            }
                        }
                        Row {
                            visible: root.battery && root.battery.isPresent
                            height: 34
                            spacing: 5
                            BarText {
                                height: parent.height
                                color: root.batteryPercent <= 20 ? Theme.cinnabar : Theme.ink
                                text: Math.round(root.batteryPercent) + "%"
                                font.weight: root.batteryPercent <= 10 ? Font.Black : Font.DemiBold
                            }
                            BarText {
                                width: 20; height: parent.height
                                color: root.batteryPercent <= 20 ? Theme.cinnabar : Theme.ink
                                text: root.batteryIcon(root.batteryPercent)
                                font.pixelSize: 18
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                        BarText {
                            width: 22; height: 34
                            text: root.memoryIcon()
                            font.pixelSize: 18
                            horizontalAlignment: Text.AlignHCenter
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -5
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.run(["alacritty", "-e", "btop"])
                            }
                        }
                        Row {
                            spacing: 8
                            Repeater {
                                model: SystemTray.items
                                delegate: Item {
                                    id: trayEntry
                                    required property var modelData
                                    width: 18; height: 34
                                    IconImage { anchors.centerIn: parent; width: 16; height: 16; source: modelData.icon }
                                    MouseArea {
                                        id: trayMouse
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        cursorShape: Qt.PointingHandCursor
                                        function showMenu(x, y) {
                                            const point = trayMouse.mapToItem(barWindow.contentItem, x, y);
                                            modelData.display(barWindow, Math.round(point.x), Math.round(point.y));
                                        }
                                        onClicked: function(mouse) {
                                            if (mouse.button === Qt.RightButton) {
                                                if (modelData.hasMenu) showMenu(mouse.x, mouse.y);
                                                else modelData.secondaryActivate();
                                            } else if (modelData.onlyMenu && modelData.hasMenu) {
                                                showMenu(mouse.x, mouse.y);
                                            } else {
                                                modelData.activate();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        BarText {
                            width: 20; height: 34
                            text: "⏻"; color: Theme.cinnabar; font.pixelSize: 17
                            horizontalAlignment: Text.AlignHCenter
                            MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: root.togglePower(modelData) }
                        }
                    }
                }
            }

            InkCard {
                id: workspaceCard
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: workspaceRow.implicitWidth + 24
                height: 38
                z: 1
                Row {
                    id: workspaceRow
                    anchors.centerIn: parent
                    height: parent.height
                    spacing: 2
                    Repeater {
                        model: root.workspaceNumbers
                        delegate: Item {
                            required property int modelData
                            readonly property int workspaceNumber: modelData
                            readonly property var workspace: root.workspaceByNumber(workspaceNumber)
                            readonly property bool isFocused: I3.focusedWorkspace
                                ? Number(I3.focusedWorkspace.number) === workspaceNumber
                                : false
                            readonly property bool isUrgent: workspace ? workspace.urgent : false
                            readonly property bool isEmpty: !workspace || !String(workspace.lastIpcObject.representation || "")
                            width: 27; height: parent.height
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                width: 15; height: 3; radius: 1.5
                                color: Theme.cinnabar
                                opacity: parent.isFocused ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 50 } }
                            }
                            BarText {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: parent.isFocused ? -1 : 0
                                text: root.workspaceIcon(parent.workspaceNumber)
                                color: parent.isUrgent ? Theme.cinnabar : (parent.isEmpty ? Theme.muted : Theme.ink)
                                opacity: parent.isFocused || hover.containsMouse ? 1 : (parent.isEmpty ? 0.55 : 1)
                                font.pixelSize: 18
                                font.weight: Font.Normal
                                Behavior on opacity { NumberAnimation { duration: 50 } }
                            }
                            MouseArea {
                                id: hover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: I3.dispatch("workspace number " + parent.workspaceNumber)
                            }
                        }
                    }
                    Item {
                        width: 27; height: parent.height
                        BarText {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 2
                            text: root.networkIcon()
                            font.pixelSize: 19
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: root.wifiDevice !== null
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.toggleWifi(modelData)
                        }
                    }
                    Item {
                        width: Bluetooth.defaultAdapter ? 27 : 0; height: parent.height
                        BarText {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 2
                            text: root.bluetoothIcon()
                            font.pixelSize: 19
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleBluetooth(modelData)
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: root.selectedNetwork
        ignoreUnknownSignals: true
        function onConnectedChanged() {
            if (root.selectedNetwork && root.selectedNetwork.connected) root.closeWifi();
            else if (root.selectedNetwork && root.wifiStage === "disconnecting") root.closeWifi();
        }
        function onConnectionFailed(reason) {
            root.wifiStage = "password";
            root.wifiError = "Connection failed. Check the password and try again.";
            passwordFocus.restart();
        }
    }

    PanelWindow {
        id: calendarPopup
        visible: root.calendarOpen && root.calendarPopupScreen !== null
        screen: root.calendarPopupScreen
        anchors { top: true; right: true }
        margins { top: 52; right: 92 }
        implicitWidth: 300
        implicitHeight: 292
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "ink-calendar"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        Timer {
            interval: root.popupCloseDelay
            running: calendarPopup.visible && !calendarPopupHover.hovered
            onTriggered: root.closeCalendar()
        }

        Rectangle {
            id: calendarPopupSurface
            anchors.fill: parent
            radius: 16
            color: Qt.rgba(0.976, 0.972, 0.960, 0.96)
            border.color: Theme.border
            HoverHandler { id: calendarPopupHover }

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8

                Row {
                    width: parent.width; height: 34
                    BarText {
                        width: 36; height: parent.height; text: "‹"; font.pixelSize: 22; horizontalAlignment: Text.AlignHCenter
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.calendarMonthOffset-- }
                    }
                    BarText {
                        width: parent.width - 72; height: parent.height
                        text: Qt.locale("en_US").toString(root.calendarBaseDate(), "MMMM yyyy")
                        color: Theme.ink
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        horizontalAlignment: Text.AlignHCenter
                    }
                    BarText {
                        width: 36; height: parent.height; text: "›"; font.pixelSize: 22; horizontalAlignment: Text.AlignHCenter
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.calendarMonthOffset++ }
                    }
                }

                Grid {
                    width: parent.width
                    columns: 7
                    Repeater {
                        model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                        delegate: BarText {
                            required property string modelData
                            width: 38; height: 25
                            text: modelData
                            color: Theme.muted
                            font.family: Theme.chineseFont
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                Grid {
                    width: parent.width
                    columns: 7
                    Repeater {
                        model: 42
                        delegate: Item {
                            required property int index
                            readonly property date cellDate: root.calendarCellDate(index)
                            readonly property date today: root.now
                            readonly property bool inMonth: cellDate.getMonth() === root.calendarBaseDate().getMonth()
                            readonly property bool isToday: cellDate.getFullYear() === today.getFullYear()
                                                            && cellDate.getMonth() === today.getMonth()
                                                            && cellDate.getDate() === today.getDate()
                            width: 38; height: 31
                            Rectangle {
                                anchors.centerIn: parent
                                width: 27; height: 27; radius: 14
                                color: parent.isToday ? Theme.cinnabar : "transparent"
                            }
                            BarText {
                                anchors.centerIn: parent
                                text: parent.cellDate.getDate()
                                color: parent.isToday ? "white" : (parent.inMonth ? Theme.ink : Theme.muted)
                                opacity: parent.inMonth || parent.isToday ? 1 : 0.42
                                font.weight: parent.isToday ? Font.Bold : Font.Normal
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }
            }
        }
        Shortcut { sequence: "Escape"; onActivated: root.closeCalendar() }
    }

    Timer {
        id: passwordFocus
        interval: 60
        onTriggered: { wifiPassword.forceActiveFocus(); wifiPassword.selectAll(); }
    }

    PanelWindow {
        id: wifiPopup
        visible: root.wifiOpen && root.wifiPopupScreen !== null
        screen: root.wifiPopupScreen
        anchors { top: true; left: true }
        margins {
            top: 52
            left: wifiPopup.screen ? Math.round((wifiPopup.screen.width - wifiPopup.implicitWidth) / 2) : 0
        }
        implicitWidth: 350
        implicitHeight: root.wifiStage === "list" ? 390 : 190
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "ink-wifi"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Timer {
            interval: root.popupCloseDelay
            running: wifiPopup.visible && !wifiPopupHover.hovered
            onTriggered: root.closeWifi()
        }

        Rectangle {
            id: wifiPopupSurface
            anchors.fill: parent
            color: Qt.rgba(0.976, 0.972, 0.960, 0.96)
            border.color: Theme.border
            border.width: 1
            radius: 16
            clip: true
            HoverHandler { id: wifiPopupHover }

            Item {
                anchors.fill: parent
                anchors.margins: 12

                Column {
                    visible: root.wifiStage === "list"
                    anchors.fill: parent
                    spacing: 8

                    Row {
                        width: parent.width
                        height: 34
                        BarText {
                            width: parent.width - 38
                            text: "Wireless Networks"
                            color: Theme.cinnabar
                            font.pixelSize: 17
                        }
                        BarText {
                            width: 38
                            text: Networking.wifiEnabled ? "󰖩" : "󰖪"
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: 17
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                            }
                        }
                    }

                    ListView {
                        width: parent.width
                        height: parent.height - 42
                        clip: true
                        spacing: 4
                        model: root.wifiDevice ? root.wifiDevice.networks : null
                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width
                            height: 46
                            radius: 10
                            color: networkHover.containsMouse ? Qt.rgba(0.72, 0.20, 0.15, 0.08) : "transparent"

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 9
                                BarText {
                                    width: 22; height: parent.height
                                    text: modelData.connected ? "󰤨" : (modelData.signalStrength >= 0.65 ? "󰤥" : modelData.signalStrength >= 0.35 ? "󰤢" : "󰤟")
                                    color: modelData.connected ? Theme.cinnabar : Theme.ink
                                    font.pixelSize: 17
                                }
                                BarText {
                                    width: parent.width - 96; height: parent.height
                                    text: modelData.name
                                    elide: Text.ElideRight
                                }
                                BarText {
                                    width: 20; height: parent.height
                                    text: modelData.security === WifiSecurityType.Open ? "" : "󰌾"
                                    color: Theme.muted
                                }
                                Item {
                                    width: 24; height: parent.height
                                    visible: modelData.connected
                                    BarText {
                                        anchors.centerIn: parent
                                        text: root.wifiStage === "disconnecting" && root.selectedNetwork === modelData ? "󰑓" : "󰅖"
                                        color: Theme.cinnabar
                                        font.pixelSize: 15
                                        RotationAnimator on rotation {
                                            from: 0; to: 360; duration: 850; loops: Animation.Infinite
                                            running: root.wifiStage === "disconnecting" && root.selectedNetwork === modelData
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.selectedNetwork = modelData;
                                            root.disconnectWifi();
                                        }
                                    }
                                }
                            }
                            MouseArea {
                                id: networkHover
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: parent.right }
                                anchors.rightMargin: modelData.connected ? 34 : 0
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!modelData.connected) {
                                        root.openWifi(modelData);
                                        passwordFocus.restart();
                                    }
                                }
                            }
                        }
                    }
                }

                Column {
                    visible: root.wifiStage !== "list"
                    anchors.fill: parent
                    spacing: 12

                    BarText {
                        width: parent.width
                        text: root.selectedNetwork ? root.selectedNetwork.name : ""
                        color: Theme.cinnabar
                        font.family: Theme.chineseFont
                        font.pixelSize: 18
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Rectangle {
                        visible: root.wifiStage === "password"
                        width: parent.width
                        height: 42
                        radius: 10
                        color: Qt.rgba(1, 1, 1, 0.45)
                        border.color: wifiPassword.activeFocus ? Theme.cinnabar : Theme.border
                        border.width: 1

                        TextInput {
                            id: wifiPassword
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.ink
                            selectionColor: Theme.cinnabar
                            selectedTextColor: "white"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            echoMode: TextInput.Password
                            passwordCharacter: "●"
                            Keys.onReturnPressed: root.connectWifi(text)
                            onVisibleChanged: if (visible) { text = ""; passwordFocus.restart(); }
                        }
                        BarText {
                            visible: !wifiPassword.text && !wifiPassword.activeFocus
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.selectedNetwork && root.selectedNetwork.known
                                ? "Leave blank to use the saved password"
                                : "Enter Wi-Fi password"
                            color: Theme.muted
                            font.weight: Font.Normal
                        }
                    }

                    Item {
                        visible: root.wifiStage === "connecting" || root.wifiStage === "disconnecting"
                        width: parent.width
                        height: 48
                        BarText {
                            id: wifiSpinner
                            anchors.centerIn: parent
                            text: "󰑓"
                            color: Theme.cinnabar
                            font.pixelSize: 25
                            RotationAnimator on rotation { from: 0; to: 360; duration: 850; loops: Animation.Infinite; running: wifiSpinner.visible }
                        }
                    }

                    Rectangle {
                        visible: root.wifiStage === "connected"
                        width: parent.width
                        height: 42
                        radius: 10
                        color: disconnectHover.hovered ? Qt.rgba(0.72, 0.20, 0.15, 0.14) : Qt.rgba(0.72, 0.20, 0.15, 0.08)
                        border.color: Theme.cinnabar
                        border.width: 1

                        BarText {
                            anchors.centerIn: parent
                            text: "Disconnect"
                            color: Theme.cinnabar
                            font.pixelSize: 14
                        }
                        HoverHandler { id: disconnectHover }
                        TapHandler { onTapped: root.disconnectWifi() }
                    }

                    BarText {
                        visible: root.wifiStage === "disconnecting"
                        width: parent.width
                        text: "Disconnecting…"
                        color: Theme.muted
                        horizontalAlignment: Text.AlignHCenter
                        font.weight: Font.Normal
                    }

                    BarText {
                        visible: root.wifiError.length > 0
                        width: parent.width
                        text: root.wifiError
                        color: Theme.cinnabar
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: 11
                    }

                    BarText {
                        visible: root.wifiStage === "password"
                        width: parent.width
                        text: "Enter to connect  ·  Esc to go back"
                        color: Theme.muted
                        horizontalAlignment: Text.AlignHCenter
                        font.weight: Font.Normal
                        font.pixelSize: 11
                    }
                }
            }
        }

        Shortcut {
            sequence: "Escape"
            onActivated: {
                if (root.wifiStage === "list") root.closeWifi();
                else { root.wifiStage = "list"; root.selectedNetwork = null; root.wifiError = ""; }
            }
        }
    }

    Connections {
        target: root.selectedBluetoothDevice
        ignoreUnknownSignals: true
        function onPairedChanged() {
            if (root.selectedBluetoothDevice && root.selectedBluetoothDevice.paired && !root.selectedBluetoothDevice.connected)
                root.selectedBluetoothDevice.connect();
        }
    }

    PanelWindow {
        id: bluetoothPopup
        visible: root.bluetoothOpen && root.bluetoothPopupScreen !== null
        screen: root.bluetoothPopupScreen
        anchors { top: true; left: true }
        margins {
            top: 52
            left: bluetoothPopup.screen ? Math.round((bluetoothPopup.screen.width - bluetoothPopup.implicitWidth) / 2 + 34) : 0
        }
        implicitWidth: 350
        implicitHeight: 390
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "ink-bluetooth"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        Timer {
            interval: root.popupCloseDelay
            running: bluetoothPopup.visible && !bluetoothPopupHover.hovered
            onTriggered: root.closeBluetooth()
        }

        Rectangle {
            id: bluetoothPopupSurface
            anchors.fill: parent
            color: Qt.rgba(0.976, 0.972, 0.960, 0.96)
            border.color: Theme.border
            border.width: 1
            radius: 16
            clip: true
            HoverHandler { id: bluetoothPopupHover }

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                Row {
                    width: parent.width
                    height: 34
                    BarText {
                        width: parent.width - 38
                        text: "Bluetooth Devices"
                        color: Theme.cinnabar
                        font.pixelSize: 17
                    }
                    BarText {
                        width: 38
                        text: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled ? "󰂯" : "󰂲"
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: 18
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!Bluetooth.defaultAdapter) return;
                                const enable = !Bluetooth.defaultAdapter.enabled;
                                Bluetooth.defaultAdapter.enabled = enable;
                                Bluetooth.defaultAdapter.discovering = enable;
                            }
                        }
                    }
                }

                ListView {
                    width: parent.width
                    height: parent.height - 42
                    clip: true
                    spacing: 4
                    model: Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.devices : null
                    delegate: Rectangle {
                        id: btDeviceRow
                        required property var modelData
                        width: ListView.view.width
                        height: 46
                        radius: 10
                        color: bluetoothHover.containsMouse ? Qt.rgba(0.72, 0.20, 0.15, 0.08) : "transparent"
                        readonly property bool busy: modelData.state === BluetoothDeviceState.Connecting
                                                     || modelData.state === BluetoothDeviceState.Disconnecting
                                                     || modelData.pairing

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 9
                            BarText {
                                width: 22; height: parent.height
                                text: modelData.connected ? "" : "󰂯"
                                color: modelData.connected ? Theme.cinnabar : Theme.ink
                                font.pixelSize: 17
                            }
                            BarText {
                                width: parent.width - 112; height: parent.height
                                text: modelData.name || modelData.deviceName || modelData.address
                                elide: Text.ElideRight
                            }
                            BarText {
                                width: 28; height: parent.height
                                visible: modelData.batteryAvailable
                                text: Math.round(modelData.battery * 100) + "%"
                                color: Theme.muted
                                font.pixelSize: 10
                            }
                            BarText {
                                width: 18; height: parent.height
                                text: modelData.paired ? "󰌾" : ""
                                color: Theme.muted
                            }
                            Item {
                                width: 24; height: parent.height
                                BarText {
                                    anchors.centerIn: parent
                                    text: btDeviceRow.busy ? "󰑓" : (modelData.connected ? "󰅖" : "󰐕")
                                    color: modelData.connected ? Theme.cinnabar : Theme.ink
                                    font.pixelSize: 15
                                    RotationAnimator on rotation {
                                        from: 0; to: 360; duration: 850; loops: Animation.Infinite
                                        running: btDeviceRow.busy
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: !btDeviceRow.busy
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleBluetoothDevice(modelData)
                                }
                            }
                        }
                        MouseArea {
                            id: bluetoothHover
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: parent.right }
                            anchors.rightMargin: 34
                            hoverEnabled: true
                            enabled: !parent.busy
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (!modelData.connected) root.toggleBluetoothDevice(modelData)
                        }
                    }
                }
            }
        }

        Shortcut { sequence: "Escape"; onActivated: root.closeBluetooth() }
    }

    PanelWindow {
        id: powerPopup
        visible: root.powerOpen
        screen: root.powerPopupScreen
        anchors { top: true; right: true }
        margins { top: 56; right: 18 }
        implicitWidth: 200; implicitHeight: 230
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "ink-power"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        Timer {
            interval: root.popupCloseDelay
            running: powerPopup.visible && !powerPopupHover.hovered
            onTriggered: root.closePower()
        }

        Rectangle {
            id: powerPopupSurface
            anchors.fill: parent; radius: 18; color: Qt.rgba(0.976, 0.972, 0.960, 0.94); border.color: Theme.border
            HoverHandler { id: powerPopupHover }
            Column {
                anchors.fill: parent; anchors.margins: 14; spacing: 7
                BarText { text: "Power"; color: Theme.cinnabar; font.pixelSize: 17; height: 30 }
                Repeater {
                    model: [
                        { label: "󰌾  Lock", cmd: ["swaylock", "-f"] },
                        { label: "󰍃  Log out of Sway", cmd: ["swaymsg", "exit"] },
                        { label: "󰜉  Restart", cmd: ["systemctl", "reboot"] },
                        { label: "󰐥  Shut down", cmd: ["systemctl", "poweroff"] }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width; height: 36; radius: 10; color: hover.hovered ? Qt.rgba(0.72,0.20,0.15,0.10) : "transparent"
                        BarText { anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: modelData.label }
                        HoverHandler { id: hover }
                        TapHandler { onTapped: { root.closePower(); root.run(modelData.cmd) } }
                    }
                }
            }
        }
        Shortcut { sequence: "Escape"; onActivated: root.closePower() }
    }
}
