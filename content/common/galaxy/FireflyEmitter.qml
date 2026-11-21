// FireflyEmitter.qml
//
// Put inside any item that should attract fireflies (buttons, the active
// navigation entry, a hero panel). They are born just outside its edge into
// the shared FireflyLayer system. While the item is hovered a few more
// appear there (the spec's "hover burst", kept small).
//
//     FireflyEmitter { hovered: mouse.containsMouse }
//
// The total stays fixed (spec: ~40 alive): every emitter registers a weight
// in AppState.fireflyWeight and emits its share of the targets' budget.
// Larger items weigh a little more, like the spec's weighted pick.

import QtQuick
import QtQuick.Particles
import DragonArm

Item {
    id: host

    property bool hovered: false
    property bool active: true

    // Spec: 0.6 + min(1, (w + h) / 500) per element.
    readonly property real weight: active && visible && width > 0
                                   ? 0.6 + Math.min(1, (width + height) / 500) : 0
    property real registered: 0

    // Fireflies per second for this item: its share of the 55 % of the
    // total that targets get (the screen edges take the rest), plus the burst.
    readonly property real rate: weight <= 0 ? 0
        : Theme.fireflies * 0.55 / 2.6 * weight / Math.max(weight, AppState.fireflyWeight)
          + (hovered ? Theme.hoverBoost * 2 / 2.6 : 0)

    anchors.fill: parent
    anchors.margins: -7                 // the ring they are born on: 1-14 px out
    enabled: false

    onWeightChanged: {
        AppState.fireflyWeight += weight - registered
        registered = weight
    }
    Component.onCompleted: {
        AppState.fireflyWeight += weight - registered
        registered = weight
    }
    Component.onDestruction: AppState.fireflyWeight -= registered

    Repeater {
        model: AppState.fireflySystem ? [["flyPurple", 0.55], ["flyWhite", 0.45]] : []

        Emitter {
            required property var modelData
            system: AppState.fireflySystem
            group: modelData[0]
            anchors.fill: parent
            enabled: host.rate > 0
            shape: RectangleShape { fill: false }
            emitRate: Math.max(0.001, host.rate * modelData[1])
            lifeSpan: 2600
            lifeSpanVariation: 1200
            size: 9
            sizeVariation: 3
            velocity: AngleDirection { angleVariation: 360; magnitude: 5; magnitudeVariation: 4 }
        }
    }
}
