import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.widgets

// A tray app's menu, drawn in the shell's style. Submenus (up to three deep) open in
// place, with a Back row.
MenuCard {
    id: root

    required property var bar
    readonly property var trayItem: bar?.popupData ?? null
    // open submenus, for the tray item they were opened in
    property var stack: []
    property var stackOwner: null
    readonly property var path: stackOwner === trayItem ? stack : []

    function openSubmenu(entry) {
        if (path.length >= 3)
            return;
        stack = [...path, entry];
        stackOwner = trayItem;
    }

    readonly property var entries: opener.children
    minWidth: 200
    maxHeight: bar?.popupMaxHeight ?? 600

    // One opener per level: a submenu's entries only stay loaded while its parent menu
    // is open too.
    QsMenuOpener { id: level0; menu: root.trayItem?.menu ?? null }
    QsMenuOpener { id: level1; menu: root.path[0] ?? null }
    QsMenuOpener { id: level2; menu: root.path[1] ?? null }
    QsMenuOpener { id: level3; menu: root.path[2] ?? null }
    readonly property QsMenuOpener opener: [level0, level1, level2, level3][Math.min(path.length, 3)]

    MenuItem {
        visible: root.path.length > 0
        mark: "‹"
        text: "Back"
        onClicked: root.stack = root.stack.slice(0, -1)
    }
    MenuSeparator { visible: root.path.length > 0 }

    Repeater {
        model: root.opener.children

        ColumnLayout {
            id: entry

            required property QsMenuEntry modelData
            required property int index
            readonly property bool checked: modelData?.checkState === Qt.Checked

            Layout.fillWidth: true
            spacing: 0

            // (apps sometimes start or end a menu with a separator)
            MenuSeparator { visible: (entry.modelData?.isSeparator ?? false) && entry.index > 0 && entry.index < root.opener.children.values.length - 1 }

            MenuItem {
                visible: !(entry.modelData?.isSeparator ?? true)
                enabled: entry.modelData?.enabled ?? false
                text: entry.modelData?.text ?? ""
                mark: entry.modelData?.buttonType === QsMenuButtonType.CheckBox ? (entry.checked ? "✓" : "")
                    : entry.modelData?.buttonType === QsMenuButtonType.RadioButton ? (entry.checked ? "●" : "")
                    : ""
                iconSource: entry.modelData?.icon ?? ""
                submenu: entry.modelData?.hasChildren ?? false
                onClicked: {
                    if (submenu) {
                        root.openSubmenu(entry.modelData);
                    } else {
                        entry.modelData.triggered();
                        root.bar.closePopup();
                    }
                }
            }
        }
    }
}
