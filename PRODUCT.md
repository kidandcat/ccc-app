# CCC app

Public store app for anyone running their own ccc. Talk to **General** from a phone the way the Telegram DM works: pick a computer, talk to the dispatcher. Sessions are backend workers — a roster, not peer chats.

The phone never holds Telegram tokens or engine credentials. Each `ccc listen` instance keeps an outbound encrypted connection to a public hub. The hub is a dumb pipe (Tailscale DERP, not a VPN mesh): it routes NaCl boxes between a machine and a paired device and cannot read them.

Pairing is TOFU. `ccc pair` prints a URI whose query carries the instance public key; the phone encrypts its identity to that key. The hub only forwards.

## Surfaces

- Machine list (several ccc instances: Mac, VPS, …)
- Pair a machine (paste URI from `ccc pair`)
- Machine home is **General** (the dispatcher). Same hub as the Telegram DM. General cannot be renamed or archived.
- Sessions roster (from General): backend workers as live status cards (running / waiting / idle), same glance as Grok Bot cloud agents — name, status pill, current thinking or last line. They also sit as a sticky strip on General. They drop off when archived (hub `session`/`archive` events, 4s poll of `bots`, and a client-side `archived` filter). Opening a worker shows its log; sending there is `tell_session`. Chat pops if that worker is gone.
- Rename a worker (tap the title). Not General.
- Archive a worker (swipe, no confirm); restore from Archived
- Decisions inbox: unanswered `ask_owner` questions stay in a banner / Decisions screen / sticky card above chat (Telegram-style option buttons). Answering there is hub `answer` (same as tapping the Telegram button). They cannot scroll away in the thread.
- Chat with General (history + send + photos + any file up to 50 MB including APKs + GitHub-flavored Markdown including tables + live thinking/tool progress that is restored when you leave and come back). Worker reports are captions, not owner bubbles. Internal `source=system` injections stay hidden.
- Receive files a session sends (`send_file`): tap the chip to download and share/save
- Push notification when General posts, a session sends a file, or `ask_owner` asks — the same pings Telegram would send. Worker transcripts do not notify. Android keeps the hub socket alive in a dataSync foreground service.
