import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

// OmaGames launcher panel: one row per detected game plugin.
// Summon with:  omarchy-shell shell summon david.omagames '{}'
Item {
  id: root

  property var bar: null
  property var shell: null
  property var service: null
  property var manifest: null

  property bool opened: false

  readonly property string pluginId: "david.omagames"

  // ── Theme ─────────────────────────────────────────────────────────────
  readonly property color themeBg: Color.background
  readonly property color themeFg: Color.foreground
  readonly property color themeAccent: Color.accent
  readonly property color themeMuted: Color.muted
  readonly property color themeUrgent: Color.urgent
  readonly property color surfaceBg: Qt.rgba(themeBg.r, themeBg.g, themeBg.b, 0.96)
  readonly property color lineColor: Qt.rgba(themeFg.r, themeFg.g, themeFg.b, 0.14)
  readonly property string fontFamily: {
    var families = Qt.fontFamilies()
    if (families.indexOf("JetBrains Mono") >= 0) return "JetBrains Mono"
    if (families.indexOf("JetBrainsMono Nerd Font") >= 0) return "JetBrainsMono Nerd Font"
    return families[0] || "sans-serif"
  }

  readonly property var gameList: service ? service.games : []
  readonly property bool scanning: service ? service.scanning : false
  readonly property string scanError: service ? service.error : ""
  readonly property string actionError: service ? service.actionError : ""
  readonly property string busyId: service ? service.busyId : ""
  readonly property string removingId: service ? service.removeBusyId : ""
  readonly property bool busy: busyId !== "" || removingId !== ""

  // ── Panel lifecycle ───────────────────────────────────────────────────
  function open(payloadJson) {
    opened = true
    if (service) service.rescan()
  }

  function close() {
    opened = false
  }

  function launchGame(game) {
    if (!game || root.busy) return
    // Close first so the cabinet opens unobstructed; the launch itself goes
    // through the shared service, which uses the shell IPC route (the scoped
    // shell object cannot toggle other plugins' ids).
    root.close()
    if (service) service.launch(game.id)
    else Quickshell.execDetached(["omarchy-shell", "shell", "toggle", String(game.id)])
  }

  function setShown(game, show) {
    if (!game || !service || root.busy) return
    service.setShown(game.id, show)
  }

  function removeGame(game) {
    if (!game || !service || root.busy) return
    service.remove(game.id)
  }

  function anyVisible() {
    for (var i = 0; i < root.gameList.length; i++) {
      if (root.gameList[i].enabled) return true
    }
    return false
  }

  function toggleAll() {
    if (!service || root.gameList.length === 0) return
    service.setShownAll(!root.anyVisible())
  }

  // Best-effort glyph per known game; falls back to a gamepad.
  function emojiFor(game) {
    var id = String((game && game.id) || "").toLowerCase()
    var name = String((game && game.name) || "").toLowerCase()
    var s = id + " " + name
    if (s.indexOf("invader") >= 0) return "👾"
    if (s.indexOf("omalander") >= 0 || s.indexOf("lander") >= 0 || s.indexOf("moon") >= 0) return "☾"
    if (s.indexOf("quattro") >= 0 || s.indexOf("race") >= 0 || s.indexOf("racer") >= 0
        || s.indexOf("kart") >= 0 || s.indexOf(" gp") >= 0) return "🏁"
    if (s.indexOf("wyrm") >= 0 || s.indexOf("dragon") >= 0) return "🐉"
    if (s.indexOf("tetris") >= 0) return "🟧"
    if (s.indexOf("snake") >= 0) return "🐍"
    if (s.indexOf("chess") >= 0) return "♟️"
    if (s.indexOf("doom") >= 0) return "🔥"
    if (s.indexOf("pac") >= 0) return "🟡"
    return "🎮"
  }

  // ── Window ────────────────────────────────────────────────────────────
  FloatingWindow {
    id: window
    title: "OmaGames"
    implicitWidth: 520
    implicitHeight: 560
    minimumSize: Qt.size(420, 360)
    color: root.themeBg
    visible: root.opened

    onVisibleChanged: {
      if (visible) {
        Qt.callLater(function() { content.forceActiveFocus() })
        return
      }
      if (root.opened) root.close()
    }

    Item {
      id: content
      anchors.fill: parent
      focus: true

      Keys.onEscapePressed: root.close()

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(16)
        spacing: Style.space(8)

        // ── Header ──────────────────────────────────────────────────
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Rectangle {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: 6
            color: root.themeAccent
            Text {
              anchors.centerIn: parent
              text: ""
              color: root.themeBg
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 16
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
              text: "OmaGames"
              color: root.themeFg
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              text: {
                if (root.busy) return "Working…"
                if (!root.service) return "Loading…"
                if (root.scanning && root.gameList.length === 0) return "Scanning installed plugins…"
                if (root.gameList.length === 0) return "No game plugins found"
                var n = root.gameList.length
                return n + " game" + (n === 1 ? "" : "s") + " installed"
              }
              color: root.themeMuted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Button {
            text: root.anyVisible() ? "Hide all" : "Show all"
            foreground: root.themeFg
            tooltipText: root.anyVisible()
              ? "Hide every game icon — they stay launchable from this panel"
              : "Show every game icon in the top bar again"
            onClicked: root.toggleAll()
          }

          Button {
            text: "Refresh"
            foreground: root.themeFg
            tooltipText: "Re-scan installed plugins"
            onClicked: { if (root.service) root.service.rescan() }
          }

          Button {
            iconText: ""
            foreground: root.themeFg
            tooltipText: "Close (Esc)"
            onClicked: root.close()
          }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.lineColor }

        Text {
          Layout.fillWidth: true
          visible: root.scanError !== ""
          text: root.scanError
          color: root.themeUrgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          Layout.fillWidth: true
          visible: root.actionError !== ""
          text: root.actionError
          color: root.themeUrgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        // ── Game list ───────────────────────────────────────────────
        ListView {
          id: gameView
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          spacing: Style.space(6)
          model: root.gameList
          ScrollBar.vertical: ScrollBar {}

          delegate: Rectangle {
            id: row
            property var game: modelData
            property bool confirmingRemove: false
            width: gameView.width
            height: Math.max(64, rowLayout.implicitHeight + Style.space(16))
            radius: Style.cornerRadius
            color: rowHover.hovered
              ? Qt.rgba(root.themeFg.r, root.themeFg.g, root.themeFg.b, 0.07)
              : root.surfaceBg
            border.color: root.lineColor
            border.width: 1

            // Hover-only: unlike a MouseArea, this never intercepts clicks,
            // so the Launch button and toggle switch underneath stay clickable.
            HoverHandler {
              id: rowHover
            }

            Timer {
              id: confirmRemoveTimer
              interval: 4000
              onTriggered: row.confirmingRemove = false
            }

            RowLayout {
              id: rowLayout
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(10)

              Text {
                text: root.emojiFor(row.game)
                font.pixelSize: 26
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                  Layout.fillWidth: true
                  text: row.game.name || row.game.id
                  color: root.themeFg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  Layout.fillWidth: true
                  text: {
                    if (!row.game.hasPanel) return "Bar pet · already lives in your bar"
                    if (!row.game.enabled) return "Off the top bar — still launchable from here"
                    var d = String(row.game.description || "")
                    return d.length > 110 ? d.slice(0, 110) + "…" : (d || row.game.id)
                  }
                  color: root.themeMuted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  wrapMode: Text.NoWrap
                }
              }

              Button {
                visible: row.game.hasPanel
                text: "Launch"
                foreground: root.themeAccent
                selected: true
                bordered: true
                enabled: !root.busy
                tooltipText: "Open " + (row.game.name || row.game.id)
                  + (row.game.enabled ? "" : " (works even while off the bar)")
                onClicked: root.launchGame(row.game)
              }

              ToggleSwitch {
                Layout.alignment: Qt.AlignVCenter
                checked: row.game.enabled
                busy: root.busyId === row.game.id
                foreground: root.themeFg
                accent: root.themeAccent
                onToggled: root.setShown(row.game, !row.game.enabled)
              }

              Button {
                text: root.removingId === row.game.id
                  ? "Removing…"
                  : (row.confirmingRemove ? "Confirm?" : "Remove")
                foreground: row.confirmingRemove ? root.themeUrgent : root.themeMuted
                bordered: row.confirmingRemove
                enabled: !root.busy
                tooltipText: row.confirmingRemove
                  ? "Click again to permanently remove " + (row.game.name || row.game.id) + " from Omarchy"
                  : "Uninstall " + (row.game.name || row.game.id) + " — folder is backed up, not just hidden"
                onClicked: {
                  if (root.busy) return
                  if (row.confirmingRemove) {
                    confirmRemoveTimer.stop()
                    row.confirmingRemove = false
                    root.removeGame(row.game)
                  } else {
                    row.confirmingRemove = true
                    confirmRemoveTimer.restart()
                  }
                }
              }
            }
          }
        }

        Text {
          Layout.fillWidth: true
          visible: !root.scanning && root.gameList.length === 0 && root.scanError === ""
          horizontalAlignment: Text.AlignHCenter
          topPadding: Style.space(24)
          text: "Install a game plugin (e.g. Invaders, Omalander, Quattro GP)\nand it will appear here automatically."
          color: root.themeMuted
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        // ── Footer ──────────────────────────────────────────────────
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)
          Text {
            Layout.fillWidth: true
            text: "Games are detected by category (Games/Fun), tags and aliases. The switch controls the top-bar icon only — Launch always works, shown or hidden."
            color: root.themeMuted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
