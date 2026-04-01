# GlassUsage

A native macOS widget that shows your live Claude CLI usage — weekly limits, 5-hour limits, per-model quotas, and local session stats — styled with the Apple glass aesthetic.

![Widget preview showing usage bars and session stats](preview.png)

---

## What it shows

Mirrors what you see at `claude.ai/settings/usage` plus local session data:

| Section | Source |
|---|---|
| Weekly limit % | Claude API (live) |
| 5-hour limit % | Claude API (live) |
| Opus / Sonnet model limits | Claude API (live) |
| Extra usage (overages) | Claude API (live) |
| Output tokens, cache reads, API calls | Local `~/.claude` JSONL files |

Refreshes every 15 minutes. Shows graceful error states if you're offline or logged out.

---

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16 or later
- [Claude CLI](https://claude.ai/download) installed and logged in

---

## Setup in Xcode

The source files are ready — you need to create the Xcode project and wire them up. This takes about 5 minutes.

### 1. Create the Xcode project

1. Open Xcode → **File > New > Project**
2. Choose **macOS > App**, click Next
3. Name it `GlassUsage`, set bundle ID to something like `com.yourname.GlassUsage`
4. Uncheck **Include Tests**, click Next
5. Save into this repo folder (replace the generated files)

### 2. Add the Widget Extension

1. **File > New > Target**
2. Choose **macOS > Widget Extension**, click Next
3. Name it `GlassUsageWidget`
4. Uncheck **Include Configuration App Intent**
5. Click Finish

### 3. Add the source files

Drag these files into the **GlassUsage** target in the Project Navigator:
- `GlassUsage/GlassUsageApp.swift`
- `GlassUsage/ContentView.swift`
- `GlassUsage/Models.swift`
- `GlassUsage/APIClient.swift`
- `GlassUsage/UsageParser.swift`

Drag these into the **GlassUsageWidget** target:
- `GlassUsageWidget/GlassUsageWidget.swift`
- `GlassUsage/Models.swift` *(add to this target too)*
- `GlassUsage/APIClient.swift` *(add to this target too)*
- `GlassUsage/UsageParser.swift` *(add to this target too)*

### 4. Disable App Sandbox (required)

The widget needs to read `~/.claude` and the macOS keychain. For a personal tool, the simplest fix is disabling the sandbox.

For **each target** (GlassUsage and GlassUsageWidget):

1. Select the target in Xcode
2. Go to **Signing & Capabilities**
3. Click the **App Sandbox** capability and remove it (click the trash icon)

> **Note:** This is fine for a personal tool. If you ever want to distribute via the App Store, you'd use App Groups instead.

### 5. Build and run

Select the **GlassUsage** scheme, press **⌘R**.

---

## Adding the widget to your desktop

1. Build and run the app at least once (this registers the widget with macOS)
2. Right-click your desktop → **Edit Widgets**
3. Search for **Claude Usage**
4. Drag the Small or Medium widget to your desktop

---

## Auth & error states

The widget handles these states automatically:

| State | What you see | Fix |
|---|---|---|
| Claude CLI not installed | Warning + install hint | Install Claude CLI |
| Not logged in | Error + run hint | Run `claude` in terminal |
| Session expired | Warning | Open Claude CLI to refresh |
| API unreachable | Offline indicator | Check network |
| Loaded | Live usage bars | — |

The widget reads your OAuth token from the macOS keychain (stored there by the Claude CLI under `Claude Code-credentials`). It never stores or transmits your token anywhere other than the official Claude API.

---

## How it works

```
macOS Keychain
  └── "Claude Code-credentials"
        └── claudeAiOauth.accessToken
              └── GET claude.ai/api/oauth/usage
                    └── weekly %, 5h %, Opus %, Sonnet %, extra usage

~/.claude/projects/**/*.jsonl
  └── assistant entries with usage.input_tokens / output_tokens / cache_*
        └── aggregated into local session stats
```

The usage API endpoint is the same one the Claude CLI's `/usage` command uses internally.

---

## Contributing

PRs welcome. Key files:

- `APIClient.swift` — keychain reading + API call
- `UsageParser.swift` — local JSONL parsing
- `Models.swift` — shared data models
- `ContentView.swift` — main app UI
- `GlassUsageWidget.swift` — WidgetKit extension

---

## License

MIT
