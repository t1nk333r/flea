// API and defaults mirror Omarchy 4.0.4 shell/Ui/PanelSeparator.qml (MIT, ../LICENSE.omarchy), limited to what ui/ reads; tests/generic/compat-surface.sh and compat-parity.sh keep it true.
import QtQuick
import qs.Commons

Rectangle {
    id: root

    property color foreground: Color.foreground
    property real strength: 0.12

    width: parent ? parent.width : implicitWidth
    implicitWidth: 100
    implicitHeight: 1
    height: 1
    color: Qt.rgba(foreground.r, foreground.g, foreground.b, strength)
}
