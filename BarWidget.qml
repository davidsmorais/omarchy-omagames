import QtQuick
import qs.Commons
import qs.Ui

// OmaGames bar widget: one gamepad icon for every installed game plugin.
// Left click summons the launcher panel; the panel does the launching.
BarWidget {
  id: root
  moduleName: "david.omagames"

  property var gamesService: null
  readonly property int gameCount: gamesService ? gamesService.games.length : 0
  readonly property bool scanning: gamesService ? gamesService.scanning : false

  readonly property string tooltip: {
    if (!gamesService || scanning) return "OmaGames — scanning for games…"
    if (gameCount === 0) return "OmaGames — no game plugins found"
    return "OmaGames — " + gameCount + " game" + (gameCount === 1 ? "" : "s")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onSettingsChanged: {
    if (gamesService) gamesService.settings = root.settings
  }

  // serviceFor() is not reactive when the service finishes loading
  // asynchronously, so poll until it resolves (same pattern as
  // david.singularity). Also pushes bar settings into the service once.
  Timer {
    interval: 250
    repeat: true
    running: root.bar && root.bar.shell && !root.gamesService
    onTriggered: {
      var svc = root.bar.shell.serviceFor("david.omagames")
      if (!svc) return
      root.gamesService = svc
      if (root.settings) svc.settings = root.settings
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    fontFamily: "JetBrainsMono Nerd Font"
    foreground: root.gameCount > 0 ? Color.accent : Color.muted
    tooltipText: root.tooltip
    onPressed: function(b) {
      if (!root.bar || !root.bar.shell) return
      if (b === Qt.LeftButton) root.bar.shell.summon("david.omagames", "{}")
      else if (b === Qt.RightButton) root.bar.shell.toggle("david.omagames", "{}")
    }
  }
}
