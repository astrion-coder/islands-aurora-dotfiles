import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.widgets

// Beside the clipboard list: the selected entry, previewed. Images large with their size;
// links as a card (picture, site, title, description, address) that opens the page when
// clicked; colours as a swatch; text in full with a count, its web addresses clickable.
Rectangle {
    id: root

    required property var mode
    readonly property var entry: mode.current
    readonly property string kind: entry?.kind ?? ""
    readonly property var link: mode.link

    // open a web page in the browser (and get the launcher out of the way)
    function open(url) {
        if (!/^https?:\/\//.test(url))
            return;
        Launcher.close();
        Quickshell.execDetached(["xdg-open", url]);
    }

    // plain text as rich text, with its web addresses as links
    function linkify(text) {
        const safe = text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        return safe.replace(/https?:\/\/[^\s<>"']*[^\s<>"'.,;:!?)\]]/g, url => `<a href="${url}">${url}</a>`)
                   .replace(/\n/g, "<br>");
    }

    radius: 14
    color: Theme.alpha(Theme.fg, 0.06)

    Label {
        anchors.centerIn: parent
        visible: root.entry === null
        text: "nothing selected"
        color: Theme.muted
        font.pixelSize: 13
    }

    // ---------------------------------------------------------------- image
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        visible: root.kind === "image"
        spacing: 10

        Image {
            Layout.fillWidth: true
            Layout.fillHeight: true
            source: root.kind === "image" && root.entry.thumb ? "file://" + root.entry.thumb : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            mipmap: true
            sourceSize.width: 700
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text: root.kind === "image" ? `${root.entry.format} image, ${root.entry.width} × ${root.entry.height}, ${root.entry.size}` : ""
            color: Theme.subtle
            font.pixelSize: 13
        }
    }

    // ---------------------------------------------------------------- link
    // the whole card opens the page
    MouseArea {
        id: linkCard
        anchors.fill: parent
        visible: root.kind === "link"
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.open(root.entry.url)

        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: Theme.alpha(Theme.accent, 0.08)
            opacity: linkCard.containsMouse ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        visible: root.kind === "link"
        spacing: 8
        clip: true

        // the page's picture, whole (its own shape; narrower if it's tall)
        Item {
            id: picture
            readonly property real aspect: pic.implicitWidth > 0 ? pic.implicitHeight / pic.implicitWidth : 0.5
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(Math.round(width * aspect), 250)
            visible: (root.link?.image ?? "") !== ""

            ClippingRectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                height: parent.height
                width: Math.min(parent.width, Math.round(height / picture.aspect))
                radius: 10
                color: "transparent"

                Image {
                    id: pic
                    anchors.fill: parent
                    source: root.link?.image ? "file://" + root.link.image : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    sourceSize.width: 700
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            IconImage {
                visible: (root.link?.icon ?? "") !== ""
                source: root.link?.icon ? "file://" + root.link.icon : ""
                implicitSize: 16
            }
            Label {
                Layout.fillWidth: true
                text: root.link?.site ?? (root.entry?.url ?? "").replace(/^https?:\/\/([^/]+).*/, "$1")
                color: Theme.subtle
                font.pixelSize: 13
                elide: Text.ElideRight
            }
        }

        Label {
            Layout.fillWidth: true
            visible: text !== ""
            text: root.mode.fetching ? "loading preview…" : root.link?.title ?? ""
            color: root.mode.fetching ? Theme.muted : linkCard.containsMouse ? Theme.accent : Theme.fg
            font.pixelSize: 15
            font.weight: root.mode.fetching ? Font.Medium : Font.Bold
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        Label {
            Layout.fillWidth: true
            visible: text !== ""
            text: root.link?.description ?? ""
            color: Theme.subtle
            font.pixelSize: 13
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Item { Layout.fillHeight: true }

        Label {
            Layout.fillWidth: true
            text: root.entry?.url ?? ""
            color: linkCard.containsMouse ? Theme.accent : Theme.muted
            font.pixelSize: 12
            font.underline: linkCard.containsMouse
            elide: Text.ElideMiddle
        }
    }

    // ---------------------------------------------------------------- colour
    ColumnLayout {
        anchors.centerIn: parent
        visible: root.kind === "color"
        spacing: 12

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 120
            implicitHeight: 120
            radius: 24
            color: root.kind === "color" ? root.entry.swatch : "transparent"
            border.width: 1
            border.color: Theme.edge
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text: root.entry?.title ?? ""
            font.pixelSize: 15
            font.weight: Font.Bold
        }
    }

    // ---------------------------------------------------------------- text
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        visible: root.kind === "text" || root.kind === "binary"
        spacing: 8

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Label {
                id: body
                width: parent.width
                text: root.linkify(root.kind === "binary" ? "binary data (" + root.entry.size + ")" : root.mode.text || root.entry?.title || "")
                font.pixelSize: 13
                font.weight: Font.Normal
                verticalAlignment: Text.AlignTop
                wrapMode: Text.Wrap     // at words; very long ones (links, paths) anywhere
                textFormat: Text.StyledText
                linkColor: Theme.accent
                onLinkActivated: url => root.open(url.replace(/&amp;/g, "&"))

                HoverHandler {
                    cursorShape: body.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
            }
        }
        Label {
            visible: root.kind === "text" && root.mode.text !== ""
            text: {
                const t = root.mode.text;
                const words = t.trim() === "" ? 0 : t.trim().split(/\s+/).length;
                const lines = t.split("\n").length;
                return `${t.length} characters, ${words} word${words === 1 ? "" : "s"} and ${lines} line${lines === 1 ? "" : "s"}`;
            }
            color: Theme.muted
            font.pixelSize: 12
        }
    }
}
