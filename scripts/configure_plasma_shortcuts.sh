#!/bin/bash

function __set_shortcut() {
    local group="$1"
    local action="$2"
    local shortcut="$3"

    kwriteconfig6 --file kglobalshortcutsrc --group "$group" --key "$action" "$shortcut,none,$action"
}

function __clear_shortcut() {
    local group="$1"
    local action="$2"

    kwriteconfig6 --file kglobalshortcutsrc --group "$group" --key "$action" "none,none,$action"
}

# Service groups hold a bare list of keys, unlike component groups with default and name fields
function __set_service_shortcut() {
    local desktop_file="$1"
    local action="$2"
    local shortcut="$3"

    kwriteconfig6 --file kglobalshortcutsrc --group services --group "$desktop_file" --key "$action" "$shortcut"
}

# Plasma binds Meta with digit on task manager entries, while awesome used it for tags
for entry in {1..10}; do
    __clear_shortcut plasmashell "activate task manager entry $entry"
done

# Krohnkite ships own defaults, which overlap with awesome ones
for action in BTreeLayout ColumnsLayout Decrease FloatAll FloatingLayout FocusDown FocusLeft \
    FocusNext FocusPrev FocusRight FocusUp GrowHeight Increase MonocleLayout NextLayout \
    PreviousLayout QuarterLayout Rotate RotatePart SetMaster ShiftDown ShiftLeft ShiftRight \
    ShiftUp ShrinkHeight ShrinkWidth SpiralLayout SpreadLayout StackedLayout StairLayout \
    TileLayout ToggleFloat TreeColumnLayout growWidth toggleDock; do
    __clear_shortcut kwin "Krohnkite$action"
done

# Plasma defaults, which occupy keys taken by awesome bindings
__clear_shortcut kwin "Overview"
__clear_shortcut kwin "Window Quick Tile Left"
__clear_shortcut kwin "Window Quick Tile Right"
__clear_shortcut kwin "Edit Tiles"
__clear_shortcut kwin "Walk Through Windows of Current Application"
__clear_shortcut kwin "Show Desktop"

# Power profile switching keeps its hardware key and gives up Meta+B
__set_shortcut org_kde_powerdevil "powerProfile" "Battery"

# Spectacle keeps recording and its own launcher on the keys awesome did not use
__set_service_shortcut "org.kde.spectacle.desktop" "RecordRegion" "Meta+Shift+R"
__set_service_shortcut "org.kde.spectacle.desktop" "_launch" "Meta+Shift+S"
__set_service_shortcut "org.kde.spectacle.desktop" "ActiveWindowScreenShot" "none"

# System monitor ships Meta+Esc, spelled Esc not Escape, which awesome used for the next screen
__set_service_shortcut "org.kde.plasma-systemmonitor.desktop" "_launch" "Meta+S"

# Tags
for tag in {1..5}; do
    __set_shortcut kwin "Switch to Desktop $tag" "Meta+$tag"
    __set_shortcut kwin "Window to Desktop $tag" "Meta+Shift+$tag"
done
__set_shortcut kwin "Switch One Desktop to the Left" "Meta+Left"
__set_shortcut kwin "Switch One Desktop to the Right" "Meta+Right"

# Kwin gives zero to the primary monitor, so the middle one is screen 0, left 1 and right 2
__set_shortcut kwin "Switch to Screen 1" "Ctrl+1"
__set_shortcut kwin "Switch to Screen 0" "Ctrl+2"
__set_shortcut kwin "Switch to Screen 2" "Ctrl+3"
__set_shortcut kwin "Switch to Next Screen" 'Meta+`'
__set_shortcut kwin "Switch to Previous Screen" "Meta+Ctrl+K"
__set_shortcut kwin "Window to Next Screen" "Meta+Esc"

# Tiling
__set_shortcut kwin "KrohnkiteFocusNext" "Meta+J"
__set_shortcut kwin "KrohnkiteFocusPrev" "Meta+K"
__set_shortcut kwin "KrohnkiteShiftDown" "Meta+Shift+J"
__set_shortcut kwin "KrohnkiteShiftUp" "Meta+Shift+K"
__set_shortcut kwin "KrohnkitegrowWidth" "Alt+Shift+L"
__set_shortcut kwin "KrohnkiteShrinkWidth" "Alt+Shift+H"
__set_shortcut kwin "KrohnkiteIncrease" "Meta+Shift+H"
__set_shortcut kwin "KrohnkiteDecrease" "Meta+Shift+L"
__set_shortcut kwin "KrohnkiteNextLayout" "Meta+Space"
__set_shortcut kwin "KrohnkitePreviousLayout" "Meta+Shift+Space"
__set_shortcut kwin "KrohnkiteSetMaster" "Meta+Ctrl+Return"
__set_shortcut kwin "KrohnkiteToggleFloat" "Meta+Ctrl+Space"

# Window manipulation
__set_shortcut kwin "Window Fullscreen" "Meta+F"
__set_shortcut kwin "Window Maximize" "Meta+M"
__set_shortcut kwin "Window Minimize" "Meta+N"
__set_shortcut kwin "Window Above Other Windows" "Meta+T"
__set_shortcut kwin "Window Close" "Meta+Shift+C"
__set_shortcut kwin "Walk Through Windows" "Meta+Tab"
__set_shortcut kwin "Activate Window Demanding Attention" "Meta+U"

# Launchers
__set_service_shortcut "terminal.desktop" "_launch" "Meta+Return"
__set_service_shortcut "browser.desktop" "_launch" "Meta+B"
__set_service_shortcut "org.kde.krunner.desktop" "_launch" "Meta+R"
__set_shortcut plasmashell "activate application launcher" "Meta+W"
__set_shortcut ksmserver "Lock Session" "Meta+L"

# Notifications without a timeout, as chrome sends them, otherwise stay until closed by hand
__set_service_shortcut "dismiss-notifications.desktop" "_launch" "Meta+D"

# Screenshots. Region capture takes the print key, as it is the one that opens the annotation tools
__set_service_shortcut "org.kde.spectacle.desktop" "RectangularRegionScreenShot" "Print"
__set_service_shortcut "org.kde.spectacle.desktop" "FullScreenScreenShot" "Meta+Print"
__set_service_shortcut "org.kde.spectacle.desktop" "WindowUnderCursorScreenShot" "Meta+Shift+Print"

unset -f __set_shortcut
unset -f __clear_shortcut
unset -f __set_service_shortcut
