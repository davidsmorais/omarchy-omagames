import QtQuick
import Quickshell
import Quickshell.Io

// OmaGames background service. Owns the detected game list: it runs
// scan-games.py (manifest scan + `omarchy plugin list` enabled state) on a
// timer and whenever settings change, so newly installed games appear without
// a shell restart. The panel only reads `games` from here.
Item {
  id: root

  readonly property string pluginId: "david.omagames"
  // Injected by the shell when the service instance is created.
  property var shell: null
  property var settings: ({ extraIds: "", hiddenIds: "" })

  property var games: []
  property bool scanning: false
  property string error: ""
  property string lastScan: ""

  // State for show/hide (add-to/remove-from bar) actions. `enabled` in
  // `omarchy plugin list` is `inBar(id)` for a bar-widget, so plain
  // `omarchy plugin disable` would also make the game un-summonable — the
  // shell refuses to open a plugin that isn't "enabled". bar-visibility.py
  // works around that: it keeps the game's id in shell.json's top-level
  // `plugins[]` array (which the shell's panel loader treats as enabled on
  // its own, independent of bar placement) before/after delegating the
  // actual bar.layout mutation to `omarchy plugin enable/disable`. Net
  // effect: hiding removes the bar icon but launch() keeps working. The CLI
  // reports failure even on success (its IPC reply times out during the
  // shell's reload), so actions are verified by re-scanning instead of
  // trusting the exit code.
  property string actionError: ""
  property string busyId: ""
  property var pendingVerify: null

  readonly property string scriptPath: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/david.omagames/scan-games.py"
  readonly property string barVisibilityScriptPath: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/david.omagames/bar-visibility.py"

  // "a, b,,c" -> ["a", "b", "c"]
  function csv(value) {
    var out = []
    var parts = String(value || "").split(",")
    for (var i = 0; i < parts.length; i++) {
      var s = parts[i].trim()
      if (s !== "") out.push(s)
    }
    return out
  }

  function rescan() {
    if (root.scanning) return
    root.scanning = true
    root.error = ""
    var proc = scanComponent.createObject(root, {
      payload: JSON.stringify({
        extra: csv(root.settings.extraIds),
        hidden: csv(root.settings.hiddenIds)
      })
    })
    if (!proc) {
      root.scanning = false
      root.error = "Could not start game scan"
      return
    }
    proc.running = true
  }

  // Open a game through the shell's IPC route — the exact command the games
  // themselves document (`omarchy-shell shell toggle <id>`). This must NOT go
  // through the injected `shell` object: third-party plugins receive a scoped
  // shell that only permits toggling their own id, so shell.toggle(gameId)
  // always returns false here. The CLI talks to the unscoped IPC handler.
  function launch(id) {
    var pid = String(id || "")
    if (pid === "") return
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", pid])
  }

  function enable(id) {
    setShown(id, true)
  }

  function disable(id) {
    setShown(id, false)
  }

  // Uninstall the plugin folder entirely (backed up unless it's a bare git
  // clone). Separate from the show/hide queue above: it doesn't verify
  // against an enabled/disabled state afterward, it just re-scans and lets
  // the removed game drop out of the list on its own.
  property string removeBusyId: ""

  function remove(id) {
    var pid = String(id || "")
    if (pid === "" || root.removeBusyId !== "") return
    root.removeBusyId = pid
    root.actionError = ""
    var proc = removeActionComponent.createObject(root, {
      actionCommand: ["omarchy", "plugin", "remove", pid, "--yes"]
    })
    if (!proc) {
      root.removeBusyId = ""
      root.actionError = "Could not start remove"
      return
    }
    proc.running = true
  }

  // Queued hide/show actions. The shell reloads (~10 s) after every
  // enable/disable, so actions run one at a time; extras wait their turn.
  property var showQueue: []

  // Show (enable) or hide (disable) a game's icon in the top bar.
  function setShown(id, show) {
    var pid = String(id || "")
    if (pid === "") return
    enqueueShowAction(pid, !!show)
    processShowQueue()
  }

  // Hide every visible game icon, or show every hidden one, in one go —
  // the one-click path to a single top-bar entry for all games.
  function setShownAll(show) {
    var want = !!show
    for (var i = 0; i < root.games.length; i++) {
      if (root.games[i].enabled === want) continue
      enqueueShowAction(root.games[i].id, want)
    }
    root.actionError = ""
    processShowQueue()
  }

  function enqueueShowAction(pid, want) {
    var q = root.showQueue.slice()
    for (var k = 0; k < q.length; k++) {
      if (q[k].id === pid) { q[k] = { id: pid, want: want }; root.showQueue = q; return }
    }
    q.push({ id: pid, want: want })
    root.showQueue = q
  }

  function processShowQueue() {
    if (root.busyId !== "" || root.pendingVerify) return
    var q = root.showQueue.slice()
    if (q.length === 0) return
    var next = q.shift()
    root.showQueue = q
    startShowAction(next.id, next.want)
  }

  function startShowAction(pid, want) {
    root.busyId = pid
    root.actionError = ""
    root.pendingVerify = { id: pid, want: want, attempts: 0 }
    var proc = pluginActionComponent.createObject(root, {
      actionCommand: ["python3", root.barVisibilityScriptPath,
        JSON.stringify({ id: pid, action: want ? "show" : "hide" })]
    })
    if (!proc) {
      root.busyId = ""
      root.pendingVerify = null
      root.actionError = "Could not start " + (want ? "show" : "hide")
      processShowQueue()
      return
    }
    proc.running = true
  }

  onSettingsChanged: rescan()

  Timer {
    id: pollTimer
    interval: 60000
    repeat: true
    triggeredOnStart: true
    running: true
    onTriggered: root.rescan()
  }

  Timer {
    id: rescanDelay
    interval: 10000
    repeat: false
    onTriggered: root.rescan()
  }

  // External changes (omaplug, settings, terminal) also rewrite the bar
  // layout, so re-scan shortly after the shell reports a bar config change.
  Timer {
    id: rescanDebounce
    interval: 2000
    repeat: false
    onTriggered: root.rescan()
  }

  Connections {
    target: root.shell
    function onBarConfigChanged() { rescanDebounce.start() }
  }

  // Checks a pending enable/disable against the fresh scan. The shell
  // reloads asynchronously after the CLI returns, so allow a few scans
  // before calling it a failure.
  function verifyPendingAction() {
    var v = root.pendingVerify
    if (!v) return
    var found = null
    for (var i = 0; i < root.games.length; i++) {
      if (root.games[i].id === v.id) { found = root.games[i]; break }
    }
    if (found && found.enabled === v.want) {
      root.pendingVerify = null
      processShowQueue()
      return
    }
    v.attempts = (v.attempts || 0) + 1
    if (v.attempts >= 3) {
      root.actionError = "Could not " + (v.want ? "show " : "hide ")
        + v.id + " — try again"
      root.pendingVerify = null
      processShowQueue()
      return
    }
    root.pendingVerify = v
    rescanDelay.start()
  }

  Component {
    id: pluginActionComponent
    Process {
      property var actionCommand: []
      command: actionCommand
      stdout: StdioCollector { id: actionOut }
      stderr: StdioCollector { id: actionErr }
      onExited: function(exitCode) {
        // The exit code is meaningless here (the CLI's IPC reply times out
        // during the shell reload even on success), so always re-scan and
        // let verifyPendingAction() judge the outcome.
        Qt.callLater(function() {
          root.busyId = ""
          destroy()
          root.rescan()
        })
      }
    }
  }

  Component {
    id: removeActionComponent
    Process {
      property var actionCommand: []
      command: actionCommand
      stdout: StdioCollector { id: removeOut }
      stderr: StdioCollector { id: removeErr }
      onExited: function(exitCode) {
        var errText = removeErr.text
        Qt.callLater(function() {
          root.removeBusyId = ""
          if (exitCode !== 0)
            root.actionError = String(errText || "").trim() || "Could not remove plugin"
          destroy()
          root.rescan()
        })
      }
    }
  }

  Component {
    id: scanComponent
    Process {
      property string payload: "{}"
      command: ["python3", root.scriptPath, payload]
      stdout: StdioCollector { id: scanOut }
      stderr: StdioCollector { id: scanErr }
      onExited: function(exitCode) {
        // Read collectors on the next tick; they flush on stream end.
        var outText = scanOut.text
        var errText = scanErr.text
        var cb = function() {
          root.scanning = false
          if (exitCode !== 0) {
            root.error = String(errText || "").trim() || "Game scan failed"
            destroy()
            return
          }
          try {
            var data = JSON.parse(outText)
            var fresh = Array.isArray(data.games) ? data.games : []
            // `omarchy plugin list` can fail while the shell is reloading;
            // when the scan could not determine enabled states, keep the
            // previous ones instead of flashing every row.
            if (data.enabledKnown === false && root.games.length > 0) {
              var oldById = {}
              for (var o = 0; o < root.games.length; o++)
                oldById[root.games[o].id] = root.games[o].enabled
              for (var n = 0; n < fresh.length; n++) {
                if (oldById.hasOwnProperty(fresh[n].id))
                  fresh[n].enabled = oldById[fresh[n].id]
              }
            }
            root.games = fresh
            root.error = ""
            root.lastScan = new Date().toLocaleTimeString()
            root.verifyPendingAction()
          } catch (e) {
            root.error = "Could not read game list"
          }
          destroy()
        }
        Qt.callLater(cb)
      }
    }
  }

  Component.onCompleted: rescan()
}
