import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "logan.mercado"
  ipcTarget: "logan.mercado"
  manageIpc: false

  readonly property string helperPath: decodeURIComponent(Qt.resolvedUrl("quotes.py").toString().replace(/^file:\/\//, ""))
  readonly property string symbols: String(setting("symbols", "USDBRL=X, ^BVSP, PETR4, VALE3, ITUB4"))
  readonly property string barSymbol: normalize(String(setting("barSymbol", "USDBRL=X")))
  readonly property int refreshIntervalSec: Math.max(60, parseInt(String(setting("refreshIntervalSec", 120)), 10) || 120)

  // Quote state, filled by quotes.py
  property var quotes: []
  property double fetchedAt: 0
  property string lastError: ""
  readonly property var barQuote: findQuote(barSymbol)

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color rising: Qt.tint(foreground, Qt.rgba(0.25, 0.8, 0.35, 0.6))
  readonly property color falling: urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string marketGlyph: "󰄨"
  readonly property var ptBR: Qt.locale("pt_BR")

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ── Actions ────────────────────────────────────────────────────────────

  function refresh(force) {
    if (quotesProcess.running) return
    var list = symbols.split(",").map(function(s) { return s.trim() }).filter(function(s) { return s !== "" })
    if (list.map(normalize).indexOf(barSymbol) === -1) list.unshift(barSymbol)
    quotesProcess.command = ["python3", "-I", helperPath, list.join(","), force ? "0" : "60"]
    quotesProcess.running = true
  }

  function applyQuotes(raw) {
    var s
    try { s = JSON.parse(String(raw || "").trim()) } catch (e) { lastError = "Falha ao ler as cotações"; return }
    if (!Array.isArray(s.quotes)) { lastError = "Falha ao ler as cotações"; return }
    quotes = s.quotes
    fetchedAt = Number(s.fetchedAt || 0)
    lastError = s.ok ? "" : "Sem conexão com o Yahoo Finance"
  }

  function openQuote(quote) {
    if (!quote || !quote.symbol) return
    Qt.openUrlExternally("https://finance.yahoo.com/quote/" + encodeURIComponent(quote.symbol))
    close()
  }

  // Mirrors quotes.py: bare B3 tickers get ".SA".
  function normalize(symbol) {
    var s = String(symbol || "").trim().toUpperCase()
    return /^[A-Z]{4}\d{1,2}$/.test(s) ? s + ".SA" : s
  }

  function findQuote(symbol) {
    for (var i = 0; i < quotes.length; i++) if (quotes[i].symbol === symbol) return quotes[i]
    return null
  }

  // ── Formatting ─────────────────────────────────────────────────────────

  function decimalsFor(quote) {
    if (quote.type === "INDEX") return 0
    if (quote.type === "CURRENCY" && Math.abs(quote.price) < 10) return 4
    return 2
  }

  function formatPrice(quote) {
    if (!quote || !quote.ok) return "—"
    var value = Number(quote.price).toLocaleString(ptBR, "f", decimalsFor(quote))
    if (quote.type === "INDEX") return value + " pts"
    if (quote.currency === "BRL") return "R$ " + value
    if (quote.currency === "USD") return "US$ " + value
    return value + " " + quote.currency
  }

  function formatPercent(quote) {
    if (!quote || !quote.ok || quote.changePercent === null || quote.changePercent === undefined) return ""
    var p = Number(quote.changePercent)
    return (p > 0 ? "▲ " : (p < 0 ? "▼ " : "")) + Math.abs(p).toLocaleString(ptBR, "f", 2) + "%"
  }

  function changeColor(quote) {
    if (!quote || !quote.ok || !quote.changePercent) return dim
    return quote.changePercent > 0 ? rising : falling
  }

  function barText() {
    var q = barQuote
    if (!q || !q.ok) return marketGlyph
    var value = Number(q.price).toLocaleString(ptBR, "f", q.type === "INDEX" ? 0 : 2)
    var p = Number(q.changePercent || 0)
    return marketGlyph + " " + value + " " + (p > 0 ? "▲" : (p < 0 ? "▼" : "•"))
  }

  function updatedText() {
    if (fetchedAt <= 0) return "Carregando…"
    var d = new Date(fetchedAt * 1000)
    return "Atualizado às " + d.toLocaleTimeString(ptBR, "HH:mm")
  }

  function marketTime(quote) {
    if (!quote || !quote.time) return ""
    var d = new Date(quote.time * 1000)
    var today = new Date()
    var sameDay = d.toDateString() === today.toDateString()
    return (sameDay ? "" : d.toLocaleDateString(ptBR, "dd/MM") + " ") + d.toLocaleTimeString(ptBR, "HH:mm")
  }

  onOpenedChanged: if (opened) {
    panelFlick.contentY = 0
    refresh(false)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onSymbolsChanged: refresh(true)

  // ── Processes / timers ─────────────────────────────────────────────────

  Process {
    id: quotesProcess
    running: false
    stdout: StdioCollector { id: quotesOut; waitForEnd: true }
    stderr: StdioCollector { id: quotesErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.applyQuotes(quotesOut.text)
      else root.lastError = String(quotesErr.text || "Falha ao buscar as cotações").trim().slice(-140)
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(true); return "ok" }
  }

  // ── Bar button ─────────────────────────────────────────────────────────

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText()
    horizontalMargin: 8.75
    tooltipText: root.opened || !root.barQuote ? "" : root.barQuote.label + " · " + root.formatPrice(root.barQuote) + "  " + root.formatPercent(root.barQuote)
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.refresh(true)
      else if (buttonCode === Qt.RightButton) root.openQuote(root.barQuote)
      else root.toggle()
    }
  }

  // ── Popup ──────────────────────────────────────────────────────────────

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t.toLowerCase() === "r") root.refresh(true) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "Mercado"
            meta: quotesProcess.running && root.fetchedAt <= 0 ? "Carregando…" : root.updatedText()
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: root.marketGlyph
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Atualizar (r)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                enabled: !quotesProcess.running
                onClicked: root.refresh(true)
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.lastError !== ""
            width: parent.width
            text: root.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator {
            visible: root.quotes.length > 0
            foreground: root.foreground
          }

          Column {
            id: quoteColumn
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              model: root.quotes
              QuoteRow {
                required property var modelData
                width: quoteColumn.width
                quote: modelData
              }
            }
          }
        }
      }
    }
  }

  // ── Components ─────────────────────────────────────────────────────────

  component QuoteRow: CursorSurface {
    id: row
    property var quote: ({})
    readonly property color trend: root.changeColor(quote)

    hasCursor: mouse.containsMouse
    foreground: root.foreground
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openQuote(row.quote)
    }

    RowLayout {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: row.quote.label + (row.quote.stale ? "  󰅐" : "")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: row.quote.ok ? [row.quote.name, root.marketTime(row.quote)].filter(function(s) { return s }).join(" · ") : "Indisponível"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Sparkline {
        visible: row.quote.ok && (row.quote.points || []).length > 1
        series: row.quote.points || []
        prevClose: Number(row.quote.previousClose || 0)
        strokeColor: row.trend
        Layout.preferredWidth: Style.space(56)
        Layout.preferredHeight: Style.space(22)
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        spacing: Style.space(1)
        Layout.alignment: Qt.AlignVCenter

        Text {
          textFormat: Text.PlainText
          Layout.alignment: Qt.AlignRight
          text: root.formatPrice(row.quote)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          textFormat: Text.PlainText
          Layout.alignment: Qt.AlignRight
          text: root.formatPercent(row.quote)
          color: row.trend
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  component Sparkline: Canvas {
    id: spark
    property var series: []
    property real prevClose: 0
    property color strokeColor: root.foreground

    onSeriesChanged: requestPaint()
    onStrokeColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      if (series.length < 2) return
      var lo = Math.min.apply(null, series), hi = Math.max.apply(null, series)
      if (prevClose > 0) { lo = Math.min(lo, prevClose); hi = Math.max(hi, prevClose) }
      var span = hi - lo || 1
      var pad = 1.5
      function y(v) { return pad + (height - pad * 2) * (1 - (v - lo) / span) }

      if (prevClose > 0) {
        ctx.strokeStyle = Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
        ctx.lineWidth = 1
        ctx.setLineDash([2, 2])
        ctx.beginPath()
        ctx.moveTo(0, y(prevClose))
        ctx.lineTo(width, y(prevClose))
        ctx.stroke()
        ctx.setLineDash([])
      }

      ctx.strokeStyle = strokeColor
      ctx.lineWidth = 1.5
      ctx.lineJoin = "round"
      ctx.beginPath()
      for (var i = 0; i < series.length; i++) {
        var x = width * i / (series.length - 1)
        if (i === 0) ctx.moveTo(x, y(series[i]))
        else ctx.lineTo(x, y(series[i]))
      }
      ctx.stroke()
    }
  }
}
