#!/usr/bin/env bash
# Regenerate AIDevTools.xcodeproj from project.yml.
#
# After generation, write WorkspaceSettings.xcsettings with
# IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded=false. This stops
# Xcode from prompting "Autocreate Schemes" on every open (the project has
# many transitive Swift Package targets, so Xcode flags it as needing scheme
# autocreation unless told otherwise). XcodeGen has no native option for
# this setting, and xcshareddata is regenerated on each run, so we re-write
# it here. See:
#   https://github.com/tuist/XcodeProj/blob/main/Sources/XcodeProj/Project/WorkspaceSettings.swift
set -euo pipefail

cd "$(dirname "$0")/.."

xcodegen generate

SHARED_DIR="AIDevTools.xcodeproj/project.xcworkspace/xcshareddata"
mkdir -p "$SHARED_DIR"
cat > "$SHARED_DIR/WorkspaceSettings.xcsettings" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded</key>
	<false/>
</dict>
</plist>
PLIST
