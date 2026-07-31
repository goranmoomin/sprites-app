# Sprite state is observed, never app-durable

Everything the detail screen shows about a Sprite (agent logins, services, integration recognition, pairing, tasks) is recomputed from the Sprite itself on each visit; the app keeps no durable record of it. This makes checkpoint restore, multi-device use, and app reinstall need no special handling — the screen simply re-observes — and it prevents the app from ever claiming state the Sprite no longer has.

Because deep observation (exec/fs/services calls) counts as activity and wakes a cold Sprite, observation has two levels: shallow (control-plane metadata: name, status, URL — never wakes) always runs; deep runs only when the Sprite is already running or the user explicitly wakes it. A cold Sprite's detail screen shows shallow data plus a wake affordance instead of stale claims. A read-through cache for "last seen" values is a permitted future optimization, not a source of truth.
