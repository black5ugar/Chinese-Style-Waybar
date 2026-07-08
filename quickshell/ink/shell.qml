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
                height: parent.height - y - 16
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
        }
    }
}
