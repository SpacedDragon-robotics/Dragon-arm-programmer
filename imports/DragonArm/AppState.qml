// AppState.qml
//
// UI-level state: which module is open, what is selected, timeline zoom,
// drag-and-drop bookkeeping and the generated-code cache.
//
// Deliberately separate from MovementPlan: the plan is the document, this is
// the view of it.

pragma Singleton
import QtQuick

QtObject {
    id: app

    // ---- Navigation ----------------------------------------------------
    readonly property string moduleHome: "home"
    readonly property string moduleBlocks: "blocks"
    readonly property string moduleCode: "code"
    readonly property string moduleView3d: "view3d"

    property string currentModule: moduleHome

    // The Code entry is a sub-item of Blocks, so the Blocks group stays open
    // while the user is reading the generated sketch.
    readonly property bool blocksSectionActive: currentModule === moduleBlocks
                                                || currentModule === moduleCode

    function showModule(name) {
        if (currentModule === name)
            return
        currentModule = name
        if (name === moduleCode && !codeUpToDate)
            regenerateCode()
    }

    // ---- Selection -----------------------------------------------------
    property int selectedBlockId: -1

    function selectBlock(blockId) {
        selectedBlockId = blockId
    }

    function clearSelection() {
        selectedBlockId = -1
    }

    // ---- Timeline view -------------------------------------------------
    property real pixelsPerSecond: 72
    readonly property real minPixelsPerSecond: 16
    readonly property real maxPixelsPerSecond: 260

    // Shortest span the timeline always shows, so an empty plan still has a
    // usable ruler.
    readonly property real minimumSpan: 20
    property real snapSeconds: 0.1
    property bool snapEnabled: true

    function zoomBy(factor) {
        pixelsPerSecond = Math.max(minPixelsPerSecond,
                                   Math.min(maxPixelsPerSecond, pixelsPerSecond * factor))
    }

    function snap(seconds) {
        if (!snapEnabled || snapSeconds <= 0)
            return Math.max(0, seconds)
        return Math.max(0, Math.round(seconds / snapSeconds) * snapSeconds)
    }

    // ---- Drag and drop -------------------------------------------------
    //
    // One invisible drag proxy lives in MainShell and follows the cursor.
    // Both the palette and the timeline drive it through these properties, so
    // drop targets (timeline tracks, trash bin) only deal with DropArea.

    readonly property string dragNone: ""
    readonly property string dragPalette: "palette"
    readonly property string dragBlock: "block"

    property string dragKind: dragNone
    property string dragJointId: ""
    // Set instead of dragJointId while a tool-move chip or block is dragged:
    // "up" | "down" | "left" | "right" | "forward" | "back".
    property string dragMoveDirection: ""
    property int dragBlockId: -1
    property real dragX: 0
    property real dragY: 0

    readonly property bool dragging: dragKind !== dragNone

    // Lanes the dragged palette item would land on: the one axis of an axis
    // chip, or every axis a tool move drives.
    readonly property var dragTargetAxes:
        dragKind !== dragPalette ? []
        : (dragMoveDirection !== "" ? RobotLibrary.moveAxes(dragMoveDirection)
                                    : [dragJointId])

    signal dropRequested()

    function beginPaletteDrag(jointId, sceneX, sceneY) {
        dragJointId = jointId
        dragMoveDirection = ""
        dragBlockId = -1
        dragX = sceneX
        dragY = sceneY
        dragKind = dragPalette
    }

    function beginMovePaletteDrag(direction, sceneX, sceneY) {
        dragJointId = ""
        dragMoveDirection = direction
        dragBlockId = -1
        dragX = sceneX
        dragY = sceneY
        dragKind = dragPalette
    }

    function beginBlockDrag(blockId, jointId, sceneX, sceneY) {
        var b = MovementPlan.block(blockId)
        dragJointId = jointId
        dragMoveDirection = b && b.role === "move" ? b.direction : ""
        dragBlockId = blockId
        dragX = sceneX
        dragY = sceneY
        dragKind = dragBlock
    }

    function updateDrag(sceneX, sceneY) {
        dragX = sceneX
        dragY = sceneY
    }

    // Asks MainShell to deliver the drop, then clears the drag state.
    function finishDrag() {
        if (dragKind === dragNone)
            return
        dropRequested()
        cancelDrag()
    }

    function cancelDrag() {
        dragKind = dragNone
        dragJointId = ""
        dragMoveDirection = ""
        dragBlockId = -1
    }

    // ---- Pointer (Galaxy theme) ------------------------------------------
    // Where the mouse is, in window coordinates, written by MainShell. The
    // theme's light comes from the cursor: the cursor glow, the edge glow on
    // panels and buttons, and shadows that fall away from it all read this.
    property real pointerX: -10000
    property real pointerY: -10000
    property bool pointerInside: false

    // The fireflies' particle system (MainShell's FireflyLayer). Buttons and
    // panels place their own emitters into it (FireflyEmitter).
    property var fireflySystem: null
    // Sum of the weights of every visible FireflyEmitter: each emits its
    // share of a fixed total, so ~40 fireflies stay on screen however many
    // buttons attract them (the spec picks a target by weight per firefly).
    property real fireflyWeight: 0

    // ---- Generated code cache ------------------------------------------
    property string generatedCode: ""
    property bool codeUpToDate: false
    property bool codeValid: false
    property string codeGeneratedAt: ""
    property var codeIssues: []

    function regenerateCode() {
        var result = MovementPlan.generateCode()
        generatedCode = result.code
        codeValid = result.ok
        codeIssues = result.issues
        codeUpToDate = true
        codeGeneratedAt = Qt.formatDateTime(new Date(), "HH:mm:ss")
    }

    function clearCode() {
        generatedCode = ""
        codeValid = false
        codeIssues = []
        codeUpToDate = false
        codeGeneratedAt = ""
    }

    function markCodeOutdated() {
        codeUpToDate = false
    }

    // Any edit to the plan or to the hardware invalidates the sketch.
    readonly property Connections planWatcher: Connections {
        target: MovementPlan
        function onPlanChanged() {
            app.markCodeOutdated()
            if (app.selectedBlockId !== -1 && MovementPlan.indexOf(app.selectedBlockId) === -1)
                app.clearSelection()
        }
    }

    readonly property Connections robotWatcher: Connections {
        target: RobotLibrary
        function onCurrentModelChanged() { app.markCodeOutdated() }
    }
}
