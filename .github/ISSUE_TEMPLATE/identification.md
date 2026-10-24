---
name: Service not identified
about: PortScope shows the wrong service name, or none, for a port
title: ""
labels: identification
---

## What is on the port

<!--
Which service is actually running: the product and, if you know, the framework.
-->

## What PortScope says

```bash
PortScope --list
# paste the row for this port
```

## What it should say

<!-- e.g. "Vite, not Node.js" -->

## Why PortScope should be able to tell

<!--
Identification uses three tiers, strongest first: process metadata (executable,
argv, working directory), HTTP response headers, and finally the port number.
If you know which of those would give it away, say so — it usually means a
missing fingerprint rather than a broken rule.
-->

- [ ] The command line contains something distinctive (paste it):
- [ ] It sends a distinctive HTTP header (paste `curl -sI localhost:PORT`):
- [ ] It is the standard port for this service (which one):

## Environment

- PortScope version:
- macOS version:
