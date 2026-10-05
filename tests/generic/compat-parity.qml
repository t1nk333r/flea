// Probe for tests/generic/compat-parity.sh: loaded once against Omarchy's Commons and Ui and once against
// ui/compat, it prints one "parity <fixture> <key>=<value>" line per value ui/ reads; the two sets must match.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui

ShellRoot {
    id: root

    // "initial" reports the startup values before any theme is loaded: the no-theme palette and type
    // scale under the user override, which loadColors("") would not reset once a theme set them.
    // "user" is the stock theme under the ~/.config/omarchy/shell.toml compat-parity.sh writes, which
    // each Commons reads through its own file watcher at startup; then that layer is cleared so the
    // other fixtures compare the theme alone.
    readonly property var fixtures: ["initial", "user", "empty", "stock", "hostile"]

    // name -> {colors, shell}; the empty fixture is two empty strings, the others are read once at startup.
    function fixture(name) {
        if (name === "stock" || name === "user")
            return { colors: stockColors.text(), shell: stockShell.text() };
        if (name === "hostile")
            return { colors: hostileColors.text(), shell: hostileShell.text() };
        return { colors: "", shell: "" };
    }

    FileView { id: stockColors; path: Quickshell.shellDir + "/fixtures/stock/colors.toml"; blockLoading: true }
    FileView { id: stockShell; path: Quickshell.shellDir + "/fixtures/stock/shell.toml"; blockLoading: true }
    FileView { id: hostileColors; path: Quickshell.shellDir + "/fixtures/hostile/colors.toml"; blockLoading: true }
    FileView { id: hostileShell; path: Quickshell.shellDir + "/fixtures/hostile/shell.toml"; blockLoading: true }

    function emit(name, key, value) {
        console.log("parity " + name + " " + key + "=" + String(value));
    }

    function report(name) {
        var values = {
            "Color.foreground": Color.foreground, "Color.background": Color.background,
            "Color.accent": Color.accent, "Color.urgent": Color.urgent,
            "Color.urgent.hsvSaturation": Color.urgent.hsvSaturation.toFixed(4),
            "Style.cornerRadius": Style.cornerRadius, "Style.normalBorderWidth": Style.normalBorderWidth,
            "Style.hoverFillAlpha": Style.hoverFillAlpha, "Style.selectionFillAlpha": Style.selectionFillAlpha,
            "Style.normalFill": Style.normalFill, "Style.hoverFill": Style.hoverFill,
            "Style.selectedFill": Style.selectedFill, "Style.selectionFill": Style.selectionFill,
            "Style.selectedAccentFill": Style.selectedAccentFill, "Style.hoverBorderColor": Style.hoverBorderColor,
            "Style.space(0)": Style.space(0), "Style.space(1)": Style.space(1), "Style.space(7)": Style.space(7),
            "Style.space(10)": Style.space(10), "Style.space(220)": Style.space(220), "Style.space(-3)": Style.space(-3),
            "Style.spacing.hairline": Style.spacing.hairline, "Style.spacing.rowPaddingX": Style.spacing.rowPaddingX,
            "Style.spacing.rowGap": Style.spacing.rowGap, "Style.spacing.panelGap": Style.spacing.panelGap,
            "Style.spacing.controlPaddingY": Style.spacing.controlPaddingY,
            "Style.font.family": Style.font.family, "Style.font.resolvedFamily": Style.font.resolvedFamily,
            "Style.font.baseSize": Style.font.baseSize, "Style.font.caption": Style.font.caption,
            "Style.font.bodySmall": Style.font.bodySmall, "Style.font.body": Style.font.body,
            "Style.font.icon": Style.font.icon,
            "Util.alpha(hex,0.5)": Util.alpha("#336699", 0.5), "Util.alpha(null,0.3)": Util.alpha(null, 0.3),
            "Util.alpha(accent,2)": Util.alpha(Color.accent, 2), "Util.alpha(urgent,-1)": Util.alpha(Color.urgent, -1),
            "Util.fileUrl": Util.fileUrl("/home/a b/c#d%e.png"), "Util.fileUrl(empty)": Util.fileUrl(""),
            "Border.flat": JSON.stringify(Border.flat(Color.accent, 2)), "Border.flat(-1)": JSON.stringify(Border.flat("", -1)),
            "Border.none": JSON.stringify(Border.none()),
            "PanelSectionHeader.color": header.color, "PanelSectionHeader.pixelSize": header.font.pixelSize,
            "PanelSectionHeader.family": header.font.family, "PanelSectionHeader.bold": header.font.bold,
            "PanelSectionHeader.topPadding": header.topPadding, "PanelSectionHeader.textFormat": header.textFormat,
            "PanelSeparator.color": separator.color, "PanelSeparator.height": separator.height,
            "PanelSeparator.width": separator.width,
            "BorderSurface.border.width": surface.border.width, "BorderSurface.border.color": surface.border.color,
            "BorderSurface.insets": [surface.contentTopInset, surface.contentRightInset, surface.contentBottomInset,
                                     surface.contentLeftInset].join(","),
            "BorderSurface(none).border": bare.border.width + " " + bare.border.color + " " + bare.contentTopInset
        };
        for (var key in values)
            emit(name, key, values[key]);
    }

    Item {
        width: 300
        height: 200

        PanelSectionHeader { id: header; text: "SECTION" }
        PanelSeparator { id: separator }
        BorderSurface {
            id: surface
            width: 100
            height: 40
            padding: Style.space(14)
            borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
        }
        BorderSurface { id: bare; width: 10; height: 10 }
    }

    // Past the startup loads both Commons start on their own (theme files, fontconfig), so a late one
    // cannot land on top of a fixture.
    Timer {
        interval: 1500
        running: true
        onTriggered: {
            for (var i = 0; i < root.fixtures.length; i++) {
                var name = root.fixtures[i];
                var input = root.fixture(name);
                // An unread fixture would compare defaults with defaults and pass for nothing.
                if (name !== "empty" && name !== "initial" && (!input.colors || !input.shell)) {
                    console.log("parity-error fixture " + name + " was not read");
                    Qt.quit();
                    return;
                }
                if (name !== "initial") {
                    Color.loadColors(input.colors);
                    Color.loadShell(input.shell);
                }
                root.report(name);
                if (name === "user")
                    Color.loadUserShell("");
            }
            console.log("parity done");
            Qt.quit();
        }
    }
}
