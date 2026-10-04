# Changelog

What's new in each Brushfall release, newest first. The same notes appear in your server's Studio Desk under **Overview → What's new in Brushfall**.

Brushfall is in **early access**. Every release is a preview, so things can change between versions. See [PREVIEW.md](PREVIEW.md).

Downloads and Docker tags for every version: <https://github.com/Twelve47Studios/brushfall_release/releases>

## [Unreleased]

These are on the way and will be listed under a version number when they ship.

### Hosting
- A ready-to-run Docker image (`ghcr.io/twelve47studios/brushfall`) for 64-bit PCs, Macs and Raspberry Pi 4/5, plus a `docker-compose.yml` with optional add-ons for HTTPS (Caddy), Cloudflare Tunnel and Tailscale.
- Downloadable server folders for people who'd rather not use Docker (needs Node.js 24), with a `SHA256SUMS.txt` to check each download.
- The `brushfall` host command: `init`, `start`, `doctor`, `status`, `admin create`, `admin promote`, `invite create`, `backup`, `backups`, `restore`, `update`, `reports` and more.
- The **Studio Desk** admin panel at `/admin`: an overview, the painting queue (Hang It / Send Back), hung paintings (put an earlier version back, or reset to the original art), players and roles, approvals, invite links with QR codes, families, messages to everyone, backups, settings and a safety checklist.
- **What's new in Brushfall** in the Studio Desk shows these notes.
- **Report a Problem** in the game: reports land in your own Studio Desk inbox, with optional phone (ntfy), Discord, Slack or email pings. Admins can choose to forward a bug to the Brushfall project after reviewing exactly what would be shared. Reports about other players never leave your server.
- Gentle, optional "Support Brushfall" links for the project and for the host. They never unlock anything.

### Families
- Grown-ups can make or link their kids' accounts and, per child, choose chat (Open, Family filter, Quick phrases, Off), daily play time, quiet hours, party invites (family only or anyone), "Ask a grown-up before painting" and **Safe Paths**.
- **Safe Paths** keeps younger heroes out of areas that are much too hard unless a family grown-up is with them in their party.

### In the world
- **The Puddle Monarch**, a world boss in the starting area that the whole server takes on together, with shared credit and loot.
- Ability animations and effects for every ability, and heroes that turn to face what they're fighting.
- A paper-and-paint sound palette with gentle zone music and its own volume slider.
- "Read to me" for younger players, quest beacons, and an automatic paint trail to help kids find their way.

## [0.1.0] - 2026-10-02

### Added
- The first playable foundation of Brushfall: The Unfinished World.
