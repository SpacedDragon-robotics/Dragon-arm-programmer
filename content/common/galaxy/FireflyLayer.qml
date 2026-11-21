// FireflyLayer.qml
//
// Glowing fireflies (Galaxy Theme, spec section 6): white-lavender and
// purple, never gold, fading in and out along the edges of the screen and of
// selected buttons and panels. About 40 are alive at once, each for
// 1.4-3.8 s, wandering slowly and drifting a little upward.
//
// This layer owns the particle system and paints the fireflies above the
// content. The screen edges emit from here; any other item adds a
// FireflyEmitter inside itself, which emits into this same system
// (published as AppState.fireflySystem).

import QtQuick
import QtQuick.Particles
import DragonArm

Item {
    id: layer

    // Rates are particles per second: alive ~= rate x mean life (2.6 s).
    // The screen edges carry 2.2 / (2.2 + targets) of the total in the spec;
    // here they take a fixed share and each FireflyEmitter adds its own.
    readonly property real edgeRate: Theme.fireflies * 0.45 / 2.6

    enabled: false                      // never takes input

    ParticleSystem {
        id: system
        anchors.fill: parent
        running: layer.visible
        Component.onCompleted: AppState.fireflySystem = system
    }

    // 55 % purple hsl(268 72% 70%), 45 % white hsl(268 30% 93%).
    ImageParticle {
        system: system
        groups: ["flyPurple"]
        source: "qrc:///particleresources/glowdot.png"
        color: Theme.fireflyPurple
        alpha: 0.85
        alphaVariation: 0.3
        entryEffect: ImageParticle.Fade
    }
    ImageParticle {
        system: system
        groups: ["flyWhite"]
        source: "qrc:///particleresources/glowdot.png"
        color: Theme.fireflyWhite
        // White reads much brighter than purple at the same alpha.
        alpha: 0.6
        alphaVariation: 0.3
        entryEffect: ImageParticle.Fade
    }

    // A slow random walk with a slight upward drift.
    Wander {
        system: system
        groups: ["flyPurple", "flyWhite"]
        anchors.fill: parent
        xVariance: 26
        yVariance: 26
        pace: 26
        affectedParameter: Wander.Velocity
    }
    Gravity {
        system: system
        groups: ["flyPurple", "flyWhite"]
        anchors.fill: parent
        angle: 270
        magnitude: 3
    }

    // ---- Screen edges: just inside the window frame, drifting inward -------
    Repeater {
        model: [["flyPurple", 0.55], ["flyWhite", 0.45]]

        Emitter {
            required property var modelData
            system: system
            group: modelData[0]
            x: 12; y: 12
            width: layer.width - 24
            height: layer.height - 24
            shape: RectangleShape { fill: false }
            emitRate: layer.edgeRate * modelData[1]
            lifeSpan: 2600
            lifeSpanVariation: 1200
            size: 9
            sizeVariation: 3
            velocity: AngleDirection { angleVariation: 360; magnitude: 5; magnitudeVariation: 4 }
        }
    }
}
