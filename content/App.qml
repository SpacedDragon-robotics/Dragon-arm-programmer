// App.qml -- application entry point (mainFile of the .qmlproject).

import QtQuick
import DragonArm

Window {
    id: window

    width: 1480
    height: 920
    minimumWidth: 1120
    minimumHeight: 700
    visible: true
    title: "SpaceDragon Robot Programmer – " + RobotLibrary.currentModelName
    color: Theme.backgroundDeep

    // The theme's typeface ships with the app (SIL Open Font License, see
    // fonts/OFL.txt). Loading it registers "Manrope" for every Text.
    FontLoader {
        source: "fonts/Manrope-Variable.ttf"
    }

    MainShell {
        anchors.fill: parent
    }
}
