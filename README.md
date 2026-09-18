# CCC

Open-source phone app for [ccc](https://github.com/kidandcat/ccc). Anyone can run `ccc listen` on a Mac or VPS, install this app, and pair.

```
ccc pair          # on the machine
# paste the ccc://pair/v1?… URI in the app
```

The default hub (`wss://hub.mentasystems.com`) is a free encrypted relay. It cannot read your chats. Run `ccc hub` yourself if you want it on your metal.

A machine opens on **Chief**, the dispatcher — same as the Telegram DM. Workers Chief starts appear under Sessions with running / waiting / idle, and drop off when archived. Unanswered `ask_owner` questions stay in a Decisions inbox and a sticky card above chat — same option buttons as Telegram.

- License: MIT
- Privacy: https://hub.mentasystems.com/privacy
- Issues: https://github.com/kidandcat/ccc/issues

## Build

```bash
flutter run
```

Bundle id / applicationId: `dev.ccc.app`.
