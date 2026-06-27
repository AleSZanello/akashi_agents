# Akashi showcase

A Flutter **web** app of live, in-browser demos for the Akashi agent framework —
the analog of Bonfire's demo site. Every demo runs entirely client-side on a
scripted **fake model** (`ScriptedModel`), so there are **no API keys and no
backend**.

🌐 **Live:** https://akashi-agents.web.app (custom domain:
`akashi.azanello.com`, see below)

## Demos

Grouped by Akashi's three pillars:

- **Foundations** — Streaming chat · Typed tool calling · Human-in-the-loop approval
- **Multi-agent** — Subagent-as-tool · Handoffs · Model escalation
- **Durable & Flutter** — Durable suspend / resume (pause across a simulated
  process restart, resuming from an in-browser `CheckpointStore`)

Each demo has a **Live** tab and a **Code** tab showing the Akashi code behind it.

## Architecture

It depends on local `akashi` + `akashi_flutter` via path overrides (it is **not**
a pub-workspace member — it needs the Flutter SDK, like `akashi_flutter`).

```
lib/
  main.dart                 # entry
  src/
    app.dart                # MaterialApp.router + GoRouter
    theme.dart              # Akashi dark theme + palette
    scripted_model.dart     # ScriptedModel: a client-side fake LanguageModel
    demos/                  # one file per demo + registry.dart + demo.dart (model)
    widgets/                # gallery shell, demo view, chat panel, code view, home
```

The reusable `ChatPanel` (in `widgets/`) drives an `AgentController`
(`akashi_flutter`) and renders the transcript, tool-call chips, reasoning
disclosures, a live streaming bubble, and an inline approval card that resolves
both in-process and durable pauses.

## Run locally

```bash
cd examples/web_showcase
flutter pub get
flutter run -d chrome        # or: flutter run -d web-server
```

Checks:

```bash
flutter analyze
flutter test                 # runtime smoke tests for the demos
flutter build web --release  # output in build/web
```

## Deploy (Firebase Hosting · project `akashi-agents`)

Hosting config lives here (`firebase.json`, `.firebaserc`). Manual deploy:

```bash
cd examples/web_showcase
flutter build web --release
firebase deploy --only hosting --project akashi-agents
```

### Automatic deploy (CI)

`.github/workflows/deploy-showcase.yaml` builds and deploys on every push to
`main` that touches the showcase or `akashi`/`akashi_flutter`. It authenticates
with the repo secret **`FIREBASE_SERVICE_ACCOUNT_AKASHI_AGENTS`** (a
Hosting-admin service-account JSON), which is already configured for this repo.

To recreate it elsewhere, the one-shot path is:

```bash
cd examples/web_showcase
firebase init hosting:github   # creates the SA + the GitHub secret + a workflow
```

…or manually: create a service account with the **Firebase Hosting Admin** role,
download a JSON key, and `gh secret set FIREBASE_SERVICE_ACCOUNT_AKASHI_AGENTS
--body "$(cat key.json)"`.

## Custom domain — `akashi.azanello.com`

Custom domains require DNS verification, so they're connected once via the
console (not scriptable):

1. Firebase Console → **Hosting** → **Add custom domain** → `akashi.azanello.com`.
2. Add the **TXT** record Firebase shows to the `azanello.com` DNS zone to verify
   ownership.
3. Add the **A records** (or the provided `CNAME`) Firebase shows for
   `akashi` → Firebase Hosting. SSL is provisioned automatically (can take up to
   ~24h).

Until then the site is reachable at `https://akashi-agents.web.app`.
