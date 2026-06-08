# BlueDeck 🔵

Controla tu **Mac (y Kodi)** desde tu **Android** por **Bluetooth LE**, sin usar la red.
Pensado para hoteles / redes con aislamiento de clientes donde no puedes usar control remoto por WiFi/HTTP.

La conexión es **directa teléfono ↔ Mac por Bluetooth**. No pasa por internet ni por la red del hotel.

```
┌─────────────┐   Bluetooth LE (GATT)   ┌────────────────────────┐
│  Android    │ ──────────────────────▶ │  Mac: daemon BlueDeck  │
│  Chrome PWA │   comandos de texto      │  (inyecta teclado/ratón│
│ (control)   │ ◀────────────────────── │   con CGEvent)         │
└─────────────┘      notificaciones      └────────────────────────┘
```

- **Mac**: un daemon en Swift que se anuncia como periférico BLE (servicio Nordic UART) y
  traduce los comandos a eventos reales de teclado/ratón (`CGEvent`), volumen, lanzar apps, etc.
- **Android**: una PWA (Chrome + Web Bluetooth) con pestañas **Kodi / Trackpad / Teclado / Apps**.
  No requiere instalar el toolchain de Android: es una página web que se instala como app y
  funciona **offline** una vez cargada.

---

## 1) Instalar en la Mac (una vez)

```bash
cd ~/Documents/bluedeck/mac
./install.sh
```

Esto:
1. Copia `BlueDeck.app` a `~/Applications`.
2. Lo arranca y lo deja iniciándose solo en cada login (LaunchAgent).
3. Abre **Ajustes › Privacidad y seguridad**.

**Concede 2 permisos a `BlueDeck` (una sola vez):**
- **Accesibilidad** → para mover el ratón y escribir.
- **Bluetooth** → para conectarse con el teléfono (el aviso aparece al arrancar; actívalo en
  Ajustes › Privacidad y seguridad › Bluetooth).

> Ver logs en vivo: `tail -f /tmp/bluedeck.log`
> Debe aparecer: `✅ anunciando como 'BlueDeck'. Listo para conectar desde el teléfono.`

## 2) Abrir el control en el teléfono

1. En **Chrome de Android**, abre: **https://ptybrainhack507.github.io/bluedeck/**
2. Menú de Chrome → **Añadir a pantalla de inicio** / **Instalar app**.
3. Ábrela, pulsa **Conectar** y elige **BlueDeck** en la lista de Bluetooth.

> **Hotel sin internet:** carga la PWA **una vez** con datos móviles (o antes de viajar).
> Al instalarla queda cacheada y luego funciona **100% offline**; el control va por Bluetooth.

⚠️ Web Bluetooth **solo funciona en Chrome/Edge de Android** (no en Safari/iOS, no en Firefox).
Necesita **HTTPS** (por eso se publica en una URL segura; la conexión Bluetooth en sí es local).

---

## Uso

| Pestaña | Para qué |
|---|---|
| **🎬 Kodi** | D-pad (navegar), OK, Atrás, Menú, Play/Pausa, Stop, ±10s, anterior/siguiente, volumen, subtítulos, info, pantalla completa. |
| **🖱️ Trackpad** | Desliza = mover cursor · toca = clic · 2 dedos = clic derecho · desliza 2 dedos = scroll · botón Arrastrar. |
| **⌨️ Teclado** | Escribe y se envía en vivo a la Mac; teclas Enter/Esc/Tab/flechas; multimedia del sistema. |
| **🚀 Apps** | Spotlight, cambiar app, Mission Control, lanzar Kodi/Safari/…; bloquear, suspender. |

### Atajos de Kodi (referencia)
Las teclas que envía la pestaña Kodi son las estándar de Kodi: flechas, `Enter` (OK),
`Backspace` (atrás), `Espacio` (play/pausa), `x` (stop), `r`/`f` (rebobinar/avanzar),
`,`/`.` (anterior/siguiente), `c` (menú), `i` (info), `t` (subtítulos), `\` (pantalla completa).

---

## Cómo está hecho / extender

**Protocolo** (una línea de texto por escritura BLE a la característica RX):

| Comando | Ejemplo | Acción |
|---|---|---|
| `KEY <nombre> [mods]` | `KEY left` · `KEY a shift` | Pulsa una tecla |
| `HOTKEY <a+b+c>` | `HOTKEY cmd+space` | Combinación |
| `TYPE <texto>` | `TYPE hola mundo` | Escribe texto |
| `MOVE <dx> <dy>` | `MOVE 12 -4` | Mueve el cursor (relativo) |
| `CLICK <l\|r\|m> [2]` | `CLICK r` · `CLICK l 2` | Clic (2 = doble) |
| `MDOWN/MUP <l\|r>` | `MDOWN l` | Arrastrar |
| `SCROLL <dy> [dx]` | `SCROLL -30` | Scroll |
| `MEDIA <playpause\|next\|prev>` | `MEDIA playpause` | Teclas multimedia del sistema |
| `VOL <up\|down\|mute>` | `VOL up` | Volumen del sistema |
| `APP <Nombre>` | `APP Kodi` | `open -a Nombre` |
| `SYS <sleep\|lock\|displaysleep\|mission\|launchpad\|spotlight>` | `SYS lock` | Sistema |

UUIDs (Nordic UART Service): servicio `6E400001-…`, RX `6E400002-…`, TX `6E400003-…`.

**Archivos:**
```
mac/   main.swift · Info.plist · build.sh · install.sh · uninstall.sh · run.sh
web/   index.html · manifest.webmanifest · sw.js · icon-*.png · gen-icons.swift · serve.py
```

Recompilar el daemon: `cd mac && ./build.sh` (luego `./install.sh` de nuevo).

---

## Solución de problemas

- **El teléfono no encuentra BlueDeck** → revisa `tail -f /tmp/bluedeck.log`: debe decir
  «anunciando como 'BlueDeck'». Si dice *unauthorized*, falta el permiso de **Bluetooth**.
- **Conecta pero no controla nada** → falta el permiso de **Accesibilidad**. Actívalo y
  vuelve a probar (no hace falta reiniciar).
- **«Web Bluetooth no soportado»** → usa **Chrome** (no Safari) en Android.
- **Se desconecta** → la PWA reintenta sola; si no, pulsa Conectar otra vez.

## Desinstalar
```bash
cd ~/Documents/bluedeck/mac && ./uninstall.sh
```
