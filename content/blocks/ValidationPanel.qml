// ValidationPanel.qml
//
// Status of the whole movement plan. Re-runs on every edit, because
// MovementPlan revalidates before it notifies.

import QtQuick
import QtQuick.Controls.Basic
import DragonArm
import "../common"

PanelCard {
    id: panel

    readonly property bool clean: MovementPlan.errorCount === 0 && MovementPlan.warningCount === 0

    title: "Plan validation"
    subtitle: {
        if (MovementPlan.blockCount === 0)
            return "timeline is empty"
        if (clean)
            return "ready to convert"
        var parts = []
        if (MovementPlan.errorCount > 0)
            parts.push(MovementPlan.errorCount + (MovementPlan.errorCount === 1
                                                  ? " error" : " errors"))
        if (MovementPlan.warningCount > 0)
            parts.push(MovementPlan.warningCount + (MovementPlan.warningCount === 1
                                                    ? " warning" : " warnings"))
        return parts.join(" · ")
    }
    accent: MovementPlan.errorCount > 0 ? Theme.danger
                                        : (MovementPlan.warningCount > 0 ? Theme.warning
                                                                         : Theme.success)

    content: [
        Item {
            anchors.fill: parent

            // -- Everything fine ---------------------------------------
            Column {
                anchors.centerIn: parent
                spacing: Theme.spacingSmall
                visible: panel.clean

                StatusPill {
                    anchors.horizontalCenter: parent.horizontalCenter
                    state_: MovementPlan.blockCount === 0 ? "neutral" : "ok"
                    text: MovementPlan.blockCount === 0 ? "NOTHING TO CHECK" : "PLAN IS VALID"
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    width: panel.width - 40
                    wrapMode: Text.WordWrap
                    text: {
                        if (MovementPlan.blockCount === 0)
                            return "Add blocks to the timeline to start planning."
                        var rules = RobotLibrary.currentModel.constraints.length
                        var base = RobotLibrary.isStepper
                                ? "Travel limits, axis speed and acceleration"
                                : "Servo limits"
                        if (rules > 0)
                            base += " and " + rules + " mechanical constraint"
                                    + (rules === 1 ? "" : "s")
                        return base + " hold across the whole sequence, including "
                               + "simultaneous movements."
                    }
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.weight: Theme.weightBody
                    font.pixelSize: Theme.fontTiny
                }
            }

            // -- Problems ------------------------------------------------
            ListView {
                id: issueList

                anchors.fill: parent
                visible: !panel.clean
                clip: true
                spacing: 6
                model: MovementPlan.issues

                ScrollBar.vertical: ScrollBar {
                    id: issueScrollBar
                    policy: issueList.contentHeight > issueList.height
                            ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                }

                delegate: IssueRow {
                    required property var modelData

                    width: issueList.width - (issueScrollBar.visible ? 12 : 0)
                    issue: modelData
                }
            }
        }
    ]
}
