# Deskflow (software KVM) — fleet notes

Open-source KVM (keyboard/video/mouse sharing over LAN), Barrier/Synergy lineage.
Barrier is dead (2022), Input Leap archived (07/2026) — **Deskflow is the maintained
upstream** (community project, Synergy 4 builds on it). v1.27.0, ~15k stars.
https://github.com/deskflow/deskflow

## Fleet install
Run `scripts/deskflow/install_deskflow.sh` on any Ubuntu/Debian box:
- noble (24.04): flatpak bundle (no native deb for noble)
- plucky/questing/25.04+ & Debian trixie+: native .deb
- Windows: `winget install Deskflow.Deskflow` or the win-x64.msi from releases

This box (oracle, aarch64): installed via aarch64 flatpak, system-wide.

## Roles
- **server** = machine with the physical keyboard/mouse. Runs the config map.
- **client** = all others; point at the server IP, TCP **24800** (open it in the
  firewall on the server).

## Config
- Server conf: `~/.config/Deskflow/deskflow-server.conf` (Barrier-style screens/links
  syntax). Fleet template: `~/env/config/deskflow/deskflow-server.conf.template` —
  edit screen names to the exact hostnames.
- GUI settings: `~/.config/Deskflow/deskflow.ini`
- Windows config dir: `%APPDATA%\Deskflow`

## Security
Enable TLS in the GUI (Settings → TLS); fingerprints must match on both sides.
LAN-only by design — don't expose 24800 to the internet. ZeroTier works fine
(share over the 10.147.17.x addresses).

## Wayland
Deskflow has Wayland support (libei on GNOME/KDE). Barrier never did. If a Wayland
machine misbehaves, `lan-mouse` (Rust, wayland-first) is the per-machine fallback.

## Checklist for a new pair
1. `install_deskflow.sh` on the Linux box; MSI on Windows
2. open 24800/tcp on the server
3. copy + edit the conf template (screen names = hostnames)
4. server: GUI → Server mode → start; clients: Client mode → server IP
5. verify TLS fingerprints match, test edge-switch both directions
