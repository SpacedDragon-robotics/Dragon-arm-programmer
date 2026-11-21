// main.cpp -- desktop launcher for the SpaceDragon Robot Programmer.
//
// The application itself is pure QML. This file exists only so the project can
// be shipped as a normal Windows executable: it embeds content/ and imports/
// into the binary as Qt resources, so a released build is a single .exe plus
// the Qt runtime, with no loose QML files for a user to break.
//
// Editing the app never requires touching this file -- see README.txt.

#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQuickStyle>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    app.setApplicationName(QStringLiteral("SpaceDragon Robot Programmer"));
    app.setApplicationVersion(QStringLiteral(SPACEDRAGON_VERSION));
    app.setOrganizationName(QStringLiteral("SpaceDragon"));
    app.setWindowIcon(QIcon(QStringLiteral(":/content/images/appicon.png")));

    // The UI imports QtQuick.Controls.Basic explicitly so every control can be
    // themed; pinning the style here stops a system style from overriding it.
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    QQmlApplicationEngine engine;

    // The DragonArm module (singletons + logic) lives under imports/.
    engine.addImportPath(QStringLiteral(":/imports"));

    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);

    engine.load(QUrl(QStringLiteral("qrc:/content/App.qml")));

    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
