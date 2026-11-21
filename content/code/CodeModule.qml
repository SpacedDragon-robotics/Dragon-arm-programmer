// CodeModule.qml
//
// The generated Arduino sketch. Opening this module regenerates the code when
// it is out of date; editing anything in Blocks marks it out of date again.

import QtQuick
import QtQuick.Controls.Basic
import DragonArm
import "../common"
import "../blocks"

Item {
    id: codeModule

    readonly property bool hasCode: AppState.generatedCode.length > 0
    readonly property bool blocked: MovementPlan.errorCount > 0

    // ---- Header ---------------------------------------------------------
    Item {
        id: header

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacing
        height: 58

        Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                text: "Arduino code"
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTitle
                font.weight: Theme.weightStrong
            }

            Text {
                // The stepper models have no I2C address, so the bus detail is
                // only meaningful for the PWM arms.
                text: {
                    var m = RobotLibrary.currentModel
                    var parts = [RobotLibrary.currentModelName, m.driver]
                    if (!RobotLibrary.isStepper && m.i2cAddress !== undefined)
                        parts.push("0x" + m.i2cAddress.toString(16).toUpperCase())
                    parts.push(m.controller)
                    return parts.join(" · ")
                }
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.weight: Theme.weightBody
                font.pixelSize: Theme.fontTiny
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingSmall

            StatusPill {
                anchors.verticalCenter: parent.verticalCenter
                state_: {
                    if (!codeModule.hasCode)
                        return "neutral"
                    if (!AppState.codeValid)
                        return "error"
                    return AppState.codeUpToDate ? "ok" : "warning"
                }
                text: {
                    if (!codeModule.hasCode)
                        return "NOT GENERATED"
                    if (!AppState.codeValid)
                        return "PLAN REJECTED"
                    return AppState.codeUpToDate
                            ? "MATCHES TIMELINE · " + AppState.codeGeneratedAt
                            : "OUTDATED – REGENERATE"
                }
            }

            AppButton {
                anchors.verticalCenter: parent.verticalCenter
                text: AppState.codeUpToDate && codeModule.hasCode ? "Regenerate" : "Convert"
                variant: "primary"
                onClicked: AppState.regenerateCode()
            }

            AppButton {
                anchors.verticalCenter: parent.verticalCenter
                text: copyFeedback.running ? "Copied" : "Copy code"
                enabled: codeModule.hasCode
                onClicked: {
                    editor.copyToClipboard()
                    copyFeedback.restart()
                }

                Timer {
                    id: copyFeedback
                    interval: 1400
                }
            }

            AppButton {
                anchors.verticalCenter: parent.verticalCenter
                text: "Clear"
                variant: "ghost"
                danger: true
                enabled: codeModule.hasCode
                onClicked: AppState.clearCode()
            }
        }
    }

    // ---- Validation banner ---------------------------------------------
    Rectangle {
        id: banner

        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.spacing
        anchors.rightMargin: Theme.spacing
        height: visible ? 44 : 0
        visible: codeModule.blocked
        radius: Theme.radiusSmall
        color: Theme.dangerSoft
        border.width: 1
        border.color: Theme.fade(Theme.danger, 0.5)

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingSmall

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "⚠"
                color: Theme.danger
                font.pixelSize: 16
                font.bold: true
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: MovementPlan.errorCount
                      + (MovementPlan.errorCount === 1 ? " problem" : " problems")
                      + " must be fixed before an executable sketch is generated."
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.weight: Theme.weightBody
                font.pixelSize: Theme.fontSmall
            }
        }

        AppButton {
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacing
            anchors.verticalCenter: parent.verticalCenter
            text: "Back to Blocks"
            variant: "secondary"
            implicitHeight: 26
            onClicked: AppState.showModule(AppState.moduleBlocks)
        }
    }

    // ---- Code + issues --------------------------------------------------
    Item {
        anchors.top: banner.bottom
        anchors.topMargin: codeModule.blocked ? Theme.spacing : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Theme.spacing
        anchors.rightMargin: Theme.spacing
        anchors.bottomMargin: Theme.spacing

        CodeEditorView {
            id: editor

            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: issuePane.visible ? issuePane.left : parent.right
            anchors.rightMargin: issuePane.visible ? Theme.spacing : 0
            visible: codeModule.hasCode

            text: AppState.generatedCode
        }

        // Empty state
        Rectangle {
            anchors.fill: parent
            visible: !codeModule.hasCode
            radius: Theme.radiusSmall
            color: Theme.surface
            border.width: 1
            border.color: Theme.border

            Column {
                anchors.centerIn: parent
                spacing: Theme.spacing

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No sketch yet"
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontTitle
                    font.weight: Theme.weightStrong
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: "Convert the timeline to generate an Arduino sketch for\n"
                          + RobotLibrary.currentModel.servoType + " on "
                          + RobotLibrary.currentModel.driver + "."
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.weight: Theme.weightBody
                    font.pixelSize: Theme.fontSmall
                }

                AppButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Convert timeline"
                    variant: "primary"
                    onClicked: AppState.regenerateCode()
                }
            }
        }

        // Problem list beside the code when the plan was rejected.
        Rectangle {
            id: issuePane

            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 340
            visible: codeModule.blocked && codeModule.hasCode
            radius: Theme.radiusSmall
            color: Theme.surface
            border.width: 1
            border.color: Theme.border

            SectionHeader {
                id: issueHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.spacing
                text: "Blocking problems"
            }

            ListView {
                anchors.top: issueHeader.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Theme.spacing
                anchors.topMargin: Theme.spacingSmall
                clip: true
                spacing: 6
                model: MovementPlan.issues

                delegate: IssueRow {
                    required property var modelData

                    width: ListView.view.width
                    issue: modelData
                }
            }
        }
    }
}
