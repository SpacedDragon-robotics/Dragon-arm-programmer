// PlaceholderArt.qml
//
// Stand-in for artwork that is not drawn yet: a dashed frame, a schematic arm
// and a note saying where the real asset goes. Set `source` to a file in
// content/images and the placeholder steps aside automatically.

import QtQuick
import DragonArm

Item {
    id: art

    property string source: ""
    property string caption: "Artwork placeholder"
    property string path: "content/images/"
    property color accent: Theme.accent
    property bool showCaption: true

    readonly property bool hasImage: source.length > 0 && image.status === Image.Ready

    Image {
        id: image
        anchors.fill: parent
        source: art.source
        fillMode: Image.PreserveAspectFit
        visible: art.hasImage
        asynchronous: true
    }

    Item {
        anchors.fill: parent
        visible: !art.hasImage

        // Faint technical grid.
        Canvas {
            id: grid
            anchors.fill: parent
            opacity: 0.5

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = Theme.border
                ctx.lineWidth = 1
                var step = 22
                for (var x = step; x < width; x += step) {
                    ctx.beginPath()
                    ctx.moveTo(x + 0.5, 0)
                    ctx.lineTo(x + 0.5, height)
                    ctx.stroke()
                }
                for (var y = step; y < height; y += step) {
                    ctx.beginPath()
                    ctx.moveTo(0, y + 0.5)
                    ctx.lineTo(width, y + 0.5)
                    ctx.stroke()
                }
            }
        }

        // Schematic 3-axis arm, so the slot reads as "robot" before the real
        // render exists.
        Canvas {
            id: armSketch
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.62, parent.height * 1.15)
            height: width * 0.72

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var s = Math.min(width / 200, height / 144)
                ctx.scale(s, s)
                ctx.lineCap = "round"
                ctx.lineJoin = "round"

                // Base
                ctx.strokeStyle = Theme.textMuted
                ctx.lineWidth = 5
                ctx.beginPath()
                ctx.moveTo(30, 132)
                ctx.lineTo(86, 132)
                ctx.stroke()

                ctx.lineWidth = 4
                ctx.strokeStyle = art.accent
                // Axis-1 column
                ctx.beginPath()
                ctx.moveTo(58, 132)
                ctx.lineTo(58, 100)
                ctx.stroke()
                // Axis-2 link
                ctx.beginPath()
                ctx.moveTo(58, 100)
                ctx.lineTo(108, 52)
                ctx.stroke()
                // Axis-3 link
                ctx.beginPath()
                ctx.moveTo(108, 52)
                ctx.lineTo(160, 76)
                ctx.stroke()
                // Gripper jaws
                ctx.beginPath()
                ctx.moveTo(160, 76)
                ctx.lineTo(176, 66)
                ctx.moveTo(160, 76)
                ctx.lineTo(174, 88)
                ctx.stroke()

                // Joint markers
                ctx.fillStyle = Theme.surface
                ctx.strokeStyle = Theme.textSecondary
                ctx.lineWidth = 3
                var joints = [[58, 100], [108, 52], [160, 76]]
                for (var i = 0; i < joints.length; ++i) {
                    ctx.beginPath()
                    ctx.arc(joints[i][0], joints[i][1], 6, 0, Math.PI * 2)
                    ctx.fill()
                    ctx.stroke()
                }
            }
        }

        // Dashed frame.
        Canvas {
            anchors.fill: parent

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = Theme.borderStrong
                ctx.lineWidth = 1
                ctx.setLineDash([6, 5])
                ctx.strokeRect(0.5, 0.5, width - 1, height - 1)
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            spacing: 1
            visible: art.showCaption && parent.height > 110

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: art.caption
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTiny
                font.weight: Theme.weightStrong
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: art.path
                color: Theme.textMuted
                opacity: 0.7
                font.family: Theme.monoFamily
                font.pixelSize: Theme.fontTiny
            }
        }
    }
}
