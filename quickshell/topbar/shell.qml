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
    property int memoryPercent: 0
    property string poemText: "山水有清音"
    property var workspaceNumbers: [1, 2, 3, 4, 5, 6, 7, 8]
    property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
    property var sink: Pipewire.defaultAudioSink
    property var battery: UPower.displayDevice
    readonly property real batteryPercent: battery ? battery.percentage * 100 : 0
    property var wifiDevice: {
        const devices = Networking.devices.values;
        for (let i = 0; i < devices.length; i++)
            if (devices[i].type === DeviceType.Wifi) return devices[i];
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
            } catch (e) { console.warn("诗词令牌解析失败", e); }
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
            } catch (e) { console.warn("诗词响应解析失败", e); }
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
    Timer { interval: 600000; running: true; repeat: true; onTriggered: root.refreshPoem() }
    Component.onCompleted: { root.rebuildWorkspaces(); root.refreshPoem(); memoryPoll.running = true }

    Process { id: action; command: []; running: false }
    function run(args) { action.command = args; action.running = true }
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
        const now = new Date();
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
    function wifiIcon() {
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
        root.selectedBluetoothDevice = null;
        root.bluetoothError = "";
        if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = false;
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
        function onRawEvent(event) { root.rebuildWorkspaces(); }
        function onConnected() { root.rebuildWorkspaces(); }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
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
                    Layout.preferredWidth: Math.min(420, Math.max(180, poemLabel.implicitWidth + 30))
                    Rectangle { width: 3; height: 24; radius: 2; color: Theme.cinnabar; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
                    Row {
                        id: poemLabel
                        anchors.centerIn: parent
                        spacing: 7
                        BarText {
                            text: "詩"
                            color: Theme.cinnabar
                            font.family: Theme.chineseFont
                            font.weight: Font.Bold
                        }
                        BarText {
                            text: root.poemText
                            color: Theme.ink
                            font.family: Theme.chineseFont
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                InkCard {
                    horizontalPadding: 6
                    Layout.preferredWidth: root.workspaceNumbers.length * 28 + 64
                    Row {
                        anchors.centerIn: parent
                        spacing: 2
                        Repeater {
                            model: root.workspaceNumbers
                            delegate: Item {
                                required property int modelData
                                readonly property int workspaceNumber: modelData
                                readonly property var workspace: I3.findWorkspaceByName(String(workspaceNumber))
                                readonly property bool isFocused: workspace ? workspace.focused : false
                                readonly property bool isUrgent: workspace ? workspace.urgent : false
                                readonly property bool isEmpty: !workspace || !String(workspace.lastIpcObject.representation || "")
                                width: 27; height: 34
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: parent.top
                                    width: parent.width; height: 3; radius: 0
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
                            width: 27; height: 34
                            BarText {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: 2
                                text: root.wifiIcon()
                                font.pixelSize: 19
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.wifiPopupScreen = modelData;
                                    root.wifiOpen = !root.wifiOpen;
                                    root.wifiStage = "list";
                                    root.selectedNetwork = null;
                                    root.wifiError = "";
                                    if (root.wifiDevice) root.wifiDevice.scannerEnabled = root.wifiOpen;
                                }
                            }
                        }
                        Item {
                            width: Bluetooth.defaultAdapter ? 27 : 0; height: 34
                            BarText {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: 2
                                text: root.bluetoothIcon()
                                font.pixelSize: 19
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.bluetoothPopupScreen = modelData;
                                    root.bluetoothOpen = !root.bluetoothOpen;
                                    root.bluetoothError = "";
                                    if (Bluetooth.defaultAdapter)
                                        Bluetooth.defaultAdapter.discovering = root.bluetoothOpen && Bluetooth.defaultAdapter.enabled;
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // 旧版 center3：媒体与音量共用一张卡片。
                InkCard {
                    Layout.preferredWidth: 205
                    Row {
                        anchors.centerIn: parent
                        spacing: 10

                        Item {
                            width: 112; height: 32; clip: true
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                BarText {
                                    width: 17; height: 32
                                    text: root.player && !root.player.isPlaying ? "" : ""
                                    color: Theme.ink
                                    font.pixelSize: 17
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                Item {
                                    width: 88; height: 28; clip: true
                                    BarText {
                                        id: mediaTitle
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.player ? (root.player.trackTitle || root.player.identity) : "暂无播放"
                                        x: 0
                                        SequentialAnimation on x {
                                            running: root.player && root.player.isPlaying && mediaTitle.implicitWidth > mediaTitle.parent.width
                                            loops: Animation.Infinite
                                            PauseAnimation { duration: 900 }
                                            NumberAnimation {
                                                from: 0
                                                to: -(mediaTitle.implicitWidth - mediaTitle.parent.width)
                                                duration: Math.max(900, (mediaTitle.implicitWidth - mediaTitle.parent.width) * 70)
                                                easing.type: Easing.Linear
                                            }
                                            PauseAnimation { duration: 700 }
                                            ScriptAction { script: mediaTitle.x = 0 }
                                        }
                                    }
                                }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.player) root.player.togglePlaying() }
                        }

                        Row {
                            height: 34
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
                            TapHandler { onTapped: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted }
                            WheelHandler { onWheel: event => root.volume(event.angleDelta.y > 0 ? 0.03 : -0.03) }
                        }
                    }
                }

                // 旧版 center2：时钟、电池、内存、托盘、电源。
                InkCard {
                    Layout.preferredWidth: SystemTray.items.values.length * 26 + 260
                    Row {
                        anchors.centerIn: parent
                        spacing: 10

                        BarText {
                            id: clock
                            height: 34
                            property date now: new Date()
                            text: Qt.formatDateTime(now, "MM/dd HH:mm")
                            font.weight: Font.Bold
                            Timer { interval: 60000; running: true; repeat: true; onTriggered: clock.now = new Date() }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -5
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    if (mouse.button === Qt.MiddleButton) root.calendarMonthOffset = 0;
                                    else {
                                        root.calendarPopupScreen = modelData;
                                        root.calendarOpen = !root.calendarOpen;
                                    }
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
                                    required property var modelData
                                    width: 18; height: 34
                                    IconImage { anchors.centerIn: parent; width: 16; height: 16; source: modelData.icon }
                                    MouseArea {
                                        anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        onClicked: mouse => mouse.button === Qt.RightButton ? modelData.display(this, mouse.x, mouse.y) : modelData.activate()
                                    }
                                }
                            }
                        }
                        BarText {
                            width: 20; height: 34
                            text: "⏻"; color: Theme.cinnabar; font.pixelSize: 17
                            horizontalAlignment: Text.AlignHCenter
                            MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: root.powerOpen = !root.powerOpen }
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
            root.wifiError = "连接失败，请检查密码后重试";
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

        Rectangle {
            anchors.fill: parent
            radius: 16
            color: Qt.rgba(0.976, 0.972, 0.960, 0.96)
            border.color: Theme.border

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
                        text: Qt.formatDate(root.calendarBaseDate(), "yyyy 年 MM 月")
                        color: Theme.ink
                        font.family: Theme.chineseFont
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
                        model: ["一", "二", "三", "四", "五", "六", "日"]
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
                            readonly property date today: new Date()
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
        Shortcut { sequence: "Escape"; onActivated: root.calendarOpen = false }
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

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0.976, 0.972, 0.960, 0.96)
            border.color: Theme.border
            border.width: 1
            radius: 16
            clip: true

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
                            text: "无线网络"
                            color: Theme.cinnabar
                            font.family: Theme.chineseFont
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
                            text: root.selectedNetwork && root.selectedNetwork.known ? "留空以使用已保存的密码" : "输入 Wi-Fi 密码"
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
                            text: "断开连接"
                            color: Theme.cinnabar
                            font.family: Theme.chineseFont
                            font.pixelSize: 14
                        }
                        HoverHandler { id: disconnectHover }
                        TapHandler { onTapped: root.disconnectWifi() }
                    }

                    BarText {
                        visible: root.wifiStage === "disconnecting"
                        width: parent.width
                        text: "正在断开连接"
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
                        text: "按 Enter 连接  ·  Esc 返回"
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

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0.976, 0.972, 0.960, 0.96)
            border.color: Theme.border
            border.width: 1
            radius: 16
            clip: true

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                Row {
                    width: parent.width
                    height: 34
                    BarText {
                        width: parent.width - 38
                        text: "蓝牙设备"
                        color: Theme.cinnabar
                        font.family: Theme.chineseFont
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
        visible: root.powerOpen
        anchors { top: true; right: true }
        margins { top: 56; right: 18 }
        implicitWidth: 250; implicitHeight: 230
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "ink-power"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        Rectangle {
            anchors.fill: parent; radius: 18; color: Qt.rgba(0.976, 0.972, 0.960, 0.94); border.color: Theme.border
            Column {
                anchors.fill: parent; anchors.margins: 14; spacing: 7
                BarText { text: "电源"; color: Theme.cinnabar; font.family: Theme.chineseFont; font.pixelSize: 17; height: 30 }
                Repeater {
                    model: [
                        { label: "󰌾  锁定", cmd: ["swaylock", "-f"] },
                        { label: "󰍃  退出 Sway", cmd: ["swaymsg", "exit"] },
                        { label: "󰜉  重新启动", cmd: ["systemctl", "reboot"] },
                        { label: "󰐥  关机", cmd: ["systemctl", "poweroff"] }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width; height: 36; radius: 10; color: hover.hovered ? Qt.rgba(0.72,0.20,0.15,0.10) : "transparent"
                        BarText { anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: modelData.label }
                        HoverHandler { id: hover }
                        TapHandler { onTapped: { root.powerOpen = false; root.run(modelData.cmd) } }
                    }
                }
            }
        }
        Shortcut { sequence: "Escape"; onActivated: root.powerOpen = false }
    }
}
