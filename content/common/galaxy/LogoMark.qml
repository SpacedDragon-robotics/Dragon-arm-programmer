// LogoMark.qml -- the SpaceDragon brand mark: the dragon-head logo from the
// website (content/images/logo.png), softly glowing in the accent colour the
// way the site shows it (CSS drop-shadow 0 0 10px accent-glow).

import QtQuick
import QtQuick.Effects
import DragonArm

Item {
    id: mark

    width: 38
    height: 38

    Image {
        id: art
        anchors.fill: parent
        source: "../../images/logo.png"
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        // Decode at the drawn size (x2 for high-DPI) rather than 256 px.
        sourceSize.width: Math.ceil(mark.width * 2)
        sourceSize.height: Math.ceil(mark.height * 2)
        visible: false
    }

    // drop-shadow(0 0 10px accent-glow)
    MultiEffect {
        anchors.fill: art
        source: art
        shadowEnabled: true
        shadowColor: Theme.accentGlow
        shadowBlur: 0.6
        blurMax: 20
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 0
    }
}
