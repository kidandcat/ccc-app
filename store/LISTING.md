# CCC — store listing kit

Public app for anyone running [Crew Command Center](https://github.com/kidandcat/ccc).

Signing keys and Play/ASC API credentials stay **out of this repo** (it is public). Codemagic env groups, not committed `.jks` / `.p8`.

- **iOS bundle id:** `dev.ccc.app` (ASC `354LTQN4LU`, team `5M4PZM9Z6T`)
- **Android applicationId:** `dev.ccc.app`
- **GitHub:** https://github.com/kidandcat/ccc-app (MIT, public)
- **Server:** https://github.com/kidandcat/ccc
- **Privacy:** https://hub.mentasystems.com/privacy
- **Support:** https://github.com/kidandcat/ccc/issues
- **Category:** Developer Tools (iOS) / Productivity (Play)
- **Price:** Free
- **Age:** 4+ / PEGI 3 — no public UGC; chat is with *your* bots on *your* machine

## App Store (iOS)

| Field | Value |
|---|---|
| Nombre (30) | `CCC` |
| Subtítulo (30) | `Tus bots, en el móvil` |
| Keywords (100) | `ccc,bots,claude,grok,telegram,dev,cli,pair,hub,selfhosted` |
| Support URL | `https://github.com/kidandcat/ccc` |
| Marketing URL | `https://github.com/kidandcat/ccc` |
| Privacy Policy URL | `https://hub.mentasystems.com/privacy` |

**Texto promocional (170):**

> Instala CCC en tu Mac o VPS, abre la app, pega el código de `ccc pair` y habla con tus bots como en Telegram — sin exponer el puerto.

**Descripción:**

> CCC es el cliente móvil de Crew Command Center: un equipo de bots (Claude, Grok, Codex…) que viven en tu máquina, no en la nube de nadie.
>
> EMPAREJA EN SEGUNDOS
> En el ordenador ejecutas `ccc pair`. En el móvil pegas la URI. Listo. Puedes tener varias máquinas (el portátil, un VPS) y cambiar entre ellas.
>
> HABLA CON TUS BOTS
> Cada bot es un hilo. Escribes, ves el progreso, recibes la respuesta. Igual que en el grupo de Telegram, sin Telegram.
>
> PRIVADO POR DISEÑO
> El hub público solo reenvía cajas cifradas. No ve tus mensajes ni tus tokens. Si quieres, montas tu propio hub con `ccc hub`.
>
> PARA QUIEN YA USA CCC
> Necesitas una instancia de ccc (https://github.com/kidandcat/ccc) en marcha. La app no sustituye al servidor: es el mando a distancia.

**App Review notes:**

> CCC is a companion for a self-hosted CLI (Crew Command Center). There is no cloud login. To review pairing you need a machine running `ccc listen`; we can provide a reviewer pairing URI on request via Resolution Center. The app otherwise shows an empty machine list and pairing instructions.

## Google Play

| Field | Value |
|---|---|
| Título (30) | `CCC` |
| Descripción corta (80) | `Habla con tus bots de Crew Command Center. Empareja tu Mac o VPS en segundos.` |
| Categoría | Productividad |
| Email | `kidandcat@gmail.com` |
| Política de privacidad | `https://hub.mentasystems.com/privacy` |
| URL de borrado | `https://hub.mentasystems.com/privacy#delete` |

**Descripción larga:** same as App Store description.

**Data safety:** no collected data (no account, no analytics). Encryption in transit (NaCl boxes over WSS).
