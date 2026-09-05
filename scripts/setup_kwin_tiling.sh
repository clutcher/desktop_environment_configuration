#!/bin/bash

KROHNKITE_VERSION="0.9.9.2"

# Krohnkite provides dwm like dynamic tiling, which is the closest one to awesome layouts
curl -L "https://github.com/anametologin/krohnkite/releases/download/${KROHNKITE_VERSION}/krohnkite.kwinscript" -o /tmp/krohnkite.kwinscript
kpackagetool6 --type=KWin/Script --install /tmp/krohnkite.kwinscript
kwriteconfig6 --file kwinrc --group Plugins --key krohnkiteEnabled true

# Every monitor switches desktops independently, which replaces per screen tags of awesome
kwriteconfig6 --file kwinrc --group Windows --key PerOutputVirtualDesktops true

kwriteconfig6 --file kwinrc --group Desktops --key Number 5
kwriteconfig6 --file kwinrc --group Desktops --key Rows 1
kwriteconfig6 --file kwinrc --group Desktops --key Name_1 "α"
kwriteconfig6 --file kwinrc --group Desktops --key Name_2 "β"
kwriteconfig6 --file kwinrc --group Desktops --key Name_3 "γ"
kwriteconfig6 --file kwinrc --group Desktops --key Name_4 "δ"
kwriteconfig6 --file kwinrc --group Desktops --key Name_5 "ε"

# Focus follows mouse without raising window, as it was with vi_focus disabled in awesome
kwriteconfig6 --file kwinrc --group Windows --key FocusPolicy FocusFollowsMouse
kwriteconfig6 --file kwinrc --group Windows --key AutoRaise false
kwriteconfig6 --file kwinrc --group Windows --key ClickRaise true
kwriteconfig6 --file kwinrc --group Windows --key DelayFocusInterval 0

# Pointer crosses monitor edges and corners freely, instead of being held back at them
kwriteconfig6 --file kwinrc --group EdgeBarrier --key EdgeBarrier 0
kwriteconfig6 --file kwinrc --group EdgeBarrier --key CornerBarrier false

# Hot corners for overview and the desktop grid are given ElectricNone, which is nine
kwriteconfig6 --file kwinrc --group Effect-overview --key BorderActivate 9
kwriteconfig6 --file kwinrc --group Effect-overview --key GridBorderActivate 9

# Awesome had no titlebars and one pixel borders
kwriteconfig6 --file kwinrulesrc --group General --key count 1
kwriteconfig6 --file kwinrulesrc --group General --key rules 1
kwriteconfig6 --file kwinrulesrc --group 1 --key Description "No titlebar for all windows"
kwriteconfig6 --file kwinrulesrc --group 1 --key wmclass ".*"
kwriteconfig6 --file kwinrulesrc --group 1 --key wmclassmatch 3
kwriteconfig6 --file kwinrulesrc --group 1 --key wmclasscomplete false
kwriteconfig6 --file kwinrulesrc --group 1 --key noborder true
kwriteconfig6 --file kwinrulesrc --group 1 --key noborderrule 2

# Kwin centers volume and brightness popups with no setting to move them, so a script does it
kpackagetool6 --type=KWin/Script --install configs/kwin/osd-top-right
kwriteconfig6 --file kwinrc --group Plugins --key osdtoprightEnabled true

# Only tile layout was enabled in awesome, monocle and floating are kept as fallback
kwriteconfig6 --file kwinrc --group Script-krohnkite --key tileLayoutOrder 1
kwriteconfig6 --file kwinrc --group Script-krohnkite --key monocleLayoutOrder 2
kwriteconfig6 --file kwinrc --group Script-krohnkite --key floatingLayoutOrder 3
for layout in threeColumn spiral quarter stacked columns spread stair binaryTree cascade; do
    kwriteconfig6 --file kwinrc --group Script-krohnkite --key "${layout}LayoutOrder" 0
done

# Awesome separated windows with one pixel borders, which kwin draws only with a titlebar
for gap in Left Right Top Bottom; do
    kwriteconfig6 --file kwinrc --group Script-krohnkite --key "screenGap${gap}" 0
done
kwriteconfig6 --file kwinrc --group Script-krohnkite --key screenGapBetween 2

kwriteconfig6 --file kwinrc --group Script-krohnkite --key noTileBorder true
kwriteconfig6 --file kwinrc --group Script-krohnkite --key soleWindowNoBorders true
kwriteconfig6 --file kwinrc --group Script-krohnkite --key soleWindowNoGaps true
kwriteconfig6 --file kwinrc --group Script-krohnkite --key layoutPerDesktop true

# New window is appended to the stack instead of becoming master, as awful.client.setslave did
kwriteconfig6 --file kwinrc --group Script-krohnkite --key newWindowPosition 0

# Floating rules ported from awful.rules.rules of awesome
kwriteconfig6 --file kwinrc --group Script-krohnkite --key floatingClass \
    "DTA,copyq,pinentry,Arandr,Blueman-manager,Gpick,Kruler,MessageWin,Sxiv,Tor Browser,Wpa_gui,veromix,xtightvncviewer"
kwriteconfig6 --file kwinrc --group Script-krohnkite --key ignoreTitle "Event Tester"
