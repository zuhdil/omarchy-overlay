// omarchy-overlay: Omarchy's own power widget, imported rather than copied so
// its fixes keep arriving. Its icon already reads UPower's combined device; only
// the popup's stats come from omarchy-battery-status, which reads the first
// battery alone, so that one command is swapped for battery-combined.
// clonedFrom in manifest.json gives this the built-in's capabilities and routes
// calls made to omarchy.power here.
import QtQuick
import qs.Commons
import qs.Ui
import qs.plugins.panels.power as Omarchy

Omarchy.Panel {
  id: power

  // battery-combined --shell adds a `battery:<name>` line per battery.
  readonly property var batteries: Object.keys(batteryInfo).filter(function(k) {
    return k.indexOf("battery:") === 0
  }).sort().map(function(k) {
    return { name: k.substring(8), value: batteryInfo[k] }
  })

  Component.onCompleted: {
    for (var i = 0; i < data.length; i++) {
      var o = data[i]
      if (o && o.command && o.command[0] === "omarchy-battery-status")
        o.command = ["battery-combined"].concat(Array.prototype.slice.call(o.command, 1))
    }
    // The popup has no slot for extra rows, and reparenting its items stops
    // them rendering, so the section is appended to the column holding
    // "Battery size" (the left half of the stats row) and spans the full row.
    // Not finding it leaves Omarchy's panel as is.
    var left = findSizeColumn(power, [])
    if (left) perBattery.createObject(left, { width: Qt.binding(function() { return left.parent.width }) })
  }

  function findSizeColumn(o, seen) {
    if (!o || seen.indexOf(o) !== -1) return null
    seen.push(o)
    if (o.label === "Battery size") return o.parent
    var kids = [].concat(Array.prototype.slice.call(o.data || []),
                         Array.prototype.slice.call(o.children || []),
                         o.contentItem ? [o.contentItem] : [])
    for (var i = 0; i < kids.length; i++) {
      var found = findSizeColumn(kids[i], seen)
      if (found) return found
    }
    return null
  }

  Component {
    id: perBattery

    Column {
      spacing: Style.space(10)
      visible: power.batteries.length > 1
      // Matches the gap Omarchy's panel puts between its own sections.
      topPadding: Style.space(14) - Style.spacing.labelGap

      PanelSeparator { foreground: power.bar.foreground }

      PanelSectionHeader {
        text: "BATTERIES"
        foreground: power.bar.foreground
        fontFamily: power.bar.fontFamily
      }

      Column {
        width: parent.width
        spacing: Style.spacing.labelGap

        Repeater {
          model: power.batteries

          Item {
            required property var modelData
            width: parent.width
            implicitHeight: Math.max(label.implicitHeight, value.implicitHeight)

            Text {
              id: label
              textFormat: Text.PlainText
              text: modelData.name
              color: power.bar.foreground
              opacity: 0.6
              font.family: power.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              id: value
              anchors.right: parent.right
              textFormat: Text.PlainText
              text: modelData.value
              color: power.bar.foreground
              font.family: power.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }
  }
}
