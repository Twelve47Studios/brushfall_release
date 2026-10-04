# Security

Brushfall runs on computers in people's homes, and many of the players are kids. We take security reports seriously and are grateful for them.

## Reporting a vulnerability

**Please don't open a public issue for security problems.** Instead, report it privately in one of these ways:

1. **GitHub private report (preferred):** open the [Security tab](https://github.com/Twelve47Studios/brushfall_release/security) of this repository and click **Report a vulnerability**.
2. **Email:** **brushfallgame@gmail.com** with "Security" in the subject.

Helpful things to include:

- The Brushfall version (shown in the Studio Desk, or run `brushfall status`).
- How you run it (Docker, download, Raspberry Pi, behind a tunnel or proxy...).
- What you found, and the steps to reproduce it.
- What someone could do with it, as far as you know.

Please **never send passwords, invite links, `.admin-token` files, backups or database files**, and don't include other people's personal information.

## What happens next

- We'll reply to say we got your report, usually within a few days. Brushfall is a personal project, so please be patient.
- We'll keep you posted while we work on a fix, and publish it in a new release. The release notes will mention the fix without the details that would help someone misuse it.
- If you'd like, we'll thank you by name in the release notes.

Please give us a reasonable chance to fix the problem before sharing it publicly, and only test against servers you run yourself.

## Supported versions

Brushfall is in early access. Security fixes go into the **newest release only**, so please keep your server updated (see the wiki page [Updating](https://github.com/Twelve47Studios/brushfall_release/wiki/Updating)).

## Keeping your own server safe

The wiki has a checklist for hosts: [Playing From Outside Home → Keeping an internet server safe](https://github.com/Twelve47Studios/brushfall_release/wiki/Playing-From-Outside-Home#keeping-an-internet-server-safe).
