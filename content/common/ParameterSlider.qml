// ParameterSlider.qml
//
// Slider + numeric field for one parameter. Both controls edit the same value
// and report through `moved`; the owner writes the value back, which keeps the
// movement plan the only place where state lives.

import QtQuick
import QtQuick.Controls.Basic
import DragonArm

Item {
    id: control

    property string label: ""
    property string suffix: ""
    property real value: 0
    property real from: 0
    property real to: 180
    property real stepSize: 1
    property int decimals: 0
    property color accent: Theme.accent

    // Optional highlight showing the mechanically reachable part of the range.
    property real limitFrom: NaN
    property real limitTo: NaN
    property bool showLimits: !isNaN(limitFrom) && !isNaN(limitTo)

    property bool outOfRange: showLimits && (value < limitFrom - 1e-6 || value > limitTo + 1e-6)

    signal moved(real newValue)

    implicitHeight: 54

    function ratio(v) {
        return control.to > control.from ? (v - control.from) / (control.to - control.from) : 0
    }

    Text {
        id: labelText
        anchors.left: parent.left
        anchors.top: parent.top
        text: control.label
        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontTiny
        font.weight: Theme.weightStrong
        font.letterSpacing: 0.5
    }

    Text {
        id: limitHint
        anchors.left: labelText.right
        anchors.leftMargin: Theme.spacingSmall
        anchors.baseline: labelText.baseline
        visible: control.showLimits
        text: "limits " + control.limitFrom.toFixed(0) + "–" + control.limitTo.toFixed(0)
              + control.suffix
        color: control.outOfRange ? Theme.danger : Theme.textMuted
        font.family: Theme.fontFamily
        font.weight: Theme.weightBody
        font.pixelSize: Theme.fontTiny
    }

    TextField {
        id: field

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: -4
        width: 76
        height: 26

        text: control.value.toFixed(control.decimals)
        color: control.outOfRange ? Theme.danger : Theme.textPrimary
        font.family: Theme.monoFamily
        font.pixelSize: Theme.fontBody
        horizontalAlignment: Text.AlignHCenter
        selectByMouse: true
        validator: DoubleValidator {
            bottom: control.from
            top: control.to
            decimals: control.decimals
            notation: DoubleValidator.StandardNotation
        }

        // .gx-input: white / .04, 1 px border; focus turns it accent with a
        // 3 px ring.
        background: Rectangle {
            radius: Theme.radiusSmall
            color: Theme.fade(Theme.white, 0.04)
            border.width: 1
            border.color: field.activeFocus ? Theme.accentBright
                                            : (control.outOfRange ? Theme.danger : Theme.border)

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
            var v = parseFloat(text.replace(",", "."))
            if (isNaN(v)) {
                text = Qt.binding(function () { return control.value.toFixed(control.decimals) })
                return
            }
            v = Math.max(control.from, Math.min(control.to, v))
            control.moved(v)
            text = Qt.binding(function () { return control.value.toFixed(control.decimals) })
        }

        // Re-establish the binding after an external change.
        Connections {
            target: control
            function onValueChanged() {
                if (!field.activeFocus)
                    field.text = control.value.toFixed(control.decimals)
            }
        }
    }

    Slider {
        id: slider

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 22

        from: control.from
        to: control.to
        stepSize: control.stepSize
        snapMode: Slider.SnapAlways

        onMoved: control.moved(value)

        // While the handle is held the slider owns the value; afterwards the
        // plan owns it again.
        Binding {
            target: slider
            property: "value"
            value: control.value
            when: !slider.pressed
            restoreMode: Binding.RestoreNone
        }

        background: Rectangle {
            x: 0
            y: slider.height / 2 - height / 2
            width: slider.availableWidth
            height: 4
            radius: Theme.radiusSmall
            color: Theme.fade(Theme.white, 0.1)

            // Mechanically reachable band.
            Rectangle {
                visible: control.showLimits
                x: parent.width * control.ratio(control.limitFrom)
                width: Math.max(2, parent.width
                                * (control.ratio(control.limitTo) - control.ratio(control.limitFrom)))
                height: parent.height
                radius: parent.radius
                color: Theme.blend(Theme.surfaceHigh, control.accent, 0.22)
            }

            Rectangle {
                width: slider.visualPosition * parent.width
                height: parent.height
                radius: parent.radius
                color: control.outOfRange ? Theme.danger : control.accent
            }
        }

        // .gx-range thumb: a 14 px white SQUARE with an accent halo.
        handle: Rectangle {
            x: slider.visualPosition * (slider.availableWidth - width)
            y: slider.height / 2 - height / 2
            width: 14
            height: 14
            radius: Theme.radiusSmall
            color: Theme.white

            Rectangle {
                anchors.fill: parent
                anchors.margins: slider.pressed || slider.hovered ? -5 : -4
                z: -1
                color: Theme.fade(control.outOfRange ? Theme.danger : control.accent,
                                  slider.pressed ? 0.5 : 0.25)
            }
        }
    }
}
