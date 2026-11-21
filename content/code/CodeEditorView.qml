// CodeEditorView.qml
//
// Read-only source view with line numbers and syntax highlighting.
// Lines are rendered individually so a few hundred lines stay cheap.

import QtQuick
import QtQuick.Controls.Basic
import DragonArm
import "SyntaxHighlight.js" as SyntaxHighlight

Item {
    id: view

    property string text: ""
    property int gutterWidth: 52

    // Token colours handed to the tokeniser (named to avoid Item.palette).
    readonly property var syntaxColors: ({
        comment: "#6E6B85",
        keyword: "#C084FC",
        type: "#7C9CF5",
        number: "#4FD1C5",
        string: "#E9A14B",
        preprocessor: "#A78BFA",
        constant: "#9FB8E8",
        func: "#ECEAF6",
        punctuation: "#8E8BA6",
        text: "#ECEAF6"
    })

    readonly property var lines: SyntaxHighlight.highlightDocument(text, syntaxColors)

    Rectangle {
        anchors.fill: parent
        color: Theme.backgroundDeep
        radius: Theme.radiusSmall
        border.width: 1
        border.color: Theme.border
    }

    // Gutter backdrop.
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 1
        width: view.gutterWidth
        color: Theme.surface
        radius: Theme.radiusSmall
    }

    ListView {
        id: list

        anchors.fill: parent
        anchors.margins: 1
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        clip: true
        model: view.lines
        cacheBuffer: 600
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }
        ScrollBar.horizontal: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        contentWidth: Math.max(width, maxLineWidth)
        property real maxLineWidth: 0

        delegate: Item {
            id: lineRow
            required property var modelData
            required property int index

            width: list.contentWidth
            height: 17

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 8
                width: view.gutterWidth - 16
                horizontalAlignment: Text.AlignRight
                text: lineRow.index + 1
                color: Theme.textMuted
                font.family: Theme.monoFamily
                font.pixelSize: 12
            }

            Text {
                id: codeText
                anchors.left: parent.left
                anchors.leftMargin: view.gutterWidth + 10
                text: lineRow.modelData
                textFormat: Text.RichText
                color: Theme.textPrimary
                font.family: Theme.monoFamily
                font.pixelSize: 12

                onImplicitWidthChanged: {
                    var needed = implicitWidth + view.gutterWidth + 26
                    if (needed > list.maxLineWidth)
                        list.maxLineWidth = needed
                }
            }
        }

        // Reset the measured width when the document changes.
        Connections {
            target: view
            function onTextChanged() { list.maxLineWidth = 0 }
        }
    }

    // Off-screen holder used for "Copy code": TextEdit owns a selection and a
    // copy() that reaches the system clipboard without any C++ helper.
    TextEdit {
        id: clipboardHelper
        visible: false
        width: 1
        height: 1
        text: view.text
    }

    function copyToClipboard() {
        clipboardHelper.selectAll()
        clipboardHelper.copy()
        clipboardHelper.deselect()
    }
}
