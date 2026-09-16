# CCC app

Public store app for anyone running their own Crew Command Center. Talk to a team from a phone the way Grok Bot talks to a local machine: pick a computer, pick a bot, talk.

The phone never holds Telegram tokens or engine credentials. Each `ccc listen` instance keeps an outbound encrypted connection to a public hub. The hub is a dumb pipe (Tailscale DERP, not a VPN mesh): it routes NaCl boxes between a machine and a paired device and cannot read them.

Pairing is TOFU. `ccc pair` prints a URI whose query carries the instance public key; the phone encrypts its identity to that key. The hub only forwards.

## Surfaces

- Machine list (several ccc instances: Mac, VPS, …)
- Pair a machine (paste URI from `ccc pair`)
- Session list on a machine (live, most recently active first)
- Rename a session (tap the title)
- Archive a session (swipe) so it leaves the main list; restore from Archived
- Chat with one session (history + send + photos + live progress)
