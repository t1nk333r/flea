// API and defaults mirror Omarchy 4.0.4 shell/Ui/PanelSectionHeader.qml (MIT, ../LICENSE.omarchy), limited to what ui/ reads; tests/generic/compat-surface.sh and compat-parity.sh keep it true.
import QtQuick
import qs.Commons

Text {
    id: root

    property color foreground: Color.foreground
    property string fontFamily: Style.font.family
    property real fontSize: Style.font.caption

    // Plain text, because a title can carry a device or file name that must never promote itself to rich text.
    textFormat: Text.PlainText
    color: Qt.darker(foreground, 1.4)
    font.family: fontFamily
    font.pixelSize: fontSize
    font.bold: true
    // Glyphs overshoot their ascent, and a header at the top of a clipping list would lose that sliver.
    topPadding: Math.ceil(fontSize * 0.15)
}
