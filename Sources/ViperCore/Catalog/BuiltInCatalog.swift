import Foundation

public extension Catalog {
    /// Editorial catalog reviewed on `reviewedAt`. It is validated with the same rules as any future catalog data.
    static func builtIn() throws -> Catalog { try decode(Data(builtInJSON.utf8)) }
}

// Reviewed mappings: Homebrew tokens are canonical names (not aliases), npm names are exact registry names.
private let builtInJSON = #"""
{
  "schemaVersion": 1,
  "catalogVersion": "2026.09.21",
  "reviewedAt": "2026-09-21",
  "collections": [
    {
      "id": "editors-picks",
      "name": "Editor’s picks",
      "summary": "A well-rounded start for most Macs. An editorial selection, not a usage ranking.",
      "apps": [
        "firefox",
        "vlc",
        "rectangle",
        "the-unarchiver",
        "obsidian",
        "libreoffice"
      ]
    },
    {
      "id": "developer-setup",
      "name": "Developer setup",
      "summary": "An editor, a better terminal, and everyday command-line tools.",
      "apps": [
        "visual-studio-code",
        "iterm2",
        "git",
        "gh",
        "node",
        "ripgrep",
        "docker-desktop"
      ]
    },
    {
      "id": "ai-toolkit",
      "name": "AI toolkit",
      "summary": "Desktop assistants, terminal agents, and local models.",
      "apps": [
        "claude",
        "chatgpt",
        "claude-code",
        "codex",
        "ollama"
      ]
    },
    {
      "id": "creator-studio",
      "name": "Creator studio",
      "summary": "Record, edit, and design with free tools.",
      "apps": [
        "obs",
        "handbrake",
        "audacity",
        "gimp",
        "inkscape",
        "blender"
      ]
    },
    {
      "id": "terminal-toolkit",
      "name": "Terminal toolkit",
      "summary": "Everyday command-line upgrades: search, files, Git, and media.",
      "apps": [
        "bat",
        "fd",
        "fzf",
        "eza",
        "jq",
        "tmux",
        "lazygit",
        "ripgrep",
        "yt-dlp"
      ]
    },
    {
      "id": "home-office",
      "name": "Home office",
      "summary": "Meetings, notes, tasks, and docs for a work-from-anywhere Mac.",
      "apps": [
        "zoom",
        "slack",
        "notion",
        "obsidian",
        "craft",
        "logseq"
      ]
    }
  ],
  "apps": [
    {
      "id": "visual-studio-code",
      "name": "Visual Studio Code",
      "publisher": "Microsoft",
      "summary": "A popular, extensible code editor for almost any language.",
      "category": "developer",
      "kind": "app",
      "website": "https://code.visualstudio.com",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "visual-studio-code"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.microsoft.VSCode"
      ],
      "appNames": [
        "Visual Studio Code.app"
      ]
    },
    {
      "id": "zed",
      "name": "Zed",
      "publisher": "Zed Industries",
      "summary": "A fast, modern code editor with built-in collaboration.",
      "category": "developer",
      "kind": "app",
      "website": "https://zed.dev",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "zed"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "dev.zed.Zed"
      ],
      "appNames": [
        "Zed.app"
      ]
    },
    {
      "id": "iterm2",
      "name": "iTerm2",
      "publisher": "George Nachman",
      "summary": "A feature-rich alternative to the built-in Terminal app.",
      "category": "developer",
      "kind": "app",
      "website": "https://iterm2.com",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "iterm2"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.googlecode.iterm2"
      ],
      "appNames": [
        "iTerm.app"
      ]
    },
    {
      "id": "jetbrains-toolbox",
      "name": "JetBrains Toolbox",
      "publisher": "JetBrains",
      "summary": "Installs and updates JetBrains IDEs such as IntelliJ IDEA and PyCharm.",
      "category": "developer",
      "kind": "app",
      "website": "https://www.jetbrains.com/toolbox-app/",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "jetbrains-toolbox"
      },
      "bundleIdentifiers": [
        "com.jetbrains.toolbox"
      ],
      "appNames": [
        "JetBrains Toolbox.app"
      ],
      "notes": [
        "Individual IDEs are downloaded inside the Toolbox app and some need a licence."
      ]
    },
    {
      "id": "sublime-text",
      "name": "Sublime Text",
      "publisher": "Sublime HQ",
      "summary": "A lightweight, fast editor for code and prose.",
      "category": "developer",
      "kind": "app",
      "website": "https://www.sublimetext.com",
      "pricing": "paid",
      "install": {
        "method": "homebrewCask",
        "package": "sublime-text"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.sublimetext.4"
      ],
      "appNames": [
        "Sublime Text.app"
      ],
      "notes": [
        "You can evaluate it first; continued use requires a licence."
      ]
    },
    {
      "id": "postman",
      "name": "Postman",
      "publisher": "Postman",
      "summary": "Build, test, and document APIs.",
      "category": "developer",
      "kind": "app",
      "website": "https://www.postman.com/downloads/",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "postman"
      },
      "bundleIdentifiers": [
        "com.postmanlabs.mac"
      ],
      "appNames": [
        "Postman.app"
      ]
    },
    {
      "id": "docker-desktop",
      "name": "Docker Desktop",
      "publisher": "Docker",
      "summary": "Run containers and local development environments.",
      "category": "developer",
      "kind": "app",
      "website": "https://www.docker.com/products/docker-desktop/",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "docker-desktop"
      },
      "bundleIdentifiers": [
        "com.docker.docker"
      ],
      "appNames": [
        "Docker.app"
      ],
      "notes": [
        "On first launch Docker asks you to accept its subscription terms and may request administrator approval for helper tools."
      ]
    },
    {
      "id": "xcode",
      "name": "Xcode",
      "publisher": "Apple",
      "summary": "Apple’s tools for building apps for Mac, iPhone, iPad, and more.",
      "category": "developer",
      "kind": "app",
      "website": "https://developer.apple.com/xcode/",
      "pricing": "free",
      "install": {
        "method": "appStore",
        "url": "macappstore://itunes.apple.com/app/id497799835"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "com.apple.dt.Xcode"
      ],
      "appNames": [
        "Xcode.app"
      ]
    },
    {
      "id": "git",
      "name": "Git",
      "publisher": "The Git project",
      "summary": "Track changes in code and other files.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://git-scm.com",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "git"
      },
      "requiresAccount": false,
      "commands": [
        "git"
      ],
      "notes": [
        "macOS can also include Apple’s Git with the Command Line Tools. Homebrew installs its own separate copy."
      ]
    },
    {
      "id": "gh",
      "name": "GitHub CLI",
      "publisher": "GitHub",
      "summary": "Work with GitHub pull requests, issues, and repositories from the terminal.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://cli.github.com",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "gh"
      },
      "requiresAccount": true,
      "commands": [
        "gh"
      ]
    },
    {
      "id": "node",
      "name": "Node.js",
      "publisher": "OpenJS Foundation",
      "summary": "The JavaScript runtime, including npm for installing command-line tools.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://nodejs.org",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "node"
      },
      "requiresAccount": false,
      "commands": [
        "node"
      ],
      "notes": [
        "Includes npm. After it installs, choose Check again to make npm-based tools available."
      ]
    },
    {
      "id": "ripgrep",
      "name": "ripgrep",
      "publisher": "Andrew Gallant",
      "summary": "Search text across files and folders very quickly.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://github.com/BurntSushi/ripgrep",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "ripgrep"
      },
      "requiresAccount": false,
      "commands": [
        "rg"
      ]
    },
    {
      "id": "typescript",
      "name": "TypeScript",
      "publisher": "Microsoft",
      "summary": "Typed JavaScript, including the tsc compiler.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://www.typescriptlang.org",
      "pricing": "free",
      "install": {
        "method": "npm",
        "package": "typescript"
      },
      "requiresAccount": false,
      "commands": [
        "tsc"
      ]
    },
    {
      "id": "pnpm",
      "name": "pnpm",
      "publisher": "pnpm contributors",
      "summary": "A fast, disk-efficient package manager for JavaScript projects.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://pnpm.io",
      "pricing": "free",
      "install": {
        "method": "npm",
        "package": "pnpm"
      },
      "requiresAccount": false,
      "commands": [
        "pnpm"
      ]
    },
    {
      "id": "claude",
      "name": "Claude",
      "publisher": "Anthropic",
      "summary": "Anthropic’s desktop app for chatting and working with Claude.",
      "category": "ai",
      "kind": "app",
      "website": "https://claude.ai/download",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "claude"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "com.anthropic.claudefordesktop"
      ],
      "appNames": [
        "Claude.app"
      ]
    },
    {
      "id": "chatgpt",
      "name": "ChatGPT",
      "publisher": "OpenAI",
      "summary": "OpenAI’s desktop app for ChatGPT.",
      "category": "ai",
      "kind": "app",
      "website": "https://openai.com/chatgpt/desktop/",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "chatgpt"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "com.openai.chat"
      ],
      "appNames": [
        "ChatGPT.app"
      ]
    },
    {
      "id": "claude-code",
      "name": "Claude Code",
      "publisher": "Anthropic",
      "summary": "An AI coding agent that works in your terminal and codebase.",
      "category": "ai",
      "kind": "commandLine",
      "website": "https://www.anthropic.com/claude-code",
      "pricing": "paid",
      "install": {
        "method": "npm",
        "package": "@anthropic-ai/claude-code"
      },
      "requiresAccount": true,
      "commands": [
        "claude"
      ],
      "notes": [
        "Needs a Claude subscription or Anthropic API billing to use."
      ]
    },
    {
      "id": "codex",
      "name": "Codex CLI",
      "publisher": "OpenAI",
      "summary": "OpenAI’s coding agent for the terminal.",
      "category": "ai",
      "kind": "commandLine",
      "website": "https://github.com/openai/codex",
      "pricing": "unverified",
      "install": {
        "method": "npm",
        "package": "@openai/codex"
      },
      "requiresAccount": true,
      "commands": [
        "codex"
      ]
    },
    {
      "id": "gemini-cli",
      "name": "Gemini CLI",
      "publisher": "Google",
      "summary": "Google’s open-source AI agent for the terminal.",
      "category": "ai",
      "kind": "commandLine",
      "website": "https://github.com/google-gemini/gemini-cli",
      "pricing": "freemium",
      "install": {
        "method": "npm",
        "package": "@google/gemini-cli"
      },
      "requiresAccount": true,
      "commands": [
        "gemini"
      ]
    },
    {
      "id": "ollama",
      "name": "Ollama",
      "publisher": "Ollama",
      "summary": "Download and run open AI models locally on your Mac.",
      "category": "ai",
      "kind": "app",
      "website": "https://ollama.com",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "ollama-app"
      },
      "requiresAccount": false,
      "appNames": [
        "Ollama.app"
      ],
      "commands": [
        "ollama"
      ],
      "notes": [
        "Models are downloaded separately and can use many gigabytes."
      ]
    },
    {
      "id": "lm-studio",
      "name": "LM Studio",
      "publisher": "Element Labs",
      "summary": "Discover, download, and chat with local AI models.",
      "category": "ai",
      "kind": "app",
      "website": "https://lmstudio.ai",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "lm-studio"
      },
      "requiresAccount": false,
      "appNames": [
        "LM Studio.app"
      ],
      "appleSiliconOnly": true,
      "notes": [
        "Models are downloaded separately and can use many gigabytes."
      ]
    },
    {
      "id": "spotify",
      "name": "Spotify",
      "publisher": "Spotify",
      "summary": "Stream music and podcasts.",
      "category": "audio",
      "kind": "app",
      "website": "https://www.spotify.com/download/mac/",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "spotify"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "com.spotify.client"
      ],
      "appNames": [
        "Spotify.app"
      ]
    },
    {
      "id": "audacity",
      "name": "Audacity",
      "publisher": "Audacity Team",
      "summary": "Record and edit audio with a free multi-track editor.",
      "category": "audio",
      "kind": "app",
      "website": "https://www.audacityteam.org",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "audacity"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "org.audacityteam.audacity"
      ],
      "appNames": [
        "Audacity.app"
      ]
    },
    {
      "id": "garageband",
      "name": "GarageBand",
      "publisher": "Apple",
      "summary": "Make music with virtual instruments, loops, and recording tools.",
      "category": "audio",
      "kind": "app",
      "website": "https://www.apple.com/mac/garageband/",
      "pricing": "free",
      "install": {
        "method": "appStore",
        "url": "macappstore://itunes.apple.com/app/id682658836"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "com.apple.garageband10"
      ],
      "appNames": [
        "GarageBand.app"
      ]
    },
    {
      "id": "logic-pro",
      "name": "Logic Pro",
      "publisher": "Apple",
      "summary": "Professional music production and recording.",
      "category": "audio",
      "kind": "app",
      "website": "https://www.apple.com/logic-pro/",
      "pricing": "paid",
      "install": {
        "method": "appStore",
        "url": "macappstore://itunes.apple.com/app/id634148309"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "com.apple.logic10"
      ],
      "appNames": [
        "Logic Pro.app"
      ]
    },
    {
      "id": "vlc",
      "name": "VLC media player",
      "publisher": "VideoLAN",
      "summary": "Plays almost any video or audio file.",
      "category": "video",
      "kind": "app",
      "website": "https://www.videolan.org/vlc/",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "vlc"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "org.videolan.vlc"
      ],
      "appNames": [
        "VLC.app"
      ]
    },
    {
      "id": "iina",
      "name": "IINA",
      "publisher": "IINA project",
      "summary": "A modern media player designed for macOS.",
      "category": "video",
      "kind": "app",
      "website": "https://iina.io",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "iina"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.colliderli.iina"
      ],
      "appNames": [
        "IINA.app"
      ]
    },
    {
      "id": "obs",
      "name": "OBS Studio",
      "publisher": "OBS Project",
      "summary": "Record your screen and stream live video.",
      "category": "video",
      "kind": "app",
      "website": "https://obsproject.com",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "obs"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.obsproject.obs-studio"
      ],
      "appNames": [
        "OBS.app"
      ],
      "notes": [
        "Screen recording asks for your permission in System Settings the first time."
      ]
    },
    {
      "id": "handbrake",
      "name": "HandBrake",
      "publisher": "HandBrake Team",
      "summary": "Convert video files between formats.",
      "category": "video",
      "kind": "app",
      "website": "https://handbrake.fr",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "handbrake-app"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "fr.handbrake.HandBrake"
      ],
      "appNames": [
        "HandBrake.app"
      ]
    },
    {
      "id": "final-cut-pro",
      "name": "Final Cut Pro",
      "publisher": "Apple",
      "summary": "Professional video editing.",
      "category": "video",
      "kind": "app",
      "website": "https://www.apple.com/final-cut-pro/",
      "pricing": "paid",
      "install": {
        "method": "appStore",
        "url": "macappstore://itunes.apple.com/app/id424389933"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "com.apple.FinalCut"
      ],
      "appNames": [
        "Final Cut Pro.app"
      ]
    },
    {
      "id": "davinci-resolve",
      "name": "DaVinci Resolve",
      "publisher": "Blackmagic Design",
      "summary": "Video editing, colour correction, effects, and audio post-production.",
      "category": "video",
      "kind": "app",
      "website": "https://www.blackmagicdesign.com/products/davinciresolve",
      "pricing": "freemium",
      "install": {
        "method": "vendor",
        "url": "https://www.blackmagicdesign.com/products/davinciresolve"
      },
      "bundleIdentifiers": [
        "com.blackmagic-design.DaVinciResolve"
      ],
      "appNames": [
        "DaVinci Resolve.app"
      ],
      "notes": [
        "Downloaded from the publisher’s website, which asks for registration details."
      ]
    },
    {
      "id": "steam",
      "name": "Steam",
      "publisher": "Valve",
      "summary": "Buy, download, and play games from Valve’s store.",
      "category": "gaming",
      "kind": "app",
      "website": "https://store.steampowered.com/about/",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "steam"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "com.valvesoftware.steam"
      ],
      "appNames": [
        "Steam.app"
      ],
      "notes": [
        "Games are purchased and downloaded separately inside Steam."
      ]
    },
    {
      "id": "epic-games",
      "name": "Epic Games Launcher",
      "publisher": "Epic Games",
      "summary": "Download and play games from the Epic Games Store.",
      "category": "gaming",
      "kind": "app",
      "website": "https://store.epicgames.com/download",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "epic-games"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "com.epicgames.EpicGamesLauncher"
      ],
      "appNames": [
        "Epic Games Launcher.app"
      ]
    },
    {
      "id": "prism-launcher",
      "name": "Prism Launcher",
      "publisher": "Prism Launcher contributors",
      "summary": "Manage multiple Minecraft: Java Edition installations.",
      "category": "gaming",
      "kind": "app",
      "website": "https://prismlauncher.org",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "prismlauncher"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "org.prismlauncher.PrismLauncher"
      ],
      "appNames": [
        "Prism Launcher.app"
      ],
      "notes": [
        "Playing requires a Microsoft account that owns Minecraft: Java Edition."
      ]
    },
    {
      "id": "firefox",
      "name": "Firefox",
      "publisher": "Mozilla",
      "summary": "A fast, private web browser from a non-profit.",
      "category": "browsers",
      "kind": "app",
      "website": "https://www.mozilla.org/firefox/",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "firefox"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "org.mozilla.firefox"
      ],
      "appNames": [
        "Firefox.app"
      ]
    },
    {
      "id": "google-chrome",
      "name": "Google Chrome",
      "publisher": "Google",
      "summary": "Google’s web browser.",
      "category": "browsers",
      "kind": "app",
      "website": "https://www.google.com/chrome/",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "google-chrome"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.google.Chrome"
      ],
      "appNames": [
        "Google Chrome.app"
      ]
    },
    {
      "id": "brave-browser",
      "name": "Brave",
      "publisher": "Brave Software",
      "summary": "A privacy-focused browser that blocks ads and trackers by default.",
      "category": "browsers",
      "kind": "app",
      "website": "https://brave.com",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "brave-browser"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.brave.Browser"
      ],
      "appNames": [
        "Brave Browser.app"
      ]
    },
    {
      "id": "arc",
      "name": "Arc",
      "publisher": "The Browser Company",
      "summary": "A browser that organises tabs into spaces in a sidebar.",
      "category": "browsers",
      "kind": "app",
      "website": "https://arc.net",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "arc"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "company.thebrowser.Browser"
      ],
      "appNames": [
        "Arc.app"
      ]
    },
    {
      "id": "microsoft-edge",
      "name": "Microsoft Edge",
      "publisher": "Microsoft",
      "summary": "Microsoft’s web browser.",
      "category": "browsers",
      "kind": "app",
      "website": "https://www.microsoft.com/edge",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "microsoft-edge"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.microsoft.edgemac"
      ],
      "appNames": [
        "Microsoft Edge.app"
      ]
    },
    {
      "id": "figma",
      "name": "Figma",
      "publisher": "Figma",
      "summary": "Design interfaces and collaborate with your team.",
      "category": "design",
      "kind": "app",
      "website": "https://www.figma.com/downloads/",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "figma"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "com.figma.Desktop"
      ],
      "appNames": [
        "Figma.app"
      ]
    },
    {
      "id": "gimp",
      "name": "GIMP",
      "publisher": "The GIMP Team",
      "summary": "A free, open-source image editor.",
      "category": "design",
      "kind": "app",
      "website": "https://www.gimp.org",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "gimp"
      },
      "requiresAccount": false,
      "appNames": [
        "GIMP.app"
      ]
    },
    {
      "id": "inkscape",
      "name": "Inkscape",
      "publisher": "Inkscape Project",
      "summary": "Create and edit vector illustrations.",
      "category": "design",
      "kind": "app",
      "website": "https://inkscape.org",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "inkscape"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "org.inkscape.Inkscape"
      ],
      "appNames": [
        "Inkscape.app"
      ]
    },
    {
      "id": "blender",
      "name": "Blender",
      "publisher": "Blender Foundation",
      "summary": "Create 3D models, animation, and visual effects.",
      "category": "design",
      "kind": "app",
      "website": "https://www.blender.org",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "blender"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "org.blenderfoundation.blender"
      ],
      "appNames": [
        "Blender.app"
      ]
    },
    {
      "id": "pixelmator-pro",
      "name": "Pixelmator Pro",
      "publisher": "Pixelmator Team",
      "summary": "A professional image editor designed for Mac.",
      "category": "design",
      "kind": "app",
      "website": "https://www.pixelmator.com/pro/",
      "pricing": "paid",
      "install": {
        "method": "appStore",
        "url": "macappstore://itunes.apple.com/app/id1289583905"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "com.pixelmatorteam.pixelmator.x"
      ],
      "appNames": [
        "Pixelmator Pro.app"
      ]
    },
    {
      "id": "rectangle",
      "name": "Rectangle",
      "publisher": "Ryan Hanson",
      "summary": "Snap and resize windows with keyboard shortcuts.",
      "category": "utilities",
      "kind": "app",
      "website": "https://rectangleapp.com",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "rectangle"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.knollsoft.Rectangle"
      ],
      "appNames": [
        "Rectangle.app"
      ],
      "notes": [
        "Needs Accessibility permission in System Settings to move windows."
      ]
    },
    {
      "id": "the-unarchiver",
      "name": "The Unarchiver",
      "publisher": "MacPaw",
      "summary": "Open ZIP, RAR, 7z, and many other archive formats.",
      "category": "utilities",
      "kind": "app",
      "website": "https://theunarchiver.com",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "the-unarchiver"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.macpaw.site.theunarchiver"
      ],
      "appNames": [
        "The Unarchiver.app"
      ]
    },
    {
      "id": "raycast",
      "name": "Raycast",
      "publisher": "Raycast",
      "summary": "A fast launcher for apps, files, commands, and extensions.",
      "category": "utilities",
      "kind": "app",
      "website": "https://www.raycast.com",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "raycast"
      },
      "bundleIdentifiers": [
        "com.raycast.macos"
      ],
      "appNames": [
        "Raycast.app"
      ]
    },
    {
      "id": "stats",
      "name": "Stats",
      "publisher": "Serhiy Mytrovtsiy",
      "summary": "See CPU, memory, disk, network, and battery in the menu bar.",
      "category": "utilities",
      "kind": "app",
      "website": "https://github.com/exelban/stats",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "stats"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "eu.exelban.Stats"
      ],
      "appNames": [
        "Stats.app"
      ]
    },
    {
      "id": "keka",
      "name": "Keka",
      "publisher": "aONe",
      "summary": "Create and extract compressed archives.",
      "category": "utilities",
      "kind": "app",
      "website": "https://www.keka.io",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "keka"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.aone.keka"
      ],
      "appNames": [
        "Keka.app"
      ]
    },
    {
      "id": "wget",
      "name": "Wget",
      "publisher": "GNU Project",
      "summary": "Download files from the web on the command line.",
      "category": "utilities",
      "kind": "commandLine",
      "website": "https://www.gnu.org/software/wget/",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "wget"
      },
      "requiresAccount": false,
      "commands": [
        "wget"
      ]
    },
    {
      "id": "notion",
      "name": "Notion",
      "publisher": "Notion Labs",
      "summary": "Notes, docs, wikis, and project planning in one workspace.",
      "category": "productivity",
      "kind": "app",
      "website": "https://www.notion.com/desktop",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "notion"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "notion.id"
      ],
      "appNames": [
        "Notion.app"
      ]
    },
    {
      "id": "obsidian",
      "name": "Obsidian",
      "publisher": "Obsidian",
      "summary": "Write and link notes stored as local Markdown files.",
      "category": "productivity",
      "kind": "app",
      "website": "https://obsidian.md",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "obsidian"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "md.obsidian"
      ],
      "appNames": [
        "Obsidian.app"
      ]
    },
    {
      "id": "libreoffice",
      "name": "LibreOffice",
      "publisher": "The Document Foundation",
      "summary": "A free office suite for documents, spreadsheets, and presentations.",
      "category": "productivity",
      "kind": "app",
      "website": "https://www.libreoffice.org",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "libreoffice"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "org.libreoffice.script"
      ],
      "appNames": [
        "LibreOffice.app"
      ]
    },
    {
      "id": "todoist",
      "name": "Todoist",
      "publisher": "Doist",
      "summary": "Organise tasks and projects across your devices.",
      "category": "productivity",
      "kind": "app",
      "website": "https://www.todoist.com/downloads",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "todoist-app"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "com.todoist.mac.Todoist"
      ],
      "appNames": [
        "Todoist.app"
      ]
    },
    {
      "id": "slack",
      "name": "Slack",
      "publisher": "Slack Technologies",
      "summary": "Team messaging, channels, and calls.",
      "category": "communication",
      "kind": "app",
      "website": "https://slack.com/downloads/mac",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "slack"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "com.tinyspeck.slackmacgap"
      ],
      "appNames": [
        "Slack.app"
      ]
    },
    {
      "id": "discord",
      "name": "Discord",
      "publisher": "Discord",
      "summary": "Voice, video, and text chat for communities and friends.",
      "category": "communication",
      "kind": "app",
      "website": "https://discord.com/download",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "discord"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "com.hnc.Discord"
      ],
      "appNames": [
        "Discord.app"
      ]
    },
    {
      "id": "zoom",
      "name": "Zoom",
      "publisher": "Zoom Communications",
      "summary": "Video meetings and calls.",
      "category": "communication",
      "kind": "app",
      "website": "https://zoom.us/download",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "zoom"
      },
      "bundleIdentifiers": [
        "us.zoom.xos"
      ],
      "appNames": [
        "zoom.us.app"
      ]
    },
    {
      "id": "signal",
      "name": "Signal",
      "publisher": "Signal Foundation",
      "summary": "Private messaging and calls with end-to-end encryption.",
      "category": "communication",
      "kind": "app",
      "website": "https://signal.org/download/",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "signal"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "org.whispersystems.signal-desktop"
      ],
      "appNames": [
        "Signal.app"
      ],
      "notes": [
        "Setup links the app to Signal on your phone."
      ]
    },
    {
      "id": "telegram",
      "name": "Telegram",
      "publisher": "Telegram",
      "summary": "Fast messaging with cloud sync across devices.",
      "category": "communication",
      "kind": "app",
      "website": "https://macos.telegram.org",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "telegram"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "ru.keepcoder.Telegram"
      ],
      "appNames": [
        "Telegram.app"
      ]
    },
    {
      "id": "whatsapp",
      "name": "WhatsApp",
      "publisher": "WhatsApp",
      "summary": "Messages and calls linked to WhatsApp on your phone.",
      "category": "communication",
      "kind": "app",
      "website": "https://www.whatsapp.com/download",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "whatsapp"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "net.whatsapp.WhatsApp"
      ],
      "appNames": [
        "WhatsApp.app"
      ]
    },
    {
      "id": "cursor",
      "name": "Cursor",
      "publisher": "Anysphere",
      "summary": "An AI-first code editor based on VS Code.",
      "category": "developer",
      "kind": "app",
      "website": "https://cursor.com",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "cursor"
      },
      "requiresAccount": true,
      "appNames": [
        "Cursor.app"
      ],
      "notes": [
        "AI features need a Cursor account; heavier use needs a paid plan."
      ]
    },
    {
      "id": "warp",
      "name": "Warp",
      "publisher": "Warp",
      "summary": "A modern terminal with blocks, completion, and AI assistance.",
      "category": "developer",
      "kind": "app",
      "website": "https://www.warp.dev",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "warp"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "dev.warp.Warp-Stable"
      ],
      "appNames": [
        "Warp.app"
      ],
      "notes": [
        "Warp requires signing in to an account on first launch."
      ]
    },
    {
      "id": "ghostty",
      "name": "Ghostty",
      "publisher": "Mitchell Hashimoto",
      "summary": "A fast, native terminal emulator.",
      "category": "developer",
      "kind": "app",
      "website": "https://ghostty.org",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "ghostty"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.mitchellh.ghostty"
      ],
      "appNames": [
        "Ghostty.app"
      ]
    },
    {
      "id": "tableplus",
      "name": "TablePlus",
      "publisher": "TablePlus",
      "summary": "A clean GUI for Postgres, MySQL, SQLite, and many other databases.",
      "category": "developer",
      "kind": "app",
      "website": "https://tableplus.com",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "tableplus"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.tinyapp.TablePlus"
      ],
      "appNames": [
        "TablePlus.app"
      ]
    },
    {
      "id": "insomnia",
      "name": "Insomnia",
      "publisher": "Kong",
      "summary": "Design, debug, and test REST and GraphQL APIs.",
      "category": "developer",
      "kind": "app",
      "website": "https://insomnia.rest",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "insomnia"
      },
      "requiresAccount": false,
      "appNames": [
        "Insomnia.app"
      ]
    },
    {
      "id": "fork",
      "name": "Fork",
      "publisher": "Dan Pristupov",
      "summary": "A fast, friendly Git client.",
      "category": "developer",
      "kind": "app",
      "website": "https://git-fork.com",
      "pricing": "paid",
      "install": {
        "method": "homebrewCask",
        "package": "fork"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.DanPristupov.Fork"
      ],
      "appNames": [
        "Fork.app"
      ],
      "notes": [
        "Free to evaluate; continued use is a one-time purchase."
      ]
    },
    {
      "id": "dbeaver-community",
      "name": "DBeaver Community",
      "publisher": "DBeaver",
      "summary": "A free, universal database tool and SQL client.",
      "category": "developer",
      "kind": "app",
      "website": "https://dbeaver.io",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "dbeaver-community"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "org.jkiss.dbeaver.core.product"
      ],
      "appNames": [
        "DBeaver.app"
      ]
    },
    {
      "id": "jq",
      "name": "jq",
      "publisher": "The jq project",
      "summary": "Query and transform JSON on the command line.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://jqlang.github.io/jq/",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "jq"
      },
      "requiresAccount": false,
      "commands": [
        "jq"
      ]
    },
    {
      "id": "bat",
      "name": "bat",
      "publisher": "sharkdp and contributors",
      "summary": "A cat replacement with syntax highlighting and Git awareness.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://github.com/sharkdp/bat",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "bat"
      },
      "requiresAccount": false,
      "commands": [
        "bat"
      ]
    },
    {
      "id": "fd",
      "name": "fd",
      "publisher": "sharkdp and contributors",
      "summary": "A fast, friendly alternative to find.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://github.com/sharkdp/fd",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "fd"
      },
      "requiresAccount": false,
      "commands": [
        "fd"
      ]
    },
    {
      "id": "fzf",
      "name": "fzf",
      "publisher": "Junegunn Choi",
      "summary": "A fuzzy finder for files, history, and command output.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://github.com/junegunn/fzf",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "fzf"
      },
      "requiresAccount": false,
      "commands": [
        "fzf"
      ],
      "notes": [
        "Shell key bindings and completions are set up separately in your shell config."
      ]
    },
    {
      "id": "htop",
      "name": "htop",
      "publisher": "htop team",
      "summary": "An interactive process viewer for the terminal.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://htop.dev",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "htop"
      },
      "requiresAccount": false,
      "commands": [
        "htop"
      ]
    },
    {
      "id": "eza",
      "name": "eza",
      "publisher": "eza community",
      "summary": "A modern ls replacement with icons, colours, and Git status.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://eza.rocks",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "eza"
      },
      "requiresAccount": false,
      "commands": [
        "eza"
      ]
    },
    {
      "id": "tmux",
      "name": "tmux",
      "publisher": "The tmux project",
      "summary": "Keep terminal sessions alive and split windows into panes.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://github.com/tmux/tmux",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "tmux"
      },
      "requiresAccount": false,
      "commands": [
        "tmux"
      ]
    },
    {
      "id": "neovim",
      "name": "Neovim",
      "publisher": "Neovim contributors",
      "summary": "A modern, extensible Vim-based editor.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://neovim.io",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "neovim"
      },
      "requiresAccount": false,
      "commands": [
        "nvim"
      ]
    },
    {
      "id": "lazygit",
      "name": "lazygit",
      "publisher": "Jesse Duffield",
      "summary": "A terminal UI for everyday Git work.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://github.com/jesseduffield/lazygit",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "lazygit"
      },
      "requiresAccount": false,
      "commands": [
        "lazygit"
      ]
    },
    {
      "id": "hyperfine",
      "name": "hyperfine",
      "publisher": "sharkdp and contributors",
      "summary": "Benchmark command-line programs.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://github.com/sharkdp/hyperfine",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "hyperfine"
      },
      "requiresAccount": false,
      "commands": [
        "hyperfine"
      ]
    },
    {
      "id": "yarn",
      "name": "Yarn",
      "publisher": "Yarn contributors",
      "summary": "A package manager for JavaScript projects.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://yarnpkg.com",
      "pricing": "free",
      "install": {
        "method": "npm",
        "package": "yarn"
      },
      "requiresAccount": false,
      "commands": [
        "yarn"
      ]
    },
    {
      "id": "prettier",
      "name": "Prettier",
      "publisher": "Prettier contributors",
      "summary": "An opinionated code formatter.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://prettier.io",
      "pricing": "free",
      "install": {
        "method": "npm",
        "package": "prettier"
      },
      "requiresAccount": false,
      "commands": [
        "prettier"
      ]
    },
    {
      "id": "eslint",
      "name": "ESLint",
      "publisher": "OpenJS Foundation",
      "summary": "Find and fix problems in JavaScript and TypeScript code.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://eslint.org",
      "pricing": "free",
      "install": {
        "method": "npm",
        "package": "eslint"
      },
      "requiresAccount": false,
      "commands": [
        "eslint"
      ]
    },
    {
      "id": "tsx",
      "name": "tsx",
      "publisher": "privatenumber",
      "summary": "Run TypeScript files directly with Node.js.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://tsx.is",
      "pricing": "free",
      "install": {
        "method": "npm",
        "package": "tsx"
      },
      "requiresAccount": false,
      "commands": [
        "tsx"
      ]
    },
    {
      "id": "vercel-cli",
      "name": "Vercel CLI",
      "publisher": "Vercel",
      "summary": "Deploy sites and serverless functions to Vercel.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://vercel.com/docs/cli",
      "pricing": "freemium",
      "install": {
        "method": "npm",
        "package": "vercel"
      },
      "requiresAccount": true,
      "commands": [
        "vercel"
      ]
    },
    {
      "id": "wrangler",
      "name": "Wrangler",
      "publisher": "Cloudflare",
      "summary": "Build and deploy Cloudflare Workers.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://developers.cloudflare.com/workers/wrangler/",
      "pricing": "freemium",
      "install": {
        "method": "npm",
        "package": "wrangler"
      },
      "requiresAccount": true,
      "commands": [
        "wrangler"
      ]
    },
    {
      "id": "firebase-tools",
      "name": "Firebase CLI",
      "publisher": "Google",
      "summary": "Manage and deploy Firebase projects.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://firebase.google.com/docs/cli",
      "pricing": "freemium",
      "install": {
        "method": "npm",
        "package": "firebase-tools"
      },
      "requiresAccount": true,
      "commands": [
        "firebase"
      ]
    },
    {
      "id": "serve",
      "name": "serve",
      "publisher": "Vercel",
      "summary": "Serve a folder or static site locally over HTTP.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://github.com/vercel/serve",
      "pricing": "free",
      "install": {
        "method": "npm",
        "package": "serve"
      },
      "requiresAccount": false,
      "commands": [
        "serve"
      ]
    },
    {
      "id": "github-copilot-cli",
      "name": "GitHub Copilot CLI",
      "publisher": "GitHub",
      "summary": "An AI coding agent for the terminal powered by Copilot.",
      "category": "ai",
      "kind": "commandLine",
      "website": "https://github.com/github/copilot-cli",
      "pricing": "freemium",
      "install": {
        "method": "npm",
        "package": "@github/copilot"
      },
      "requiresAccount": true,
      "commands": [
        "copilot"
      ],
      "notes": [
        "Needs a GitHub account; full use requires a Copilot subscription."
      ]
    },
    {
      "id": "aider",
      "name": "aider",
      "publisher": "Paul Gauthier",
      "summary": "AI pair programming in your terminal, against your own repos.",
      "category": "ai",
      "kind": "commandLine",
      "website": "https://aider.chat",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "aider"
      },
      "requiresAccount": true,
      "commands": [
        "aider"
      ],
      "notes": [
        "The tool is free; it needs an API key for an AI provider such as OpenAI or Anthropic."
      ]
    },
    {
      "id": "jan",
      "name": "Jan",
      "publisher": "Jan",
      "summary": "Run open AI models locally with a simple desktop app.",
      "category": "ai",
      "kind": "app",
      "website": "https://jan.ai",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "jan"
      },
      "requiresAccount": false,
      "appNames": [
        "Jan.app"
      ],
      "notes": [
        "Models are downloaded separately and can use many gigabytes."
      ]
    },
    {
      "id": "tidal",
      "name": "TIDAL",
      "publisher": "TIDAL",
      "summary": "High-fidelity music streaming.",
      "category": "audio",
      "kind": "app",
      "website": "https://tidal.com",
      "pricing": "paid",
      "install": {
        "method": "homebrewCask",
        "package": "tidal"
      },
      "requiresAccount": true,
      "appNames": [
        "TIDAL.app"
      ]
    },
    {
      "id": "eqmac",
      "name": "eqMac",
      "publisher": "Bitgapp",
      "summary": "A system-wide audio equalizer for your Mac.",
      "category": "audio",
      "kind": "app",
      "website": "https://eqmac.app",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "eqmac"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.bitgapp.eqmac"
      ],
      "appNames": [
        "eqMac.app"
      ]
    },
    {
      "id": "soundsource",
      "name": "SoundSource",
      "publisher": "Rogue Amoeba",
      "summary": "Control audio per app, with effects and routing.",
      "category": "audio",
      "kind": "app",
      "website": "https://rogueamoeba.com/soundsource/",
      "pricing": "paid",
      "install": {
        "method": "homebrewCask",
        "package": "soundsource"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.rogueamoeba.soundsource"
      ],
      "appNames": [
        "SoundSource.app"
      ]
    },
    {
      "id": "loopback",
      "name": "Loopback",
      "publisher": "Rogue Amoeba",
      "summary": "Create virtual audio devices to route sound between apps.",
      "category": "audio",
      "kind": "app",
      "website": "https://rogueamoeba.com/loopback/",
      "pricing": "paid",
      "install": {
        "method": "homebrewCask",
        "package": "loopback"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.rogueamoeba.Loopback"
      ],
      "appNames": [
        "Loopback.app"
      ]
    },
    {
      "id": "mpv",
      "name": "mpv",
      "publisher": "mpv contributors",
      "summary": "A minimal, highly configurable media player.",
      "category": "video",
      "kind": "app",
      "website": "https://mpv.io",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "stolendata-mpv"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "io.mpv"
      ],
      "appNames": [
        "mpv.app"
      ]
    },
    {
      "id": "shotcut",
      "name": "Shotcut",
      "publisher": "Meltytech",
      "summary": "A free, cross-platform video editor.",
      "category": "video",
      "kind": "app",
      "website": "https://www.shotcut.org",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "shotcut"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.meltytech.Shotcut"
      ],
      "appNames": [
        "Shotcut.app"
      ]
    },
    {
      "id": "minecraft",
      "name": "Minecraft Launcher",
      "publisher": "Mojang",
      "summary": "Install and play Minecraft: Java Edition and Bedrock.",
      "category": "gaming",
      "kind": "app",
      "website": "https://www.minecraft.net",
      "pricing": "paid",
      "install": {
        "method": "homebrewCask",
        "package": "minecraft"
      },
      "requiresAccount": true,
      "appNames": [
        "Minecraft Launcher.app"
      ],
      "notes": [
        "Playing requires a Microsoft account that owns the game."
      ]
    },
    {
      "id": "heroic",
      "name": "Heroic Games Launcher",
      "publisher": "Heroic Games Launcher contributors",
      "summary": "An open-source launcher for Epic, GOG, and Amazon games.",
      "category": "gaming",
      "kind": "app",
      "website": "https://heroicgameslauncher.com",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "heroic"
      },
      "requiresAccount": true,
      "appNames": [
        "Heroic.app"
      ]
    },
    {
      "id": "gog-galaxy",
      "name": "GOG GALAXY",
      "publisher": "GOG",
      "summary": "Manage and play DRM-free games from GOG.",
      "category": "gaming",
      "kind": "app",
      "website": "https://www.gog.com/galaxy",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "gog-galaxy"
      },
      "requiresAccount": true,
      "appNames": [
        "GOG GALAXY.app"
      ]
    },
    {
      "id": "openemu",
      "name": "OpenEmu",
      "publisher": "OpenEmu Team",
      "summary": "A polished retro game emulator front-end.",
      "category": "gaming",
      "kind": "app",
      "website": "https://openemu.org",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "openemu"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "org.openemu.OpenEmu"
      ],
      "appNames": [
        "OpenEmu.app"
      ],
      "notes": [
        "Game ROMs are not included; you supply your own."
      ]
    },
    {
      "id": "battle-net",
      "name": "Battle.net",
      "publisher": "Blizzard Entertainment",
      "summary": "Install and play Blizzard games like Diablo and Overwatch.",
      "category": "gaming",
      "kind": "app",
      "website": "https://www.blizzard.com/apps/battle.net/desktop",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "battle-net"
      },
      "requiresAccount": true,
      "appNames": [
        "Battle.net.app"
      ]
    },
    {
      "id": "tor-browser",
      "name": "Tor Browser",
      "publisher": "The Tor Project",
      "summary": "Browse privately through the Tor network.",
      "category": "browsers",
      "kind": "app",
      "website": "https://www.torproject.org/download/",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "tor-browser"
      },
      "requiresAccount": false,
      "appNames": [
        "Tor Browser.app"
      ]
    },
    {
      "id": "vivaldi",
      "name": "Vivaldi",
      "publisher": "Vivaldi Technologies",
      "summary": "A highly customizable browser with built-in mail and calendar.",
      "category": "browsers",
      "kind": "app",
      "website": "https://vivaldi.com",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "vivaldi"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.vivaldi.Vivaldi"
      ],
      "appNames": [
        "Vivaldi.app"
      ]
    },
    {
      "id": "opera",
      "name": "Opera",
      "publisher": "Opera",
      "summary": "A browser with a sidebar, workspaces, and a built-in VPN.",
      "category": "browsers",
      "kind": "app",
      "website": "https://www.opera.com",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "opera"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.operasoftware.Opera"
      ],
      "appNames": [
        "Opera.app"
      ]
    },
    {
      "id": "zen",
      "name": "Zen Browser",
      "publisher": "Zen Browser contributors",
      "summary": "A Firefox-based browser with workspaces and a calmer interface.",
      "category": "browsers",
      "kind": "app",
      "website": "https://zen-browser.app",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "zen"
      },
      "requiresAccount": false
    },
    {
      "id": "krita",
      "name": "Krita",
      "publisher": "Krita Foundation",
      "summary": "A free digital painting and illustration app.",
      "category": "design",
      "kind": "app",
      "website": "https://krita.org",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "krita"
      },
      "requiresAccount": false,
      "appNames": [
        "krita.app"
      ]
    },
    {
      "id": "sketch",
      "name": "Sketch",
      "publisher": "Sketch",
      "summary": "Interface design and prototyping for Mac.",
      "category": "design",
      "kind": "app",
      "website": "https://www.sketch.com",
      "pricing": "paid",
      "install": {
        "method": "homebrewCask",
        "package": "sketch"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "com.bohemiancoding.sketch3"
      ],
      "appNames": [
        "Sketch.app"
      ]
    },
    {
      "id": "alfred",
      "name": "Alfred",
      "publisher": "Running with Crayons",
      "summary": "A launcher and automation app for searching and shortcuts.",
      "category": "utilities",
      "kind": "app",
      "website": "https://www.alfredapp.com",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "alfred"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.runningwithcrayons.Alfred"
      ],
      "appNames": [
        "Alfred 5.app"
      ],
      "notes": [
        "The core launcher is free; Powerpack features need a paid licence."
      ]
    },
    {
      "id": "karabiner-elements",
      "name": "Karabiner-Elements",
      "publisher": "Takayama Fumihiko",
      "summary": "Remap keys and customize your keyboard.",
      "category": "utilities",
      "kind": "app",
      "website": "https://karabiner-elements.pqrs.org",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "karabiner-elements"
      },
      "requiresAccount": false,
      "appNames": [
        "Karabiner-Elements.app"
      ],
      "notes": [
        "Needs Input Monitoring and a driver extension approval in System Settings."
      ]
    },
    {
      "id": "maccy",
      "name": "Maccy",
      "publisher": "Alexey Rodionov",
      "summary": "A lightweight clipboard manager that stays out of the way.",
      "category": "utilities",
      "kind": "app",
      "website": "https://maccy.app",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "maccy"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "org.p0deje.Maccy"
      ],
      "appNames": [
        "Maccy.app"
      ]
    },
    {
      "id": "alt-tab",
      "name": "AltTab",
      "publisher": "Louis Pontoise",
      "summary": "Windows-style window switching with previews.",
      "category": "utilities",
      "kind": "app",
      "website": "https://alt-tab-macos.netlify.app",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "alt-tab"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.lwouis.alt-tab-macos"
      ],
      "appNames": [
        "AltTab.app"
      ],
      "notes": [
        "Needs Screen Recording and Accessibility permissions to show window previews."
      ]
    },
    {
      "id": "monitorcontrol",
      "name": "MonitorControl",
      "publisher": "MonitorControl contributors",
      "summary": "Adjust brightness and volume on external displays.",
      "category": "utilities",
      "kind": "app",
      "website": "https://github.com/MonitorControl/MonitorControl",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "monitorcontrol"
      },
      "requiresAccount": false,
      "appNames": [
        "MonitorControl.app"
      ]
    },
    {
      "id": "pearcleaner",
      "name": "Pearcleaner",
      "publisher": "Alin Lupascu",
      "summary": "An open-source app uninstaller and leftover cleaner.",
      "category": "utilities",
      "kind": "app",
      "website": "https://github.com/alienator88/Pearcleaner",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "pearcleaner"
      },
      "requiresAccount": false,
      "appNames": [
        "Pearcleaner.app"
      ]
    },
    {
      "id": "itsycal",
      "name": "Itsycal",
      "publisher": "Mowglii",
      "summary": "A small calendar that lives in the menu bar.",
      "category": "utilities",
      "kind": "app",
      "website": "https://www.mowglii.com/itsycal/",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "itsycal"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.mowglii.ItsycalApp"
      ],
      "appNames": [
        "Itsycal.app"
      ]
    },
    {
      "id": "appcleaner",
      "name": "AppCleaner",
      "publisher": "FreeMacSoft",
      "summary": "Drag an app in to remove it and its support files.",
      "category": "utilities",
      "kind": "app",
      "website": "https://freemacsoft.net/appcleaner/",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "appcleaner"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "net.freemacsoft.AppCleaner"
      ],
      "appNames": [
        "AppCleaner.app"
      ]
    },
    {
      "id": "latest",
      "name": "Latest",
      "publisher": "Max Langer",
      "summary": "Check all your apps for updates in one place.",
      "category": "utilities",
      "kind": "app",
      "website": "https://max.codes/latest",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "latest"
      },
      "requiresAccount": false,
      "appNames": [
        "Latest.app"
      ]
    },
    {
      "id": "cyberduck",
      "name": "Cyberduck",
      "publisher": "iterate GmbH",
      "summary": "Browse FTP, SFTP, S3, and other remote storage.",
      "category": "utilities",
      "kind": "app",
      "website": "https://cyberduck.io",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "cyberduck"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "ch.sudo.cyberduck"
      ],
      "appNames": [
        "Cyberduck.app"
      ]
    },
    {
      "id": "ffmpeg",
      "name": "FFmpeg",
      "publisher": "FFmpeg team",
      "summary": "Convert, record, and stream audio and video.",
      "category": "utilities",
      "kind": "commandLine",
      "website": "https://ffmpeg.org",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "ffmpeg"
      },
      "requiresAccount": false,
      "commands": [
        "ffmpeg",
        "ffprobe"
      ]
    },
    {
      "id": "yt-dlp",
      "name": "yt-dlp",
      "publisher": "yt-dlp contributors",
      "summary": "Download video and audio from thousands of sites.",
      "category": "utilities",
      "kind": "commandLine",
      "website": "https://github.com/yt-dlp/yt-dlp",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "yt-dlp"
      },
      "requiresAccount": false,
      "commands": [
        "yt-dlp"
      ],
      "notes": [
        "Only download content you have the right to keep."
      ]
    },
    {
      "id": "imagemagick",
      "name": "ImageMagick",
      "publisher": "ImageMagick Studio",
      "summary": "Convert and edit images from the command line.",
      "category": "utilities",
      "kind": "commandLine",
      "website": "https://imagemagick.org",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "imagemagick"
      },
      "requiresAccount": false,
      "commands": [
        "magick"
      ]
    },
    {
      "id": "httpie",
      "name": "HTTPie",
      "publisher": "HTTPie",
      "summary": "A friendly command-line HTTP client.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://httpie.io",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "httpie"
      },
      "requiresAccount": false,
      "commands": [
        "http",
        "https"
      ]
    },
    {
      "id": "uv",
      "name": "uv",
      "publisher": "Astral",
      "summary": "A fast Python package and project manager.",
      "category": "developer",
      "kind": "commandLine",
      "website": "https://docs.astral.sh/uv/",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "uv"
      },
      "requiresAccount": false,
      "commands": [
        "uv",
        "uvx"
      ]
    },
    {
      "id": "mas",
      "name": "mas",
      "publisher": "mas-cli contributors",
      "summary": "Install and update App Store apps from the command line.",
      "category": "utilities",
      "kind": "commandLine",
      "website": "https://github.com/mas-cli/mas",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "mas"
      },
      "requiresAccount": true,
      "commands": [
        "mas"
      ],
      "notes": [
        "Needs to be signed in to the App Store to install apps."
      ]
    },
    {
      "id": "tree",
      "name": "tree",
      "publisher": "Steve Baker",
      "summary": "List folders as a tree.",
      "category": "utilities",
      "kind": "commandLine",
      "website": "https://oldmanprogrammer.net/source.php?dir=projects/tree",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "tree"
      },
      "requiresAccount": false,
      "commands": [
        "tree"
      ]
    },
    {
      "id": "pandoc",
      "name": "Pandoc",
      "publisher": "John MacFarlane",
      "summary": "Convert documents between Markdown, HTML, PDF, and more.",
      "category": "productivity",
      "kind": "commandLine",
      "website": "https://pandoc.org",
      "pricing": "free",
      "install": {
        "method": "homebrewFormula",
        "package": "pandoc"
      },
      "requiresAccount": false,
      "commands": [
        "pandoc"
      ]
    },
    {
      "id": "anki",
      "name": "Anki",
      "publisher": "Ankitects",
      "summary": "Learn and remember with spaced-repetition flashcards.",
      "category": "productivity",
      "kind": "app",
      "website": "https://apps.ankiweb.net",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "anki"
      },
      "requiresAccount": false,
      "appNames": [
        "Anki.app"
      ]
    },
    {
      "id": "logseq",
      "name": "Logseq",
      "publisher": "Logseq",
      "summary": "A privacy-first, local Markdown outliner and knowledge base.",
      "category": "productivity",
      "kind": "app",
      "website": "https://logseq.com",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "logseq"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "com.logseq.Logseq"
      ],
      "appNames": [
        "Logseq.app"
      ]
    },
    {
      "id": "zotero",
      "name": "Zotero",
      "publisher": "Corporation for Digital Scholarship",
      "summary": "Collect, organise, and cite research sources.",
      "category": "productivity",
      "kind": "app",
      "website": "https://www.zotero.org",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "zotero"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "org.zotero.zotero"
      ],
      "appNames": [
        "Zotero.app"
      ]
    },
    {
      "id": "craft",
      "name": "Craft",
      "publisher": "Craft Docs",
      "summary": "Write and share polished documents.",
      "category": "productivity",
      "kind": "app",
      "website": "https://www.craft.do",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "craft"
      },
      "requiresAccount": true,
      "appNames": [
        "Craft.app"
      ]
    },
    {
      "id": "microsoft-office",
      "name": "Microsoft 365",
      "publisher": "Microsoft",
      "summary": "Word, Excel, PowerPoint, Outlook, and OneNote in one installer.",
      "category": "productivity",
      "kind": "app",
      "website": "https://www.microsoft.com/microsoft-365",
      "pricing": "paid",
      "install": {
        "method": "homebrewCask",
        "package": "microsoft-office"
      },
      "requiresAccount": true,
      "appNames": [
        "Microsoft Word.app",
        "Microsoft Excel.app",
        "Microsoft PowerPoint.app",
        "Microsoft Outlook.app",
        "OneNote.app"
      ],
      "notes": [
        "A Microsoft 365 subscription is needed to activate the apps after installing."
      ]
    },
    {
      "id": "notion-calendar",
      "name": "Notion Calendar",
      "publisher": "Notion Labs",
      "summary": "A calendar that connects to Notion and Google Calendar.",
      "category": "productivity",
      "kind": "app",
      "website": "https://www.notion.com/product/calendar",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "notion-calendar"
      },
      "requiresAccount": true,
      "appNames": [
        "Notion Calendar.app"
      ]
    },
    {
      "id": "microsoft-teams",
      "name": "Microsoft Teams",
      "publisher": "Microsoft",
      "summary": "Chat, meetings, and calls for work and school.",
      "category": "communication",
      "kind": "app",
      "website": "https://www.microsoft.com/microsoft-teams",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "microsoft-teams"
      },
      "requiresAccount": true,
      "appNames": [
        "Microsoft Teams.app"
      ]
    },
    {
      "id": "thunderbird",
      "name": "Thunderbird",
      "publisher": "Mozilla",
      "summary": "A free email client with calendar and RSS.",
      "category": "communication",
      "kind": "app",
      "website": "https://www.thunderbird.net",
      "pricing": "free",
      "install": {
        "method": "homebrewCask",
        "package": "thunderbird"
      },
      "requiresAccount": false,
      "bundleIdentifiers": [
        "org.mozilla.thunderbird"
      ],
      "appNames": [
        "Thunderbird.app"
      ]
    },
    {
      "id": "element",
      "name": "Element",
      "publisher": "Element",
      "summary": "Secure chat on the open Matrix network.",
      "category": "communication",
      "kind": "app",
      "website": "https://element.io",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "element"
      },
      "requiresAccount": true,
      "bundleIdentifiers": [
        "im.riot.app"
      ],
      "appNames": [
        "Element.app"
      ]
    },
    {
      "id": "proton-mail",
      "name": "Proton Mail",
      "publisher": "Proton",
      "summary": "Encrypted email from Proton.",
      "category": "communication",
      "kind": "app",
      "website": "https://proton.me/mail",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "proton-mail"
      },
      "requiresAccount": true,
      "appNames": [
        "Proton Mail.app"
      ]
    },
    {
      "id": "webex",
      "name": "Webex",
      "publisher": "Cisco",
      "summary": "Meetings, calls, and messaging.",
      "category": "communication",
      "kind": "app",
      "website": "https://www.webex.com/downloads.html",
      "pricing": "freemium",
      "install": {
        "method": "homebrewCask",
        "package": "webex"
      },
      "requiresAccount": true,
      "appNames": [
        "Webex.app"
      ]
    }
  ]
}
"""#
