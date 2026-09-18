# CCC app

Public store app for anyone running their own Crew Command Center. Talk to a team from a phone the way Grok Bot talks to a local machine: pick a computer, pick a bot, talk.

The phone never holds Telegram tokens or engine credentials. Each `ccc listen` instance keeps an outbound encrypted connection to a public hub. The hub is a dumb pipe (Tailscale DERP, not a VPN mesh): it routes NaCl boxes between a machine and a paired device and cannot read them.

Pairing is TOFU. `ccc pair` prints a URI whose query carries the instance public key; the phone encrypts its identity to that key. The hub only forwards.

## Surfaces

- Machine list (several ccc instances: Mac, VPS, …)
- Pair a machine (paste URI from `ccc pair`)
- Session list on a machine (live, most recently active first). Backend workers General opens appear here with live status (running / waiting / idle). They drop off the list when archived or closed (hub `session`/`archive` events, 4s poll of `bots`, and a client-side `archived` filter). Chat pops if that worker is gone. Same hub as General DM — not a second API.
- Rename a session (tap the title)
- Archive a session (swipe, no confirm) so it leaves the main list; restore from Archived
- Decisions inbox: unanswered `ask_owner` questions stay in a banner / Decisions screen / sticky card above chat (Telegram-style option buttons). Answering there is hub `answer` (same as tapping the Telegram button). They cannot scroll away in the thread.
- Chat with one session (history + send + photos + any file up to 50 MB including APKs + GitHub-flavored Markdown including tables + live thinking/tool progress that is restored when you leave and come back)
- Receive files the session sends (`send_file`): tap the chip to download and share/save
- Push notification on the phone when a session posts a new message or asks a question (`ask_owner`), including when the app is in the background (Android keeps the hub socket alive in a dataSync foreground service)
