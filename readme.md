# Deprecated - Global Station Search

This tool is discontinued and no longer updated as the functions are replaced using Channelidentifiarr https://github.com/egyptiangio/channelidentifiarr

A comprehensive television station search tool that (optionally) integrates with Channels DVR and Dispatcharr to provide enhanced station discovery and automated Dispatcharr field population.

## Version 2.6.0
**Feature Release (2.6.0)**
- Add lineup-based user database expansion
- Fix database status display parsing  
- Enhanced station enhancement workflow

**Bug Fix Release (2.5.4)**
- Fixed user database expansion enhancement loop
- Fixed jq syntax errors in station processing
- Fixed deduplication function return codes  
- Improved enhancement progress display

**Bug Fix Release (2.5.3)**
- Fixed Emby integration menu setup flow
- Fixed Channels DVR integration menu setup flow
- Added configure_cdvr_connection wrapper function
- Consolidated all integration configurations to use settings framework
- Fixed missing configure_*_integration function errors across all integrations

**Bug Fix Release (2.5.2)**
- Fixed Dispatcharr integration menu setup flow
- Consolidated Dispatcharr configuration to use settings framework
- Fixed missing configure_dispatcharr_integration function errors

**Bug Fix Release (2.5.1)**
- Fixed Emby integration listing provider addition failures
- Removed duplicate confirmation prompts in Emby workflow  
- Fixed database expansion memory exhaustion causing system freezes
- Improved resume functionality for interrupted database builds

**Major Update Release (2.5.0)**
- New Emby Integration submenu
- Complete Dispatcharr Channel Management System (create, edit, manage channels/groups/streams)
- Enhanced logging system with comprehensive submenu (view, configure, clear logs)
- Complete menu restructuring: Search, Dispatcharr, Emby, Settings
- Submenus also reorganized
- Updated terminology: base/user cache → base/user database
- Fixed Bash compatibility issues and modular architecture/code improvements

## Features

### No Setup Required
- **Comprehensive Base Database** - Thousands of pre-loaded stations from USA, Canada, and UK, including streaming channels
- **Search immediately**
- **Optional Expansion** - Add custom markets only if you need additional coverage

### 🔍 Search**
- **Local Database Search** - Searching happens locally, without API calls
- **Direct API Search** - Real-time queries to Channels DVR server (requires Channels DVR integration)
- **Smart Filtering** - Filter by resolution (SDTV, HDTV, UHDTV) and country
- **Logo Display** - Visual station logos (requires viu and a compatible terminal)
- **Advanced Channel Name Parsing** - Intelligent channel name analysis with auto-detection of country, resolution, and language
- **Reverse Station ID Lookup**

### 🔧 **Integrations**
- **AI-Powered Search** - Use natural language queries (e.g., "news channels in the uk") to find stations, powered by the Google Gemini API. This is available as a standalone search and within the Dispatcharr station matching workflow.
- **Dispatcharr - Complete Channel Management** - Create, edit, update, and delete channels from search results
- **Dispatcharr - Group Management** - View, create, modify, and delete channel groups
- **Dispatcharr - Stream Management** - Search, assign, and remove streams with table-based UI
- **Dispatcharr - Field Population and Station ID Matching** - Interactive and **fully automatic** matching for channels missing station IDs. Automatically populate channel name, TVG-ID, station ID, and logos
- **Emby - Populate Missing listingIds** - Automatically find any missing listingIds and add them to Emby for rich EPG data
- **Emby - Delete All Channel Numbers** - Useful for some users

### 🌍 **Market Management**
- **Granular Control** - Add specific ZIP codes/postal codes for any country
- **Smart Caching** - Incremental updates only process new markets
- **Base Database Awareness** - Automatically skips markets already covered
- **Force Refresh** - Override base database when you need specific market processing

### 🔄 **System Management**
- **Enhanced Logging** - Comprehensive logging menu with view/configure/clear options
- **Configurable Log Levels** - DEBUG, INFO, WARN, ERROR levels with file rotation
- **Backup Management** - Universal tar.gz backup format with fixed file resolution
- **Auto-Update System** - Configurable update checking and in-script management

## Requirements

### Required
- **jq** - JSON processing
- **curl** - HTTP requests
- **bash 4.0+** - Shell environment

### Optional
- **viu** - Logo previews and display
- **bc** - Progress calculations during caching
- **Google Gemini API Key** - For AI-Powered Search feature
- **Channels DVR server** - For Direct API Search and adding channels using user database
- **Dispatcharr** - For Dispatcharr integrations
- **Emby** - For Emby integrations

## Installation

1. **Download the script:**
```bash
git clone https://github.com/jesmannstl/global-channel-search
cd global-channel-search
```

2. **Make executable:**
```bash
chmod +x globalstationsearch.sh
```

3. **Install dependencies:**
```bash
# Ubuntu/Debian
sudo apt-get install jq curl

# macOS
brew install jq curl

# Optional: Logo preview support
# Install viu - https://github.com/atanunq/viu
```

## Quick Start

```bash
./globalstationsearch.sh
```

```bash
./globalstationsearch.sh --help           # Usage help
./globalstationsearch.sh --version        # Version number
./globalstationsearch.sh --version-info   # Detailed version info
```

## Contributing

This script is designed to be self-contained and user-friendly. For issues or suggestions find me on the Dispatcharr Discord.

## Version History
- **2.5.0** - Complete channel management suite, enhanced logging system, improved backup
- **2.4.0** - Full Dispatcharr channel/group/stream management, standardized styling
- **2.3.0** - Centralized logging system, modular architecture completion
- **2.2.0** - Menu restructuring, terminology updates, enhanced integration management
- **2.1.0** - Improved User Database Expansion, enhanced authentication
- **2.0.4** - Emby API fixes and bugfixes
- **2.0.0** - BREAKING: Multicountry support, lineup tracing, Emby integration
- **1.4.x** - Authentication improvements, API consolidation, auto-update system
- **1.3.x** - Enhanced Dispatcharr integration, logo workflows
- **1.2.x** - Base database overhaul, improved user database handling
- **1.0.0** - Initial release with Dispatcharr integration
