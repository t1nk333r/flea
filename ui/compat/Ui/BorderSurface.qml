// API and defaults mirror Omarchy 4.0.4 shell/Ui/BorderSurface.qml (MIT, ../LICENSE.omarchy), limited to what ui/ reads; tests/generic/compat-surface.sh and compat-parity.sh keep it true.
import QtQuick
import qs.Commons

// Rectangle's native border only: compat Border makes flat uniform specs, which is the case Omarchy also draws natively.
Rectangle {
    id: root

    property var borderSpec: Border.none()
    property real padding: 0
    property real topPadding: padding
    property real rightPadding: padding
    property real bottomPadding: padding
    property real leftPadding: padding

    readonly property real borderTop: Border.top(borderSpec)
    readonly property real borderRight: Border.right(borderSpec)
    readonly property real borderBottom: Border.bottom(borderSpec)
    readonly property real borderLeft: Border.left(borderSpec)
    readonly property real contentTopInset: borderTop + topPadding
    readonly property real contentRightInset: borderRight + rightPadding
    readonly property real contentBottomInset: borderBottom + bottomPadding
    readonly property real contentLeftInset: borderLeft + leftPadding

    // A zero-width spec draws no border, so its colour is transparent, as Omarchy's canUseNative arm leaves it.
    border.color: Border.uniformWidth(borderSpec) > 0 ? Border.color(borderSpec) : "transparent"
    border.width: Border.uniformWidth(borderSpec)
}
