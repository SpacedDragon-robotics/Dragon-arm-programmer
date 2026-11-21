// AppCheckBox.qml -- themed checkbox.

import QtQuick
import QtQuick.Controls.Basic
import DragonArm

CheckBox {
    id: control

    property color accent: Theme.accent

    implicitHeight: 24
    hoverEnabled: true
    focusPolicy: Qt.NoFocus

    indicator: Rectangle {
        implicitWidth: 16
        implicitHeight: 16
        x: 0
        y: control.height / 2 - height / 2
        radius: Theme.radiusSmall
        color: control.checked ? control.accent : Theme.fade(Theme.white, 0.04)
        border.width: 1
        border.color: control.checked ? Theme.accentBright
                                      : (control.hovered ? Theme.fade(Theme.white, 0.5) : Theme.borderStrong)

        Canvas {
            anchors.fill: parent
            // Kept visible so the Canvas is always rendered; only the tick fades.
            opacity: control.checked ? 1 : 0
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = Theme.white
                ctx.lineWidth = 1.8
                ctx.lineCap = "square"
                ctx.lineJoin = "miter"
                ctx.beginPath()
                ctx.moveTo(4, 8.5)
                ctx.lineTo(6.8, 11.5)
                ctx.lineTo(12, 5)
                ctx.stroke()
            }
        }
    }

    contentItem: Text {
        text: control.text
        leftPadding: control.indicator.width + 8
        color: control.hovered ? Theme.textPrimary : Theme.textSecondary
        font.family: Theme.fontFamily
        font.weight: Theme.weightBody
        font.pixelSize: Theme.fontSmall
        verticalAlignment: Text.AlignVCenter
    }
}
