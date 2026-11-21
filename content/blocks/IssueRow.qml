// IssueRow.qml
//
// One validation message. Clicking it selects the first block involved, so a
// constraint violation leads straight to the block that has to change.

import QtQuick
import DragonArm
import "../common"

Rectangle {
    id: row

    property var issue: null
    property bool compact: false

    readonly property bool isError: issue && issue.severity === "error"
    readonly property color tone: isError ? Theme.danger : Theme.warning

    implicitHeight: body.implicitHeight + 2 * Theme.spacingSmall
    height: implicitHeight
    radius: Theme.radiusSmall
    color: rowMouse.containsMouse
           ? Theme.blend(Theme.surfaceAlt, tone, 0.12)
           : (isError ? Theme.dangerSoft : Theme.warningSoft)
    border.width: 1
    border.color: Theme.fade(tone, 0.4)

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 1
        width: 3
        radius: Theme.radiusSmall
        color: row.tone
    }

    Column {
        id: body

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Theme.spacing
        anchors.rightMargin: Theme.spacingSmall
        spacing: 3

        Text {
            width: parent.width
            text: row.issue ? row.issue.title : ""
            color: row.tone
            wrapMode: Text.WordWrap
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSmall
            font.weight: Theme.weightStrong
        }

        Text {
            width: parent.width
            text: row.issue ? row.issue.message : ""
            color: Theme.textSecondary
            wrapMode: Text.WordWrap
            font.family: Theme.fontFamily
            font.weight: Theme.weightBody
            font.pixelSize: Theme.fontTiny
            lineHeight: 1.25
        }

        Text {
            width: parent.width
            visible: !row.compact && row.issue && row.issue.hint.length > 0
            text: row.issue ? "→ " + row.issue.hint : ""
            color: Theme.textMuted
            wrapMode: Text.WordWrap
            font.family: Theme.fontFamily
            font.weight: Theme.weightBody
            font.pixelSize: Theme.fontTiny
            lineHeight: 1.25
        }
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: row.issue && row.issue.blockIds.length > 0
                     ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (row.issue && row.issue.blockIds.length > 0)
                AppState.selectBlock(row.issue.blockIds[0])
        }
    }
}
