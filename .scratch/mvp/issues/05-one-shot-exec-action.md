# 05 — One-shot exec action

**What to build:** From a running sprite's detail screen, the user can run a single command and see its captured output as plain text (stdout/stderr distinguished, exit status shown). Non-TTY framed exec only; no terminal emulator (ADR 0002).

**Blocked by:** 04 — Sprite detail with deep observation.

**Status:** resolved

- [ ] User enters a command, sees streamed/captured output as text with exit status
- [ ] stderr is visually distinguished from stdout
- [ ] Long output is scrollable; the run can be cancelled
- [ ] No PTY, no terminal rendering — plain text only
