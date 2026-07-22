//@ pragma UseQApplication

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."
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
    readonly property int wifiPopupCloseDelay: 6000
    property int memoryPercent: 0
    property string poemText: "山水有清音"
    property string poemTitle: ""
    property string poemAuthor: ""
    property string poemDynasty: ""
    property string poemFullText: ""
    property bool poemTooltipOpen: false
    property var poemTooltipScreen: null
    readonly property string poemTooltipText: {
        const attribution = (root.poemDynasty + " " + root.poemAuthor).trim()
            + (root.poemTitle ? "《" + root.poemTitle + "》" : "");
        const body = root.poemFullText || root.poemText;
        return attribution ? attribution + "\n\n" + body : body;
    }
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
    readonly property var sortedWifiNetworks: {
        if (!wifiDevice) return [];
        const networks = wifiDevice.networks.values;
        const sorted = [];
        for (let i = 0; i < networks.length; i++) sorted.push(networks[i]);
        sorted.sort((left, right) => {
            if (left.connected !== right.connected) return left.connected ? -1 : 1;
            if (left.signalStrength !== right.signalStrength)
                return right.signalStrength - left.signalStrength;
            return left.name.localeCompare(right.name);
        });
        return sorted;
    }
    property bool wifiOpen: false
    // Wi-Fi popup state machine: list, credentials, connection and connectivity.
    property string wifiStage: "list"
    property var selectedNetwork: null
    property string wifiError: ""
    property var wifiPopupScreen: null
    property string wifiReturnStage: "list"
    property bool wifiEnterpriseHidden: false
    property string wifiPendingHiddenSsid: ""
    property string wifiHiddenSecurity: "personal"
    property string wifiEapMethod: "peap"
    property string wifiPhase2Method: "mschapv2"
    property string wifiHelperRequest: ""
    property bool wifiPortalOpened: false
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
        if (cached.content) {
            root.poemText = cached.content;
            root.poemTitle = cached.title || "";
            root.poemAuthor = cached.author || "";
            root.poemDynasty = cached.dynasty || "";
            root.poemFullText = cached.fullText || "";
        }
        // 与旧脚本一致：缓存未满 30 分钟时不访问网络。
        if (cached.content && cached.fullText
                && Date.now() - Number(cached.fetchedAt || 0) < 1800000) return;
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
                    const origin = response.data.origin || {};
                    const originContent = origin.content || [];
                    const fullText = Array.isArray(originContent)
                        ? originContent.join("\n")
                        : String(originContent || "");
                    root.poemText = content;
                    root.poemTitle = origin.title || "";
                    root.poemAuthor = origin.author || "";
                    root.poemDynasty = origin.dynasty || "";
                    root.poemFullText = fullText;
                    poemCache.setText(JSON.stringify({
                        content: content,
                        title: root.poemTitle,
                        author: root.poemAuthor,
                        dynasty: root.poemDynasty,
                        fullText: fullText,
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
    Process {
        id: wifiManagerProcess
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/topbar/wifi-manager.py"]
        stdinEnabled: true
        onStarted: write(root.wifiHelperRequest + "\n")
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length === 0) return;
                try {
                    const result = JSON.parse(text.trim());
                    if (!result.ok) {
                        root.wifiStage = root.wifiReturnStage;
                        root.wifiError = result.error || "NetworkManager rejected the request.";
                        wifiFieldFocus.restart();
                        return;
                    }
                    root.wifiError = "";
                    root.wifiStage = "connected";
                    connectivityRefreshTimer.restart();
                } catch (error) {
                    root.wifiStage = root.wifiReturnStage;
                    root.wifiError = "Could not read the NetworkManager response.";
                }
            }
        }
    }
    Process {
        id: trayRegistrationRepair
        command: [Quickshell.env("HOME") + "/.config/quickshell/topbar/repair-qqmusic-tray.sh"]
    }
    Timer {
        interval: 750
        running: true
        onTriggered: trayRegistrationRepair.running = true
    }
    Timer {
        interval: 3000; running: true; repeat: true
        onTriggered: memoryPoll.running = true
    }
    Timer { interval: 60000; running: true; repeat: true; onTriggered: root.now = new Date() }
    Timer { interval: 600000; running: true; repeat: true; onTriggered: root.refreshPoem() }
    Timer {
        id: connectivityRefreshTimer
        interval: 650
        onTriggered: root.updateWifiConnectivity()
    }
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
        if (Networking.connectivity === NetworkConnectivity.Portal
                || Networking.connectivity === NetworkConnectivity.Limited
                || Networking.connectivity === NetworkConnectivity.None) return "󰤭";
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
    function closePoemTooltip() {
        root.poemTooltipOpen = false;
        root.poemTooltipScreen = null;
    }
    function closeOtherPopups(except) {
        root.closePoemTooltip();
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
        root.wifiPortalOpened = false;
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
    function wifiSecurityKind(network) {
        if (!network) return "unknown";
        if (network.security === WifiSecurityType.Open || network.security === WifiSecurityType.Owe)
            return "open";
        if (network.security === WifiSecurityType.WpaPsk
                || network.security === WifiSecurityType.Wpa2Psk
                || network.security === WifiSecurityType.Sae) return "personal";
        if (network.security === WifiSecurityType.WpaEap
                || network.security === WifiSecurityType.Wpa2Eap) return "enterprise";
        if (network.security === WifiSecurityType.Wpa3SuiteB192) return "certificate";
        if (network.security === WifiSecurityType.StaticWep
                || network.security === WifiSecurityType.DynamicWep
                || network.security === WifiSecurityType.Leap) return "legacy";
        return "unknown";
    }
    function wifiSecurityLabel(network) {
        if (!network) return "";
        switch (network.security) {
        case WifiSecurityType.Open: return "Open network";
        case WifiSecurityType.Owe: return "Enhanced Open (OWE)";
        case WifiSecurityType.WpaPsk: return "WPA Personal";
        case WifiSecurityType.Wpa2Psk: return "WPA2 Personal";
        case WifiSecurityType.Sae: return "WPA3 Personal";
        case WifiSecurityType.WpaEap: return "WPA Enterprise";
        case WifiSecurityType.Wpa2Eap: return "WPA2 Enterprise";
        case WifiSecurityType.Wpa3SuiteB192: return "WPA3 Enterprise 192-bit";
        case WifiSecurityType.StaticWep: return "WEP";
        case WifiSecurityType.DynamicWep: return "Dynamic WEP";
        case WifiSecurityType.Leap: return "LEAP";
        default: return "Unknown security";
        }
    }
    function selectedWifiUuid() {
        if (!root.selectedNetwork || !root.selectedNetwork.nmSettings
                || root.selectedNetwork.nmSettings.length === 0) return "";
        return root.selectedNetwork.nmSettings[0].uuid || "";
    }
    function openWifi(network) {
        root.selectedNetwork = network;
        root.wifiError = "";
        root.wifiEnterpriseHidden = false;
        if (network.connected) {
            root.updateWifiConnectivity();
            return;
        }
        if (network.known) {
            root.wifiStage = "connecting";
            network.connect();
            return;
        }
        const kind = root.wifiSecurityKind(network);
        if (kind === "open") {
            root.wifiStage = "connecting";
            network.connect();
        } else if (kind === "personal") {
            root.wifiStage = "password";
            wifiFieldFocus.restart();
        } else if (kind === "enterprise") {
            root.wifiStage = "enterprise";
            wifiFieldFocus.restart();
        } else {
            root.wifiStage = "unsupported";
            root.wifiError = kind === "certificate"
                ? "This network requires a client certificate and private key."
                : (kind === "legacy"
                    ? "This legacy security mode needs advanced NetworkManager settings."
                    : "The access point uses an unrecognized security mode.");
        }
    }
    function connectWifi(password) {
        if (!root.selectedNetwork) return;
        const isSae = root.selectedNetwork.security === WifiSecurityType.Sae;
        const validPsk = password.length >= 8 && password.length <= 63
            || /^[0-9a-fA-F]{64}$/.test(password);
        if ((!isSae && !validPsk) || (isSae && password.length === 0)) {
            root.wifiError = isSae
                ? "Enter the WPA3 password."
                : "Use 8–63 characters, or a 64-digit hexadecimal key.";
            return;
        }
        root.wifiError = "";
        root.wifiStage = "connecting";
        root.selectedNetwork.connectWithPsk(password);
        wifiPassword.text = "";
    }
    function startWifiHelper(request, returnStage) {
        if (wifiManagerProcess.running) return;
        root.wifiError = "";
        root.wifiReturnStage = returnStage;
        root.wifiHelperRequest = JSON.stringify(request);
        root.wifiStage = "connecting";
        wifiManagerProcess.running = true;
    }
    function connectEnterprise() {
        const ssid = root.wifiEnterpriseHidden
            ? root.wifiPendingHiddenSsid
            : (root.selectedNetwork ? root.selectedNetwork.name : "");
        if ((!root.selectedWifiUuid() && !wifiEnterpriseIdentity.text.trim())
                || !wifiEnterprisePassword.text) {
            root.wifiError = root.selectedWifiUuid()
                ? "Password is required."
                : "Username and password are required.";
            return;
        }
        root.startWifiHelper({
            action: "connect-enterprise",
            hidden: root.wifiEnterpriseHidden,
            ssid: ssid,
            interface: root.wifiDevice ? root.wifiDevice.name : "",
            uuid: root.wifiEnterpriseHidden ? "" : root.selectedWifiUuid(),
            identity: wifiEnterpriseIdentity.text,
            password: wifiEnterprisePassword.text,
            anonymousIdentity: wifiEnterpriseAnonymous.text,
            domain: wifiEnterpriseDomain.text,
            caCert: wifiEnterpriseCa.text,
            eap: root.wifiEapMethod,
            phase2: root.wifiPhase2Method
        }, "enterprise");
        wifiEnterprisePassword.text = "";
    }
    function cycleHiddenSecurity() {
        root.wifiHiddenSecurity = root.wifiHiddenSecurity === "open"
            ? "personal" : (root.wifiHiddenSecurity === "personal" ? "sae"
            : (root.wifiHiddenSecurity === "sae" ? "enterprise" : "open"));
    }
    function connectHiddenWifi() {
        const ssid = wifiHiddenSsid.text.trim();
        if (!ssid) {
            root.wifiError = "Network name is required.";
            return;
        }
        if (root.wifiHiddenSecurity === "enterprise") {
            root.wifiEnterpriseHidden = true;
            root.wifiPendingHiddenSsid = ssid;
            root.wifiStage = "enterprise";
            root.wifiError = "";
            wifiFieldFocus.restart();
            return;
        }
        if ((root.wifiHiddenSecurity === "personal" || root.wifiHiddenSecurity === "sae")
                && !wifiHiddenPassword.text) {
            root.wifiError = "Password is required.";
            return;
        }
        root.startWifiHelper({
            action: root.wifiHiddenSecurity === "open" ? "connect-open" : "connect-personal",
            hidden: true,
            ssid: ssid,
            interface: root.wifiDevice ? root.wifiDevice.name : "",
            keyMgmt: root.wifiHiddenSecurity === "sae" ? "sae" : "wpa-psk",
            password: wifiHiddenPassword.text
        }, "hidden");
        wifiHiddenPassword.text = "";
    }
    function wifiFailureText(reason) {
        switch (reason) {
        case ConnectionFailReason.NoSecrets: return "NetworkManager needs additional credentials.";
        case ConnectionFailReason.WifiAuthTimeout: return "Authentication timed out. Check the credentials and signal.";
        case ConnectionFailReason.WifiNetworkLost: return "The network disappeared during connection.";
        case ConnectionFailReason.WifiClientDisconnected: return "The access point ended the connection.";
        case ConnectionFailReason.WifiClientFailed: return "The Wi-Fi adapter could not complete the connection.";
        default: return "The connection failed for an unknown reason.";
        }
    }
    function updateWifiConnectivity() {
        if (!root.activeNetwork) {
            if (root.wifiStage === "disconnecting") root.wifiStage = "list";
            return;
        }
        if (!root.selectedNetwork) root.selectedNetwork = root.activeNetwork;
        if (Networking.canCheckConnectivity && !Networking.connectivityCheckEnabled)
            Networking.connectivityCheckEnabled = true;
        if (Networking.canCheckConnectivity) Networking.checkConnectivity();
        if (Networking.connectivity === NetworkConnectivity.Portal)
            root.wifiStage = "portal";
        else if (Networking.connectivity === NetworkConnectivity.Limited
                || Networking.connectivity === NetworkConnectivity.None)
            root.wifiStage = "limited";
        else
            root.wifiStage = "connected";
    }
    function openWifiPortal() {
        root.wifiPortalOpened = true;
        root.run(["xdg-open", "http://ping.archlinux.org/nm-check.txt"]);
    }
    function forgetWifi() {
        if (!root.selectedNetwork) return;
        root.selectedNetwork.forget();
        root.wifiStage = "list";
        root.selectedNetwork = null;
        root.wifiError = "";
    }
    function clearWifiSecrets() {
        wifiPassword.text = "";
        wifiEnterprisePassword.text = "";
        wifiHiddenPassword.text = "";
    }
    function cancelWifiConnection() {
        if (wifiManagerProcess.running) wifiManagerProcess.signal(15);
        if (root.selectedNetwork && root.selectedNetwork.stateChanging)
            root.selectedNetwork.disconnect();
        root.wifiStage = "list";
        root.selectedNetwork = null;
        root.wifiError = "";
        root.clearWifiSecrets();
    }
    function wifiBack() {
        if (root.wifiStage === "enterprise" && root.wifiEnterpriseHidden) {
            root.wifiStage = "hidden";
            root.wifiEnterpriseHidden = false;
        } else {
            root.wifiStage = "list";
            root.selectedNetwork = null;
        }
        root.wifiError = "";
        root.clearWifiSecrets();
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
        root.wifiEnterpriseHidden = false;
        root.wifiPendingHiddenSsid = "";
        root.wifiPortalOpened = false;
        root.clearWifiSecrets();
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

    PanelWindow {
        id: poemTooltip
        function measuredContentWidth() {
            const lines = root.poemTooltipText.split("\n");
            let widest = 0;
            for (let i = 0; i < lines.length; i++)
                widest = Math.max(widest, poemTooltipFontMetrics.advanceWidth(lines[i]));
            return widest;
        }
        visible: root.poemTooltipOpen && root.poemTooltipScreen !== null
        screen: root.poemTooltipScreen
        anchors { top: true; left: true }
        margins { top: 52; left: 14 }
        implicitWidth: Math.min(560, Math.max(180, measuredContentWidth() + 30))
        implicitHeight: poemTooltipBody.contentHeight + 28
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "ink-poem-tooltip"
        WlrLayershell.layer: WlrLayer.Overlay

        FontMetrics {
            id: poemTooltipFontMetrics
            font.family: Theme.chineseFont
            font.pixelSize: 13
        }

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: Qt.rgba(0.976, 0.972, 0.960, 0.96)
            border.color: Theme.border
            border.width: 1

            Text {
                id: poemTooltipBody
                anchors { top: parent.top; left: parent.left; right: parent.right }
                anchors.margins: 14
                text: root.poemTooltipText
                color: Theme.ink
                font.family: Theme.chineseFont
                font.pixelSize: 13
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                lineHeight: 1.28
                renderType: Text.NativeRendering
            }
        }
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
                    Timer {
                        id: poemTooltipShowTimer
                        interval: 350
                        onTriggered: {
                            if (!poemCardHover.hovered) return;
                            root.poemTooltipScreen = modelData;
                            root.poemTooltipOpen = true;
                        }
                    }
                    HoverHandler {
                        id: poemCardHover
                        parent: poemCard
                        onHoveredChanged: {
                            if (hovered) poemTooltipShowTimer.restart();
                            else {
                                poemTooltipShowTimer.stop();
                                if (root.poemTooltipScreen === modelData)
                                    root.closePoemTooltip();
                            }
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
                            width: 94; height: 32; clip: true
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
                                    width: 70; height: 28; clip: true
                                    property int scrollOffset: 0
                                    readonly property string title: root.player
                                        ? (root.player.trackTitle || root.player.identity)
                                        : "No media"
                                    readonly property bool needsScroll: displayWidth(title) > 10

                                    function displayWidth(value) {
                                        const characters = Array.from(value);
                                        let columns = 0;
                                        for (let i = 0; i < characters.length; i++)
                                            columns += characters[i].codePointAt(0) > 127 ? 2 : 1;
                                        return columns;
                                    }

                                    function visibleFrame() {
                                        if (!needsScroll) return title;
                                        const characters = Array.from(title + "  ·  ");
                                        if (characters.length === 0) return "";

                                        let frame = "";
                                        let columns = 0;
                                        let index = scrollOffset % characters.length;
                                        while (columns < 10) {
                                            const character = characters[index % characters.length];
                                            const characterWidth = character.codePointAt(0) > 127 ? 2 : 1;
                                            if (columns + characterWidth > 10) break;
                                            frame += character;
                                            columns += characterWidth;
                                            index++;
                                        }
                                        while (columns < 10) {
                                            frame += " ";
                                            columns++;
                                        }
                                        return frame;
                                    }

                                    onTitleChanged: scrollOffset = 0

                                    Timer {
                                        interval: 500
                                        running: mediaViewport.needsScroll && root.player !== null && root.player.isPlaying
                                        repeat: true
                                        onTriggered: mediaViewport.scrollOffset++
                                    }

                                    BarText {
                                        y: 3
                                        width: parent.width; height: parent.height
                                        text: mediaViewport.visibleFrame()
                                        horizontalAlignment: Text.AlignHCenter
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
                                    readonly property bool isInputMethod: {
                                        const itemId = String(modelData.id || "").toLowerCase();
                                        const title = String(modelData.title || "").toLowerCase();
                                        return itemId.indexOf("fcitx") >= 0 || title === "input method";
                                    }
                                    readonly property bool isRime: String(modelData.icon || "").toLowerCase().indexOf("rime") >= 0
                                    width: 18; height: 34
                                    IconImage {
                                        anchors.centerIn: parent
                                        width: 16; height: 16
                                        source: trayEntry.isInputMethod ? "" : modelData.icon
                                    }
                                    BarText {
                                        visible: trayEntry.isInputMethod
                                        anchors.centerIn: parent
                                        width: 16; height: 20
                                        text: trayEntry.isRime ? "中" : "A"
                                        color: Theme.ink
                                        font.family: trayEntry.isRime ? Theme.chineseFont : Theme.fontFamily
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        horizontalAlignment: Text.AlignHCenter
                                    }
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
                                color: parent.isUrgent || parent.isFocused
                                    ? Theme.cinnabar
                                    : (parent.isEmpty ? Theme.muted : Theme.ink)
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
            if (root.selectedNetwork && root.selectedNetwork.connected) {
                root.wifiError = "";
                connectivityRefreshTimer.restart();
            } else if (root.wifiStage === "disconnecting") {
                root.wifiStage = "list";
                root.selectedNetwork = null;
            }
        }
        function onConnectionFailed(reason) {
            const kind = root.wifiSecurityKind(root.selectedNetwork);
            if (reason === ConnectionFailReason.NoSecrets && kind === "personal") {
                root.wifiStage = "password";
                root.wifiError = "Enter the password required by this network.";
                wifiFieldFocus.restart();
            } else if (reason === ConnectionFailReason.NoSecrets && kind === "enterprise") {
                root.wifiStage = "enterprise";
                root.wifiError = "Enter the enterprise credentials required by this profile.";
                wifiFieldFocus.restart();
            } else {
                root.wifiStage = "error";
                root.wifiError = root.wifiFailureText(reason);
            }
        }
    }

    Connections {
        target: Networking
        function onConnectivityChanged() {
            if (!root.wifiOpen || !root.activeNetwork) return;
            const connectionStage = root.wifiStage === "connecting"
                || root.wifiStage === "connected" || root.wifiStage === "portal"
                || root.wifiStage === "limited";
            if (!connectionStage && (!root.selectedNetwork || !root.selectedNetwork.connected)) return;
            if (Networking.connectivity === NetworkConnectivity.Portal)
                root.wifiStage = "portal";
            else if (Networking.connectivity === NetworkConnectivity.Limited
                    || Networking.connectivity === NetworkConnectivity.None)
                root.wifiStage = "limited";
            else if (Networking.connectivity === NetworkConnectivity.Full
                    && (root.wifiStage === "connecting" || root.wifiStage === "connected"
                        || root.wifiStage === "portal" || root.wifiStage === "limited"))
                root.wifiStage = "connected";
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
        id: wifiFieldFocus
        interval: 60
        onTriggered: {
            if (root.wifiStage === "password") wifiPassword.focus();
            else if (root.wifiStage === "enterprise") wifiEnterpriseIdentity.focus();
            else if (root.wifiStage === "hidden") wifiHiddenSsid.focus();
        }
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
        implicitWidth: 380
        implicitHeight: root.wifiStage === "list" ? 390
            : (root.wifiStage === "enterprise" ? 520
            : (root.wifiStage === "hidden" ? 350 : 270))
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "ink-wifi"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Timer {
            interval: root.wifiPopupCloseDelay
            running: wifiPopup.visible && root.wifiStage === "list" && !wifiPopupHover.hovered
            onTriggered: root.closeWifi()
        }

        Timer {
            interval: 5000
            repeat: true
            running: wifiPopup.visible && root.wifiStage === "portal"
            onTriggered: if (Networking.canCheckConnectivity) Networking.checkConnectivity()
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
                            width: parent.width - 74
                            text: "Wireless Networks"
                            color: Theme.cinnabar
                            font.pixelSize: 17
                        }
                        BarText {
                            width: 36
                            text: "＋"
                            color: Theme.ink
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: 19
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.wifiStage = "hidden";
                                    root.wifiError = "";
                                    wifiFieldFocus.restart();
                                }
                            }
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
                        id: wifiNetworkList
                        width: parent.width
                        height: parent.height - 42
                        clip: true
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.sortedWifiNetworks
                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                            width: 5
                            contentItem: Rectangle {
                                implicitWidth: 5
                                radius: width / 2
                                color: Theme.border
                            }
                            background: Item {}
                        }
                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width - 9
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
                                    width: parent.width - 116; height: parent.height
                                    text: modelData.name
                                    elide: Text.ElideRight
                                }
                                BarText {
                                    width: 20; height: parent.height
                                    text: modelData.known ? "󰋊"
                                        : (modelData.security === WifiSecurityType.Open
                                           || modelData.security === WifiSecurityType.Owe ? "" : "󰌾")
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
                                    if (!modelData.connected) root.openWifi(modelData);
                                    else { root.selectedNetwork = modelData; root.updateWifiConnectivity(); }
                                }
                            }
                        }
                    }
                }

                Column {
                    visible: root.wifiStage !== "list"
                    anchors.fill: parent
                    spacing: 10

                    Row {
                        width: parent.width
                        height: 32
                        BarText {
                            width: 34; height: parent.height
                            text: "‹"
                            color: Theme.muted
                            font.pixelSize: 22
                            horizontalAlignment: Text.AlignHCenter
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.wifiBack()
                            }
                        }
                        BarText {
                            width: parent.width - 68; height: parent.height
                            text: root.wifiEnterpriseHidden ? root.wifiPendingHiddenSsid
                                : (root.selectedNetwork ? root.selectedNetwork.name
                                   : (root.wifiStage === "hidden" ? "Hidden network" : "Wi-Fi"))
                            color: Theme.cinnabar
                            font.family: Theme.chineseFont
                            font.pixelSize: 18
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Item { width: 34; height: parent.height }
                    }

                    Column {
                        visible: root.wifiStage === "password"
                        width: parent.width
                        spacing: 10
                        BarText {
                            width: parent.width; height: 22
                            text: root.wifiSecurityLabel(root.selectedNetwork)
                            color: Theme.muted
                            horizontalAlignment: Text.AlignHCenter
                            font.weight: Font.Normal
                        }
                        WifiField {
                            id: wifiPassword
                            password: true
                            placeholderText: "Wi-Fi password"
                            onAccepted: root.connectWifi(text)
                        }
                        Rectangle {
                            width: parent.width; height: 40; radius: 10
                            color: personalConnectHover.hovered ? Qt.rgba(0.72, 0.20, 0.15, 0.14) : Qt.rgba(0.72, 0.20, 0.15, 0.08)
                            border.color: Theme.cinnabar
                            BarText { anchors.centerIn: parent; text: "Connect"; color: Theme.cinnabar }
                            HoverHandler { id: personalConnectHover }
                            TapHandler { onTapped: root.connectWifi(wifiPassword.text) }
                        }
                    }

                    Column {
                        visible: root.wifiStage === "enterprise"
                        width: parent.width
                        spacing: 8
                        Row {
                            width: parent.width; height: 34; spacing: 8
                            visible: root.wifiEnterpriseHidden || root.selectedWifiUuid() === ""
                            Rectangle {
                                width: (parent.width - 8) / 2; height: parent.height; radius: 9
                                color: Qt.rgba(0.72, 0.20, 0.15, 0.08); border.color: Theme.border
                                BarText { anchors.centerIn: parent; text: root.wifiEapMethod.toUpperCase(); color: Theme.cinnabar }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.wifiEapMethod = root.wifiEapMethod === "peap" ? "ttls" : "peap";
                                        root.wifiPhase2Method = root.wifiEapMethod === "peap" ? "mschapv2" : "pap";
                                    }
                                }
                            }
                            Rectangle {
                                width: (parent.width - 8) / 2; height: parent.height; radius: 9
                                color: Qt.rgba(0.72, 0.20, 0.15, 0.08); border.color: Theme.border
                                BarText { anchors.centerIn: parent; text: root.wifiPhase2Method.toUpperCase(); color: Theme.ink }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.wifiEapMethod === "peap")
                                            root.wifiPhase2Method = root.wifiPhase2Method === "mschapv2" ? "gtc" : "mschapv2";
                                        else
                                            root.wifiPhase2Method = root.wifiPhase2Method === "pap" ? "mschapv2" : "pap";
                                    }
                                }
                            }
                        }
                        WifiField {
                            id: wifiEnterpriseIdentity
                            placeholderText: root.selectedWifiUuid()
                                ? "Username (blank keeps the saved identity)"
                                : "Username / identity"
                        }
                        WifiField { id: wifiEnterprisePassword; placeholderText: "Password"; password: true; onAccepted: root.connectEnterprise() }
                        WifiField { id: wifiEnterpriseAnonymous; placeholderText: "Anonymous identity (optional)" }
                        WifiField { id: wifiEnterpriseDomain; placeholderText: "Server domain (recommended)" }
                        WifiField { id: wifiEnterpriseCa; placeholderText: "CA certificate path (optional)" }
                        Rectangle {
                            width: parent.width; height: 40; radius: 10
                            color: enterpriseConnectHover.hovered ? Qt.rgba(0.72, 0.20, 0.15, 0.14) : Qt.rgba(0.72, 0.20, 0.15, 0.08)
                            border.color: Theme.cinnabar
                            BarText { anchors.centerIn: parent; text: "Connect securely"; color: Theme.cinnabar }
                            HoverHandler { id: enterpriseConnectHover }
                            TapHandler { onTapped: root.connectEnterprise() }
                        }
                        BarText {
                            width: parent.width; height: 26
                            text: "System CAs are used when no certificate path is supplied."
                            color: Theme.muted; font.pixelSize: 10; font.weight: Font.Normal
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    Column {
                        visible: root.wifiStage === "hidden"
                        width: parent.width
                        spacing: 10
                        WifiField { id: wifiHiddenSsid; placeholderText: "Network name (SSID)"; onAccepted: root.connectHiddenWifi() }
                        Rectangle {
                            width: parent.width; height: 38; radius: 10
                            color: Qt.rgba(0.72, 0.20, 0.15, 0.08); border.color: Theme.border
                            BarText {
                                anchors.centerIn: parent
                                text: root.wifiHiddenSecurity === "open" ? "Open network"
                                    : (root.wifiHiddenSecurity === "personal" ? "WPA/WPA2 Personal"
                                    : (root.wifiHiddenSecurity === "sae" ? "WPA3 Personal" : "WPA Enterprise"))
                                color: Theme.ink
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.cycleHiddenSecurity() }
                        }
                        WifiField {
                            id: wifiHiddenPassword
                            visible: root.wifiHiddenSecurity === "personal" || root.wifiHiddenSecurity === "sae"
                            placeholderText: "Wi-Fi password"
                            password: true
                            onAccepted: root.connectHiddenWifi()
                        }
                        Rectangle {
                            width: parent.width; height: 40; radius: 10
                            color: hiddenConnectHover.hovered ? Qt.rgba(0.72, 0.20, 0.15, 0.14) : Qt.rgba(0.72, 0.20, 0.15, 0.08)
                            border.color: Theme.cinnabar
                            BarText {
                                anchors.centerIn: parent
                                text: root.wifiHiddenSecurity === "enterprise" ? "Continue" : "Connect"
                                color: Theme.cinnabar
                            }
                            HoverHandler { id: hiddenConnectHover }
                            TapHandler { onTapped: root.connectHiddenWifi() }
                        }
                    }

                    Column {
                        visible: root.wifiStage === "connecting" || root.wifiStage === "disconnecting"
                        width: parent.width
                        spacing: 12
                        Item {
                            width: parent.width; height: 64
                            BarText {
                                id: wifiSpinner
                                anchors.centerIn: parent
                                text: "󰑓"; color: Theme.cinnabar; font.pixelSize: 25
                                RotationAnimator on rotation { from: 0; to: 360; duration: 850; loops: Animation.Infinite; running: wifiSpinner.visible }
                            }
                        }
                        BarText {
                            width: parent.width; height: 24
                            text: root.wifiStage === "disconnecting" ? "Disconnecting…" : "Authenticating and obtaining an address…"
                            color: Theme.muted; horizontalAlignment: Text.AlignHCenter; font.weight: Font.Normal
                        }
                        Rectangle {
                            width: parent.width; height: 38; radius: 10; color: "transparent"; border.color: Theme.border
                            BarText { anchors.centerIn: parent; text: "Cancel"; color: Theme.muted }
                            TapHandler { onTapped: root.cancelWifiConnection() }
                        }
                    }

                    Column {
                        visible: root.wifiStage === "connected"
                        width: parent.width
                        spacing: 10
                        BarText {
                            width: parent.width; height: 30; text: "󰤨  Connected to the Internet"
                            color: Theme.ink; font.pixelSize: 15; horizontalAlignment: Text.AlignHCenter
                        }
                        BarText {
                            width: parent.width; height: 20
                            text: root.wifiSecurityLabel(root.selectedNetwork)
                            color: Theme.muted; font.weight: Font.Normal; horizontalAlignment: Text.AlignHCenter
                        }
                        Row {
                            width: parent.width; height: 40; spacing: 8
                            Rectangle {
                                width: (parent.width - 8) / 2; height: parent.height; radius: 10
                                color: Qt.rgba(0.72, 0.20, 0.15, 0.08); border.color: Theme.cinnabar
                                BarText { anchors.centerIn: parent; text: "Disconnect"; color: Theme.cinnabar }
                                TapHandler { onTapped: root.disconnectWifi() }
                            }
                            Rectangle {
                                width: (parent.width - 8) / 2; height: parent.height; radius: 10
                                color: "transparent"; border.color: Theme.border
                                BarText { anchors.centerIn: parent; text: "Forget"; color: Theme.muted }
                                TapHandler { onTapped: root.forgetWifi() }
                            }
                        }
                    }

                    Column {
                        visible: root.wifiStage === "portal"
                        width: parent.width
                        spacing: 10
                        BarText {
                            width: parent.width; height: 34; text: "󰌆  Sign-in required"
                            color: Theme.cinnabar; font.pixelSize: 16; horizontalAlignment: Text.AlignHCenter
                        }
                        BarText {
                            width: parent.width; height: 36
                            text: "This network requires authentication in a web browser."
                            color: Theme.muted; wrapMode: Text.Wrap; font.weight: Font.Normal
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Rectangle {
                            width: parent.width; height: 40; radius: 10
                            color: Qt.rgba(0.72, 0.20, 0.15, 0.10); border.color: Theme.cinnabar
                            BarText { anchors.centerIn: parent; text: root.wifiPortalOpened ? "Open sign-in page again" : "Open sign-in page"; color: Theme.cinnabar }
                            TapHandler { onTapped: root.openWifiPortal() }
                        }
                        Rectangle {
                            width: parent.width; height: 38; radius: 10; color: "transparent"; border.color: Theme.border
                            BarText { anchors.centerIn: parent; text: "Check again"; color: Theme.ink }
                            TapHandler { onTapped: if (Networking.canCheckConnectivity) Networking.checkConnectivity() }
                        }
                    }

                    Column {
                        visible: root.wifiStage === "limited"
                        width: parent.width; spacing: 10
                        BarText {
                            width: parent.width; height: 34; text: "󰤭  No Internet access"
                            color: Theme.cinnabar; font.pixelSize: 16; horizontalAlignment: Text.AlignHCenter
                        }
                        BarText {
                            width: parent.width; height: 38
                            text: "The Wi-Fi link is active, but Internet connectivity could not be verified."
                            color: Theme.muted; wrapMode: Text.Wrap; font.weight: Font.Normal
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Rectangle {
                            width: parent.width; height: 40; radius: 10
                            color: Qt.rgba(0.72, 0.20, 0.15, 0.08); border.color: Theme.cinnabar
                            BarText { anchors.centerIn: parent; text: "Open sign-in page"; color: Theme.cinnabar }
                            TapHandler { onTapped: root.openWifiPortal() }
                        }
                        Rectangle {
                            width: parent.width; height: 38; radius: 10; color: "transparent"; border.color: Theme.border
                            BarText { anchors.centerIn: parent; text: "Check again"; color: Theme.ink }
                            TapHandler { onTapped: if (Networking.canCheckConnectivity) Networking.checkConnectivity() }
                        }
                    }

                    Column {
                        visible: root.wifiStage === "unsupported" || root.wifiStage === "error"
                        width: parent.width; spacing: 12
                        BarText {
                            width: parent.width; height: 68
                            text: root.wifiError
                            color: Theme.cinnabar; wrapMode: Text.Wrap; font.weight: Font.Normal
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        Rectangle {
                            visible: root.selectedNetwork && root.selectedNetwork.known
                            width: parent.width; height: 38; radius: 10
                            color: "transparent"; border.color: Theme.border
                            BarText { anchors.centerIn: parent; text: "Forget saved profile"; color: Theme.muted }
                            TapHandler { onTapped: root.forgetWifi() }
                        }
                        Rectangle {
                            visible: root.wifiStage === "unsupported"
                            width: parent.width; height: 40; radius: 10
                            color: Qt.rgba(0.72, 0.20, 0.15, 0.08); border.color: Theme.cinnabar
                            BarText { anchors.centerIn: parent; text: "Open advanced network settings"; color: Theme.cinnabar }
                            TapHandler { onTapped: root.run(["alacritty", "-e", "nmtui"]) }
                        }
                        Rectangle {
                            width: parent.width; height: 38; radius: 10; color: "transparent"; border.color: Theme.border
                            BarText { anchors.centerIn: parent; text: "Back to networks"; color: Theme.ink }
                            TapHandler { onTapped: root.wifiBack() }
                        }
                    }

                    BarText {
                        visible: root.wifiError.length > 0
                            && root.wifiStage !== "unsupported" && root.wifiStage !== "error"
                        width: parent.width
                        height: Math.max(24, contentHeight)
                        text: root.wifiError
                        color: Theme.cinnabar
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: 11
                    }
                }
            }
        }

        Shortcut {
            sequence: "Escape"
            onActivated: {
                if (root.wifiStage === "list") root.closeWifi();
                else if (root.wifiStage === "connecting" || root.wifiStage === "disconnecting")
                    root.cancelWifiConnection();
                else root.wifiBack();
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
                        { label: "󰌾  Lock", cmd: [Quickshell.env("HOME") + "/.config/sway/scripts/random-lock.sh"] },
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
