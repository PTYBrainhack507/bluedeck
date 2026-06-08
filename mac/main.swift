// BlueDeck — daemon de control remoto por Bluetooth LE para macOS
// El teléfono (Chrome / Web Bluetooth) se conecta a este peripheral BLE y le
// escribe comandos de texto; aquí se inyectan como eventos reales de teclado/ratón
// (CGEvent), ideal para manejar Kodi y la Mac en general sin tocar la red.
//
// Protocolo (una línea de texto por escritura BLE):
//   KEY <name> [mods]        p.ej. "KEY return", "KEY space", "KEY left"
//   HOTKEY <a+b+c>           p.ej. "HOTKEY cmd+space", "HOTKEY cmd+tab"
//   TYPE <texto...>          escribe el resto de la línea literalmente
//   MOVE <dx> <dy>           movimiento relativo del cursor (trackpad)
//   CLICK <l|r|m> [2]        click; 2 = doble click
//   MDOWN <l|r> / MUP <l|r>  botón abajo/arriba (arrastrar)
//   SCROLL <dy> [dx]         scroll
//   MEDIA <playpause|next|prev|stop>
//   VOL <up|down|mute>
//   APP <NombreApp>          open -a NombreApp  (p.ej. "APP Kodi")
//   SYS <sleep|lock|displaysleep|mission|launchpad|desktop|spotlight>
//   PING                     keepalive (responde "OK" por la característica TX)

import Cocoa
import CoreBluetooth
import CoreGraphics
import ApplicationServices

// MARK: - UUIDs (Nordic UART Service, ampliamente compatible con Web Bluetooth)
let kServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
let kRxUUID      = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // teléfono -> Mac (write)
let kTxUUID      = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // Mac -> teléfono (notify)
let kDeviceName  = "BlueDeck"

// MARK: - Mapa de teclas (nombre -> virtual keycode de macOS)
let keyMap: [String: CGKeyCode] = [
    "return": 36, "enter": 36, "kpenter": 76,
    "tab": 48, "space": 49, "spacebar": 49,
    "delete": 51, "backspace": 51, "forwarddelete": 117, "fdelete": 117,
    "escape": 53, "esc": 53,
    "up": 126, "down": 125, "left": 123, "right": 124,
    "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
    "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    // letras
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8,
    "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
    "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    // dígitos
    "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,
    // símbolos útiles
    "minus": 27, "equal": 24, "plus": 24, "leftbracket": 33, "rightbracket": 30,
    "semicolon": 41, "quote": 39, "comma": 43, "period": 47, "slash": 44,
    "backslash": 42, "grave": 50, "tilde": 50,
]

func flags(from tokens: [String]) -> CGEventFlags {
    var f: CGEventFlags = []
    for t in tokens {
        switch t.lowercased() {
        case "cmd", "command", "meta", "super", "win": f.insert(.maskCommand)
        case "shift": f.insert(.maskShift)
        case "ctrl", "control": f.insert(.maskControl)
        case "alt", "opt", "option": f.insert(.maskAlternate)
        case "fn", "function": f.insert(.maskSecondaryFn)
        default: break
        }
    }
    return f
}

// MARK: - Inyección de eventos
final class Injector {
    static let shared = Injector()
    private let src = CGEventSource(stateID: .hidSystemState)
    private var dragging = false

    func key(_ name: String, mods: [String] = []) {
        guard let code = keyMap[name.lowercased()] else { return }
        let f = flags(from: mods)
        post(code, down: true, flags: f)
        post(code, down: false, flags: f)
    }

    func hotkey(_ combo: String) {
        // "cmd+shift+a" -> mods = [cmd,shift], key = a
        var parts = combo.split(separator: "+").map { String($0) }
        guard let last = parts.popLast() else { return }
        key(last, mods: parts)
    }

    func type(_ text: String) {
        for ch in text {
            var u16 = Array(String(ch).utf16)
            let d = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            d?.keyboardSetUnicodeString(stringLength: u16.count, unicodeString: &u16)
            d?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            up?.keyboardSetUnicodeString(stringLength: u16.count, unicodeString: &u16)
            up?.post(tap: .cghidEventTap)
        }
    }

    func move(dx: Double, dy: Double) {
        let cur = CGEvent(source: nil)?.location ?? .zero
        let p = clamp(CGPoint(x: cur.x + dx, y: cur.y + dy))
        let type: CGEventType = dragging ? .leftMouseDragged : .mouseMoved
        let e = CGEvent(mouseEventSource: src, mouseType: type,
                        mouseCursorPosition: p, mouseButton: .left)
        e?.post(tap: .cghidEventTap)
    }

    func click(_ which: String, double: Bool = false) {
        let (btn, downT, upT) = buttonTypes(which)
        let p = CGEvent(source: nil)?.location ?? .zero
        let d = CGEvent(mouseEventSource: src, mouseType: downT, mouseCursorPosition: p, mouseButton: btn)
        let u = CGEvent(mouseEventSource: src, mouseType: upT, mouseCursorPosition: p, mouseButton: btn)
        if double {
            d?.setIntegerValueField(.mouseEventClickState, value: 2)
            u?.setIntegerValueField(.mouseEventClickState, value: 2)
        }
        d?.post(tap: .cghidEventTap)
        u?.post(tap: .cghidEventTap)
    }

    func mouseDown(_ which: String) {
        let (btn, downT, _) = buttonTypes(which)
        if btn == .left { dragging = true }
        let p = CGEvent(source: nil)?.location ?? .zero
        CGEvent(mouseEventSource: src, mouseType: downT, mouseCursorPosition: p, mouseButton: btn)?
            .post(tap: .cghidEventTap)
    }

    func mouseUp(_ which: String) {
        let (btn, _, upT) = buttonTypes(which)
        if btn == .left { dragging = false }
        let p = CGEvent(source: nil)?.location ?? .zero
        CGEvent(mouseEventSource: src, mouseType: upT, mouseCursorPosition: p, mouseButton: btn)?
            .post(tap: .cghidEventTap)
    }

    func scroll(dy: Int32, dx: Int32 = 0) {
        CGEvent(scrollWheelEvent2Source: src, units: .pixel,
                wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    func media(_ name: String) {
        let codes: [String: Int32] = [
            "playpause": 16, "play": 16, "pause": 16,
            "next": 17, "prev": 18, "previous": 18,
            "fast": 19, "rewind": 20, "stop": 16,
        ]
        guard let k = codes[name.lowercased()] else { return }
        auxKey(k)
    }

    func volume(_ name: String) {
        switch name.lowercased() {
        case "up":   runAS("set volume output volume (((output volume of (get volume settings)) + 8))")
        case "down": runAS("set volume output volume (((output volume of (get volume settings)) - 8))")
        case "mute": runAS("set volume output muted (not (output muted of (get volume settings)))")
        default: break
        }
    }

    func app(_ name: String) {
        let p = Process()
        p.launchPath = "/usr/bin/open"
        p.arguments = ["-a", name]
        try? p.run()
    }

    func sys(_ what: String) {
        switch what.lowercased() {
        case "sleep":        runAS("tell application \"System Events\" to sleep")
        case "lock":         hotkey("cmd+ctrl+q")
        case "displaysleep": shell("/usr/bin/pmset", ["displaysleepnow"])
        case "mission":      key("up", mods: ["ctrl"])
        case "launchpad":    app("Launchpad")
        case "desktop":      key("f11", mods: ["fn"])
        case "spotlight":    hotkey("cmd+space")
        default: break
        }
    }

    // MARK: helpers
    private func post(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
    }

    private func buttonTypes(_ which: String) -> (CGMouseButton, CGEventType, CGEventType) {
        switch which.lowercased() {
        case "r", "right": return (.right, .rightMouseDown, .rightMouseUp)
        case "m", "middle": return (.center, .otherMouseDown, .otherMouseUp)
        default: return (.left, .leftMouseDown, .leftMouseUp)
        }
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        var rect = CGDisplayBounds(CGMainDisplayID())
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        if count > 0 {
            var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
            CGGetActiveDisplayList(count, &ids, &count)
            for id in ids { rect = rect.union(CGDisplayBounds(id)) }
        }
        let x = min(max(p.x, rect.minX), rect.maxX - 1)
        let y = min(max(p.y, rect.minY), rect.maxY - 1)
        return CGPoint(x: x, y: y)
    }

    private func auxKey(_ key: Int32) {
        func doKey(_ down: Bool) {
            let mask = down ? 0xA00 : 0xB00
            let data1 = Int((key << 16) | Int32(mask))
            let ev = NSEvent.otherEvent(with: .systemDefined,
                                        location: .zero,
                                        modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(mask)),
                                        timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: 0, context: nil,
                                        subtype: 8, data1: data1, data2: -1)
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
        doKey(true); doKey(false)
    }

    private func runAS(_ s: String) {
        var err: NSDictionary?
        NSAppleScript(source: s)?.executeAndReturnError(&err)
    }

    private func shell(_ path: String, _ args: [String]) {
        let p = Process(); p.launchPath = path; p.arguments = args
        try? p.run()
    }
}

// MARK: - Parser de comandos
func execute(_ line: String) {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    // separa el primer token (tipo) del resto
    let firstSpace = trimmed.firstIndex(of: " ")
    let cmd = String(firstSpace == nil ? Substring(trimmed) : trimmed[..<firstSpace!]).uppercased()
    let rest = firstSpace == nil ? "" : String(trimmed[trimmed.index(after: firstSpace!)...])
    let args = rest.split(separator: " ").map { String($0) }
    let inj = Injector.shared

    switch cmd {
    case "KEY":    if let k = args.first { inj.key(k, mods: Array(args.dropFirst())) }
    case "HOTKEY": if let c = args.first { inj.hotkey(c) }
    case "TYPE":   inj.type(rest)
    case "MOVE":   if args.count >= 2, let dx = Double(args[0]), let dy = Double(args[1]) { inj.move(dx: dx, dy: dy) }
    case "CLICK":  inj.click(args.first ?? "l", double: args.count > 1 && args[1] == "2")
    case "MDOWN":  inj.mouseDown(args.first ?? "l")
    case "MUP":    inj.mouseUp(args.first ?? "l")
    case "SCROLL": if let dy = Int32(args.first ?? "0") { inj.scroll(dy: dy, dx: Int32(args.count > 1 ? args[1] : "0") ?? 0) }
    case "MEDIA":  if let m = args.first { inj.media(m) }
    case "VOL":    if let v = args.first { inj.volume(v) }
    case "APP":    if !rest.isEmpty { inj.app(rest) }
    case "SYS":    if let s = args.first { inj.sys(s) }
    case "PING":   break
    default:       NSLog("BlueDeck: comando desconocido: \(cmd)")
    }
}

// MARK: - BLE Peripheral
final class BLEController: NSObject, CBPeripheralManagerDelegate {
    private var manager: CBPeripheralManager!
    private var txChar: CBMutableCharacteristic!
    private var subscribers: [CBCentral] = []

    override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: nil)
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            NSLog("BlueDeck: Bluetooth listo, publicando servicio…")
            setupService()
        case .poweredOff:
            NSLog("BlueDeck: Bluetooth apagado.")
        case .unauthorized:
            NSLog("BlueDeck: ⚠️ Sin permiso de Bluetooth. Concédelo en Ajustes › Privacidad y seguridad › Bluetooth.")
        default:
            NSLog("BlueDeck: estado Bluetooth = \(peripheral.state.rawValue)")
        }
    }

    private func setupService() {
        let rx = CBMutableCharacteristic(
            type: kRxUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable])
        txChar = CBMutableCharacteristic(
            type: kTxUUID,
            properties: [.notify],
            value: nil,
            permissions: [.readable])
        let service = CBMutableService(type: kServiceUUID, primary: true)
        service.characteristics = [rx, txChar]
        manager.add(service)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error { NSLog("BlueDeck: error al añadir servicio: \(error)"); return }
        manager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [kServiceUUID],
            CBAdvertisementDataLocalNameKey: kDeviceName,
        ])
        NSLog("BlueDeck: ✅ anunciando como '\(kDeviceName)'. Listo para conectar desde el teléfono.")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for req in requests {
            if let data = req.value, let line = String(data: data, encoding: .utf8) {
                // pueden venir varios comandos en una escritura, separados por \n
                for sub in line.split(separator: "\n", omittingEmptySubsequences: true) {
                    execute(String(sub))
                }
            }
        }
        if let first = requests.first {
            manager.respond(to: first, withResult: .success)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        subscribers.append(central)
        NSLog("BlueDeck: 📱 teléfono conectado y suscrito.")
        notify("HELLO BlueDeck")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribers.removeAll { $0.identifier == central.identifier }
        NSLog("BlueDeck: teléfono desconectado.")
    }

    private func notify(_ s: String) {
        guard let tx = txChar, let data = s.data(using: .utf8) else { return }
        manager.updateValue(data, for: tx, onSubscribedCentrals: nil)
    }
}

// MARK: - Permiso de Accesibilidad (necesario para inyectar eventos)
func ensureAccessibility() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let opts = [key: true] as CFDictionary
    if AXIsProcessTrustedWithOptions(opts) {
        NSLog("BlueDeck: ✅ permiso de Accesibilidad concedido.")
    } else {
        NSLog("BlueDeck: ⚠️ Falta permiso de Accesibilidad. Actívalo en Ajustes › Privacidad y seguridad › Accesibilidad y reinicia BlueDeck.")
    }
}

// MARK: - main
let app = NSApplication.shared

final class AppDelegate: NSObject, NSApplicationDelegate {
    var ble: BLEController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("BlueDeck: iniciando…")
        ensureAccessibility()
        ble = BLEController()
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // sin icono en el Dock
app.run()
