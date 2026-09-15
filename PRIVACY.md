# Privacy policy — CCC

Last updated: 2026-09-15

CCC (Crew Command Center) is an open-source phone client for *your* `ccc listen` instance. There is no CCC user account.

## What the app stores on the device

- A Curve25519 keypair (to encrypt traffic to your machines)
- The list of machines you paired (hub URL, public key, name)

Nothing else is persisted. Uninstalling the app, or removing a machine in the app, deletes that data.

## What the public hub sees

The default hub (`hub.mentasystems.com`) is an encrypted relay. It sees:

- Public keys and short-lived pairing codes
- Opaque ciphertext (NaCl boxes)

It does **not** see your Telegram token, bot prompts, chat text, files, or engine credentials. Anyone may run their own hub (`ccc hub`) and point `ccc config set hub_url` at it.

## What your machine sees

Your `ccc listen` process receives the messages you send from the app, the same way it receives Telegram messages. That data stays on the machine you control.

## No tracking

The app does not include analytics SDKs, advertising identifiers, or crash reporters that phone home.

## Children

The app is a developer tool. It is not directed at children.

## Contact

Issues: https://github.com/kidandcat/ccc/issues  
Email: kidandcat@gmail.com

## Deleting data

There is no cloud account to delete. In the app, long-press a machine to unpair it. On the machine, `ccc unpair` revokes the device. Uninstalling the app removes local keys.
