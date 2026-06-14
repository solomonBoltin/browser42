#!/usr/bin/env bash
# Boots a single headed stealth Chromium that BOTH the AI agent (over CDP)
# and the human (over noVNC) attach to. One browser, two drivers.
set -euo pipefail

SCREEN_W="${SCREEN_WIDTH:-1920}"
SCREEN_H="${SCREEN_HEIGHT:-1080}"
DISPLAY_NUM="${DISPLAY_NUM:-99}"
export DISPLAY=":${DISPLAY_NUM}"

# 1. Virtual framebuffer — the "monitor" Chromium renders onto.
Xvfb "$DISPLAY" -screen 0 "${SCREEN_W}x${SCREEN_H}x24" -ac -nolisten tcp &
# Wait for the X socket before anything tries to draw to it.
for i in $(seq 1 50); do
    [ -e "/tmp/.X11-unix/X${DISPLAY_NUM}" ] && break
    sleep 0.1
done

# 2. Window manager — without it, popups/dialogs misbehave and look bot-like.
fluxbox >/dev/null 2>&1 &

# 2b. Maximize each browser window once it appears, so the live view fills the
#     whole screen (no empty borders) instead of a small window in the corner.
( seen=""
  while :; do
    for w in $(wmctrl -l 2>/dev/null | awk '{print $1}' || true); do
      case " $seen " in
        *" $w "*) ;;
        *) wmctrl -i -r "$w" -b add,maximized_vert,maximized_horz 2>/dev/null || true
           seen="$seen $w" ;;
      esac
    done
    sleep 1
  done ) &

# 3. VNC server scraping the display. Bound to localhost only; Caddy fronts it.
#    A password is required — generated from VNC_PASSWORD so the view isn't open.
mkdir -p /root/.vnc
x11vnc -storepasswd "${VNC_PASSWORD:-changeme}" /root/.vnc/passwd >/dev/null 2>&1
x11vnc -display "$DISPLAY" -rfbauth /root/.vnc/passwd \
       -forever -shared -localhost -rfbport 5900 -nopw -quiet &

# 4. websockify serves the noVNC static client AND bridges WS->VNC on one port.
websockify --web=/usr/share/novnc 6080 localhost:5900 >/dev/null 2>&1 &

# 4b. Tuned landing page for /view/: auto-connect, scale-to-fit (centered) and
#     auto-reconnect, with the VNC password prefilled — so opening the view is a
#     single click with no off-center/scrollbar issues. (We replace index.html
#     rather than symlink it, so writing here never clobbers vnc.html.)
rm -f /usr/share/novnc/index.html
cat > /usr/share/novnc/index.html <<HTML
<!doctype html><html><head><meta charset="utf-8"><title>Live view</title>
<meta http-equiv="refresh" content="0; url=vnc.html?autoconnect=true&reconnect=true&resize=scale&quality=8&compression=2&password=${VNC_PASSWORD:-changeme}">
</head><body style="margin:0;background:#111"></body></html>
HTML

# 5. The stealth browser itself. `cloakserve` launches CloakBrowser's patched
#    Chromium with all 58 fingerprint patches and exposes CDP on :9222.
#    0.0.0.0 lets the sibling MCP container reach CDP over the compose network.
#
#    Rendering to Xvfb (so the human sees it over noVNC) is the subtle part:
#    - Do NOT pass `--headless=false`. cloakserve forwards that flag to Chromium
#      verbatim, and Chromium 146 treats the mere *presence* of `--headless` as
#      headless-on (the `false` value is ignored) — so it renders offscreen and
#      the live view stays blank.
#    - Instead force `--ozone-platform=x11`. This build's compiled-in default
#      ozone backend is `headless` (offscreen); x11 makes Chromium map a real
#      window onto Xvfb :99 — exactly what x11vnc/noVNC stream out.
#    Stealth is unaffected: the fingerprint patches (not `--headless`) hide
#    automation, and the UA already reports real "Chrome", not HeadlessChrome.
exec cloakserve \
    --host=0.0.0.0 \
    --port=9222 \
    --ozone-platform=x11 \
    --data-dir=/profile \
    ${CLOAK_EXTRA_ARGS:-}
