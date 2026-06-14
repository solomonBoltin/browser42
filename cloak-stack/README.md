# CloakBrowser → Playwright MCP + Live View

One stealth Chromium, two drivers: an **AI agent** drives it over the Playwright
MCP, and **you** watch (and take over) the same browser in your web browser.

```
  AI agent ──MCP/HTTP──► mcp ──CDP :9222──► stealth Chromium (headed on Xvfb)
  you  ─────VNC over WS──────────────────►  ▲
                          Caddy is the only published port: TLS + auth + routing
```

## Run it

```bash
docker compose up -d --build
```

That's it — works the same locally and on a VPS.

- **Live view:** open the URL below `/view/` → log in → noVNC password (`VNC_PASSWORD`).
- **MCP:** point your client at the URL below `/mcp` with the same login.

| Where | `SITE_ADDRESS` in `.env` | URLs |
| ----- | ------------------------ | ---- |
| Local | `http://localhost` (default) | `http://localhost/view/` · `http://localhost/mcp` |
| VPS   | `your.domain` (bare, DNS → VPS) | `https://your.domain/view/` · `https://your.domain/mcp` |

Default local login is **admin / admin**. On a VPS, edit `.env`: set `SITE_ADDRESS`
to your domain (Caddy fetches a Let's Encrypt cert automatically), pick a strong
`VNC_PASSWORD`, and replace `BASIC_AUTH_HASH` (double every `$` → `$$`):

```bash
docker run --rm caddy:2-alpine caddy hash-password --plaintext 'YOUR_PASSWORD'
```

MCP client config (add `Authorization: Basic <base64 user:pass>` for the VPS):

```json
{ "mcpServers": { "cloak": { "url": "http://localhost/mcp" } } }
```

## Files

| File | Purpose |
| ---- | ------- |
| `docker-compose.yml` | Wires browser + MCP + Caddy together |
| `Dockerfile.browser` | CloakBrowser + Xvfb/x11vnc/noVNC/fluxbox |
| `start-browser.sh`   | Boots the display, VNC bridge, and `cloakserve` (CDP) |
| `caddy/Caddyfile`    | One entry point: routing + TLS + basic-auth |
| `.env`               | Config (ready for local; edit for VPS) |

## Notes

- **Connect, don't launch.** The MCP attaches to the *existing* browser over CDP,
  so the agent and you share the same Chromium. `cloakserve` is CloakBrowser's
  built-in CDP server mode.
- **Headed on Xvfb.** Stealth is stronger headed. `start-browser.sh` forces
  `--ozone-platform=x11` (this Chromium defaults to offscreen rendering) so the
  window actually paints to the display the live view streams.
- **Persistent logins.** The `cloakprofile` volume (`/profile`) survives restarts.
- **Security (VPS).** CDP/VNC/MCP are never published — only Caddy's 80/443 are.
  Use strong credentials and a residential proxy (`CLOAK_EXTRA_ARGS`); datacenter
  IPs get blocked on reputation regardless of fingerprint.
