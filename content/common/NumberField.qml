// NumberField.qml -- compact labelled numeric entry used by the config pages.

import QtQuick
import QtQuick.Controls.Basic
import DragonArm

Item {
    id: control

    property string label: ""
    property real value: 0
    property real from: 0
    property real to: 9999
    property int decimals: 0
    property string suffix: ""
    property bool hex: false
    property int fieldWidth: 72
    property bool warn: false

    signal committed(real newValue)

    implicitWidth: fieldWidth
    implicitHeight: 42

    function display() {
        if (hex) {
            var s = Math.round(value).toString(16).toUpperCase()
            return "0x" + (s.length < 2 ? "0" + s : s)
        }
        return value.toFixed(decimals) + suffix
    }

    Text {
        id: caption
        anchors.top: parent.top
        anchors.left: parent.left
        text: control.label
        color: Theme.textMuted
        font.family: Theme.fontFamily
        font.weight: Theme.weightBody
        font.pixelSize: Theme.fontTiny
    }

    TextField {
        id: field

        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: control.fieldWidth
        height: 26

        text: control.display()
        color: control.warn ? Theme.danger : Theme.textPrimary
        font.family: Theme.monoFamily
        font.pixelSize: Theme.fontSmall
        horizontalAlignment: Text.AlignHCenter
        selectByMouse: true

        // .gx-input: white / .04, 1 px border; focus turns it accent with a
        // 3 px ring.
        background: Rectangle {
            radius: Theme.radiusSmall
            color: Theme.fade(Theme.white, 0.04)
            border.width: 1
            border.color: field.activeFocus ? Theme.accentBright
                                            : (control.warn ? Theme.danger : Theme.border)

            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                visible: field.activeFocus
                color: "transparent"
                border.width: 3
                border.color: Theme.fade(Theme.accent, 0.2)
            }
        }

        onEditingFinished: commit()
        Keys.onReturnPressed: commit()
        Keys.onEnterPressed: commit()

        function commit() {
            var raw = text.trim().replace(control.suffix, "").replace(",", ".")
            var v = control.hex ? parseInt(raw, 16) : parseFloat(raw)
            if (!isNaN(v)) {
                v = Math.max(control.from, Math.min(control.to, v))
                control.committed(v)
            }
            text = Qt.binding(function () { return control.display() })
        }

        Connections {
            target: control
            function onValueChanged() {
                if (!field.activeFocus)
                    field.text = control.display()
            }
        }
    }
}
