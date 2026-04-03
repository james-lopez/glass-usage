# Bot-o-Meter

A native macOS menu bar app + WidgetKit desktop widget that shows your live Claude CLI usage — weekly limits, 5-hour limits, per-model quotas, and local session stats — styled with speedometer-style gauge dials and a pixel robot mascot.

---

## What it shows

Mirrors what you see at `claude.ai/settings/usage` plus local session data:

| Section | Source |
|---|---|
| 5-hour limit % | Claude API (live) |
| Weekly limit % | Claude API (live) |
| Opus model limit % | Claude API (live) |
| Output tokens | Local `~/.claude` JSONL files |
| Cache reads, API calls | Local `~/.claude` JSONL files |

Refreshes every 15 minutes. Shows graceful error states for offline, logged-out, rate-limited, and expired-token scenarios.

---

## Install

### Homebrew (recommended)

```bash
brew install --cask james-lopez/tap/botometer
```

The app will appear in `/Applications`. Launch it once and it installs itself in the menu bar.

After first launch, add the widget:

1. Right-click desktop → **Edit Widgets**
2. Search **Bot-o-Meter**
3. Drag Small or Medium to your desktop

---

## Build from source

### Requirements

- macOS 14 (Sonoma) or later  
- Xcode 16 or later  
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)  
- [Claude CLI](https://claude.ai/download) installed and logged in

```bash
cd botometer
xcodegen generate
open botometer.xcodeproj
```

Select the **botometer** scheme, press **⌘R**. The app appears as a dial icon in the menu bar.

After first launch, add the widget:

1. Right-click desktop → **Edit Widgets**
2. Search **Bot-o-Meter**
3. Drag Small or Medium to your desktop

---

## Project structure

```
botometer/               ← git root
└── botometer/           ← Xcode project folder
    ├── project.yml      ← xcodegen config
    ├── botometer/       ← main app target
    │   ├── BotometerApp.swift
    │   ├── ContentView.swift
    │   └── WidgetPreviews.swift
    ├── botometerWidget/ ← widget extension target
    │   └── BotometerWidget.swift
    └── Shared/          ← compiled into both targets
        ├── Models.swift
        ├── APIClient.swift
        ├── UsageParser.swift
        └── WidgetViews.swift
```

---

## Auth & error states

| State | What you see |
|---|---|
| Claude CLI not installed | Warning + install hint |
| Not logged in | Error + `claude` hint |
| Session expired | Refresh prompt |
| Rate limited (HTTP 429) | "Rate limit reached" + retry hint |
| API unreachable | Offline indicator |
| Loaded | Live gauge dials |

The widget reads your OAuth token from the macOS keychain (`Claude Code-credentials`, stored by the Claude CLI). Token never leaves your machine except to the official Claude API.

---

## How it works

```
macOS Keychain
  └── "Claude Code-credentials"
        └── claudeAiOauth.accessToken
              └── GET claude.ai/api/oauth/usage
                    └── 5h %, weekly %, opus %

~/.claude/projects/**/*.jsonl
  └── assistant entries → output tokens, cache reads, API calls
```

---

## Key files

| File | Purpose |
|---|---|
| `Shared/APIClient.swift` | Keychain reading + Claude API call |
| `Shared/UsageParser.swift` | Local JSONL session parsing |
| `Shared/Models.swift` | Shared data models + `UsageEntry` |
| `Shared/WidgetViews.swift` | `GaugeDial`, `BitCharacter`, all widget views |
| `botometer/ContentView.swift` | Menu bar popup UI |
| `botometerWidget/BotometerWidget.swift` | WidgetKit timeline provider |

---

## What's next

- [ ] Screenshots in this README
- [ ] `release.sh` script to automate archive → notarize → GitHub release → tap update
- [ ] UI polish based on daily use
- [ ] Auto-launch at login option

---

## License

MIT
