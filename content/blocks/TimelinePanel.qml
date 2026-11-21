// TimelinePanel.qml
//
// The timeline: one lane per servo, a shared seconds scale, adjustable zoom
// and horizontal scrolling. Vertical position means "which servo", horizontal
// position means "when" -- so two blocks on different lanes at the same x
// start at the same moment and run simultaneously.

import QtQuick
import QtQuick.Controls.Basic
import DragonArm
import "../common"

PanelCard {
    id: panel

    readonly property real pps: AppState.pixelsPerSecond
    readonly property real span: Math.max(AppState.minimumSpan, MovementPlan.endTime + 4)
    readonly property real contentW: span * pps
    readonly property int labelWidth: 108
    // Height of one lane; TimelineTrack and the lane labels use the same value.
    readonly property int laneHeight: 48

    title: "Timeline"
    subtitle: "drag blocks to reposition · drag the right edge to change duration "
              + "· stack lanes to move together"
              + (RobotLibrary.hasKinematics ? " · tool moves span the axes they drive" : "")

    function fitToView() {
        if (flick.width <= 0)
            return
        AppState.pixelsPerSecond = Math.max(
                    AppState.minPixelsPerSecond,
                    Math.min(AppState.maxPixelsPerSecond,
                             flick.width / Math.max(AppState.minimumSpan,
                                                    MovementPlan.endTime + 1)))
    }

    content: [
        Item {
            anchors.fill: parent

            // ---- Toolbar ------------------------------------------------
            Item {
                id: toolbar
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 32

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingSmall

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "ZOOM"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontTiny
                        font.weight: Theme.weightStrong
                        font.letterSpacing: 0.8
                    }

                    Slider {
                        id: zoomSlider
                        anchors.verticalCenter: parent.verticalCenter
                        width: 150
                        height: 20
                        from: AppState.minPixelsPerSecond
                        to: AppState.maxPixelsPerSecond
                        value: AppState.pixelsPerSecond
                        onMoved: AppState.pixelsPerSecond = value

                        Binding {
                            target: zoomSlider
                            property: "value"
                            value: AppState.pixelsPerSecond
                            when: !zoomSlider.pressed
                            restoreMode: Binding.RestoreNone
                        }

                        background: Rectangle {
                            x: 0
                            y: zoomSlider.height / 2 - 2
                            width: zoomSlider.availableWidth
                            height: 4
                            radius: Theme.radiusSmall
                            color: Theme.surfaceHigh

                            Rectangle {
                                width: zoomSlider.visualPosition * parent.width
                                height: parent.height
                                radius: Theme.radiusSmall
                                color: Theme.accent
                            }
                        }

                        handle: Rectangle {
                            x: zoomSlider.visualPosition * (zoomSlider.availableWidth - width)
                            y: zoomSlider.height / 2 - height / 2
                            width: 12
                            height: 12
                            radius: Theme.radiusSmall
                            color: Theme.textPrimary
                            border.width: 2
                            border.color: Theme.accent
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 56
                        text: Math.round(panel.pps) + " px/s"
                        color: Theme.textSecondary
                        font.family: Theme.monoFamily
                        font.pixelSize: Theme.fontTiny
                    }

                    AppButton {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Fit"
                        variant: "ghost"
                        implicitWidth: 46
                        implicitHeight: 24
                        onClicked: panel.fitToView()
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: 18
                        color: Theme.border
                    }

                    AppCheckBox {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Snap 0.1 s"
                        checked: AppState.snapEnabled
                        onToggled: AppState.snapEnabled = checked
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingSmall

                    StatusPill {
                        anchors.verticalCenter: parent.verticalCenter
                        state_: MovementPlan.blockCount === 0 ? "neutral"
                                : (MovementPlan.errorCount > 0 ? "error"
                                   : (MovementPlan.warningCount > 0 ? "warning" : "ok"))
                        text: MovementPlan.endTime.toFixed(2) + " S TOTAL"
                    }

                    AppButton {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Clear"
                        variant: "ghost"
                        danger: true
                        implicitWidth: 60
                        implicitHeight: 24
                        enabled: MovementPlan.blockCount > 0
                        onClicked: MovementPlan.clear()
                    }
                }
            }

            // ---- Lane labels -------------------------------------------
            Item {
                id: labels
                anchors.top: toolbar.bottom
                anchors.topMargin: Theme.spacingSmall
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                width: panel.labelWidth

                Rectangle {
                    anchors.fill: parent
                    color: Theme.surfaceAlt
                    radius: Theme.radiusSmall
                }

                Column {
                    anchors.fill: parent

                    // Aligns with the ruler.
                    Item {
                        width: parent.width
                        height: 28

                        Text {
                            anchors.centerIn: parent
                            text: "AXIS"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontTiny
                            font.weight: Theme.weightStrong
                            font.letterSpacing: 0.8
                        }
                    }

                    Repeater {
                        model: RobotLibrary.joints

                        delegate: Item {
                            id: laneLabel
                            required property var modelData
                            required property int index

                            width: labels.width
                            height: 48

                            Rectangle {
                                anchors.fill: parent
                                color: index % 2 === 0 ? "transparent" : Theme.fade(Theme.surfaceSolid, 0.5)
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 3
                                height: 24
                                radius: Theme.radiusSmall
                                color: laneLabel.modelData.accent
                            }

                            Column {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                Text {
                                    text: laneLabel.modelData.name
                                    color: Theme.textPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSmall
                                    font.weight: Theme.weightStrong
                                }

                                Text {
                                    width: parent.width
                                    text: RobotLibrary.wiringLabel(laneLabel.modelData.id)
                                    color: Theme.textMuted
                                    elide: Text.ElideRight
                                    font.family: Theme.monoFamily
                                    font.pixelSize: Theme.fontTiny
                                }
                            }
                        }
                    }
                }
            }

            // ---- Scrolling lanes ---------------------------------------
            Flickable {
                id: flick

                anchors.top: toolbar.bottom
                anchors.topMargin: Theme.spacingSmall
                anchors.left: labels.right
                anchors.leftMargin: 4
                anchors.right: parent.right
                anchors.bottom: parent.bottom

                clip: true
                contentWidth: panel.contentW
                contentHeight: lanes.height
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds

                // Block drags must not pan the view.
                interactive: !AppState.dragging

                ScrollBar.horizontal: ScrollBar {
                    policy: ScrollBar.AlwaysOn
                }

                Column {
                    id: lanes
                    width: panel.contentW

                    TimelineRuler {
                        id: ruler
                        width: panel.contentW
                        pixelsPerSecond: panel.pps
                        span: panel.span
                    }

                    Repeater {
                        model: RobotLibrary.joints

                        delegate: TimelineTrack {
                            required property var modelData
                            required property int index

                            width: panel.contentW
                            joint: modelData
                            rowIndex: index
                            pixelsPerSecond: panel.pps
                            span: panel.span
                            majorStep: ruler.majorStep
                        }
                    }
                }

                // ---- Tool moves ---------------------------------------
                // A tool move drives several axes at once, so it is drawn
                // over the tracks, covering every lane it uses, rather than
                // inside one of them. The layer itself takes no input: clicks
                // and drops outside a block fall through to the tracks.
                Item {
                    id: moveLayer

                    y: ruler.height
                    width: panel.contentW
                    height: lanes.height - ruler.height

                    Repeater {
                        model: {
                            MovementPlan.revision
                            var ids = []
                            for (var i = 0; i < MovementPlan.blocks.count; ++i) {
                                var b = MovementPlan.blocks.get(i)
                                if (b.role === "move")
                                    ids.push(b.blockId)
                            }
                            return ids
                        }

                        delegate: TimelineBlock {
                            required property var modelData

                            // First and last lane among the axes it drives.
                            readonly property var laneSpan: {
                                var lo = -1, hi = -1
                                for (var i = 0; i < moveAxes.length; ++i) {
                                    var lane = RobotLibrary.jointIndex(moveAxes[i])
                                    if (lane < 0)
                                        continue
                                    lo = lo < 0 ? lane : Math.min(lo, lane)
                                    hi = Math.max(hi, lane)
                                }
                                return lo < 0 ? [0, 1] : [lo, hi - lo + 1]
                            }

                            blockId: modelData
                            pixelsPerSecond: panel.pps
                            laneHeight: panel.laneHeight
                            firstLane: laneSpan[0]
                            laneCount: laneSpan[1]
                        }
                    }
                }

                // End-of-sequence marker.
                Rectangle {
                    x: MovementPlan.endTime * panel.pps
                    y: 0
                    width: 1
                    height: lanes.height
                    color: Theme.accentBright
                    opacity: 0.6
                    visible: MovementPlan.blockCount > 0
                }
            }

            // Click empty space to deselect.
            MouseArea {
                anchors.fill: flick
                z: -1
                onClicked: AppState.clearSelection()
            }
        }
    ]
}
