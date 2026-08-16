# 03 - Status details with long-press copy

**What to build:** An integration's observed status can carry ordered detail rows (label, value) under its summary. The detail screen shows them, and any row copies its value on long-press. T3 Code moves its installed version out of the summary into a detail row, so the summary reads as a status again.

**Blocked by:** None - can start immediately.

**Status:** ready-for-agent

- [ ] `IntegrationStatus` gains `details`, an ordered list of label/value pairs, defaulting to empty
- [ ] The detail screen renders details under the summary; long-press on a row copies the value to the pasteboard
- [ ] T3 Code's summary is "service running" / "service <state>" / "not set up" and its version is a detail
- [ ] Tests assert the T3 version detail and the unchanged summary; existing summary assertions updated
