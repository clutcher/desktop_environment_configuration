#!/bin/bash

# Command line tools, used by this and other plasma setup scripts
sudo apt install -y libkf6config-bin libkf6service-bin kpackagetool6 qdbus-qt6 xdg-utils

# Install login manager
sudo apt install -y sddm sddm-theme-breeze

# Install plasma desktop with wayland session
sudo apt install -y plasma-desktop plasma-workspace kwin-wayland kscreen systemsettings kde-cli-tools

# Power management
sudo apt install -y powerdevil

# Screen is never dimmed or suspended, and a long off timeout keeps the locked one working
kwriteconfig6 --file powerdevilrc --group AC --group Display --key DimDisplayWhenIdle false
kwriteconfig6 --file powerdevilrc --group AC --group Display --key DimDisplayIdleTimeoutSec -- -1
kwriteconfig6 --file powerdevilrc --group AC --group Display --key TurnOffDisplayWhenIdle true
kwriteconfig6 --file powerdevilrc --group AC --group Display --key TurnOffDisplayIdleTimeoutSec 3600
kwriteconfig6 --file powerdevilrc --group AC --group Display --key TurnOffDisplayIdleTimeoutWhenLockedSec 300
kwriteconfig6 --file powerdevilrc --group AC --group SuspendAndShutdown --key AutoSuspendAction 0
# Lid action 32 is the value written by the power management settings module
kwriteconfig6 --file powerdevilrc --group AC --group SuspendAndShutdown --key LidAction 32

# On battery the screen is dimmed after ten minutes, but still never switched off
kwriteconfig6 --file powerdevilrc --group Battery --group Display --key DimDisplayIdleTimeoutSec 600
kwriteconfig6 --file powerdevilrc --group Battery --group Display --key TurnOffDisplayWhenIdle true
kwriteconfig6 --file powerdevilrc --group Battery --group Display --key TurnOffDisplayIdleTimeoutSec 3600
kwriteconfig6 --file powerdevilrc --group Battery --group Display --key TurnOffDisplayIdleTimeoutWhenLockedSec 300
kwriteconfig6 --file powerdevilrc --group Battery --group SuspendAndShutdown --key AutoSuspendAction 0
kwriteconfig6 --file powerdevilrc --group Battery --group SuspendAndShutdown --key LidAction 32

# Power profile is fixed, so it is not switched when the power source changes
for power_profile in AC Battery LowBattery; do
    kwriteconfig6 --file powerdevilrc --group "$power_profile" --key PowerProfile performance
done

# Notification system
sudo apt install -y libnotify-bin

install -D -m 755 configs/bin/dismiss-notifications ~/.local/bin/dismiss-notifications
# Its probe notification only reveals the newest id, so it must reach neither screen nor history
kwriteconfig6 --file plasmanotifyrc --group Applications --group dismiss-notifications --key ShowPopups false
kwriteconfig6 --file plasmanotifyrc --group Applications --group dismiss-notifications --key ShowInHistory false

# File manager
sudo apt install -y dolphin ark kio-extras kdegraphics-thumbnailers ffmpegthumbs
xdg-mime default org.kde.dolphin.desktop inode/directory

# GUI for hardware connection
sudo apt install -y plasma-nm bluedevil plasma-pa

# Install terminal with the font it uses
sudo apt install -y konsole fonts-jetbrains-mono

# Install screenshot tool
sudo apt install -y kde-spectacle

# Image, document and video viewers
sudo apt install -y gwenview okular haruna

# Text editor, calculator, disk usage and system monitor
sudo apt install -y kate kcalc filelight plasma-systemmonitor

# Printing, as a system settings module and a panel widget
sudo apt install -y print-manager

# Password storage, unlocked on login, with ssh agent integration
sudo apt install -y kwalletmanager libpam-kwallet5 ksshaskpass

# Additional widgets for panel
sudo apt install -y plasma-widgets-addons

# Portal and theming of gtk applications
sudo apt install -y xdg-desktop-portal-kde kde-config-gtk-style breeze-gtk-theme

# Set sddm as display manager
echo "/usr/bin/sddm" | sudo tee /etc/X11/default-display-manager > /dev/null
sudo systemctl enable sddm

# Sddm reads the wallpaper as its own user, so the image lives outside the home directory
sudo install -D -m 644 configs/wallpaper/wall.png /usr/share/wallpapers/wall.png
# Shipped theme.conf is written directly, and an sddm-theme-breeze upgrade resets it
sudo kwriteconfig6 --file /usr/share/sddm/themes/breeze/theme.conf \
    --group General --key background /usr/share/wallpapers/wall.png

# Unlock wallet with login password
sudo pam-auth-update --enable kde-kwallet

# Setup theme and icons
kwriteconfig6 --file kdeglobals --group General --key ColorScheme BreezeDark
kwriteconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage org.kde.breezedark.desktop
kwriteconfig6 --file plasmarc --group Theme --key name breeze-dark

# Setup keyboard layouts with switch on caps lock
kwriteconfig6 --file kxkbrc --group Layout --key Use true
kwriteconfig6 --file kxkbrc --group Layout --key LayoutList "us,ru"
kwriteconfig6 --file kxkbrc --group Layout --key VariantList ","
kwriteconfig6 --file kxkbrc --group Layout --key Options "grp:caps_toggle"
kwriteconfig6 --file kxkbrc --group Layout --key ResetOldOptions true

# Store screenshots with the same name pattern as awesome did
mkdir -p ~/screenshots
kwriteconfig6 --file spectaclerc --group General --key autoSaveImage true
kwriteconfig6 --file spectaclerc --group General --key showCaptureInstructions false
kwriteconfig6 --file spectaclerc --group ImageSave --key imageSaveLocation "file://$HOME/screenshots"
kwriteconfig6 --file spectaclerc --group ImageSave --key imageFilenameTemplate "<yyyy>-<MM>-<dd>_<HH>-<mm>-<ss>"

# Lock screen uses the same wallpaper, so it stays in the same tone
kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin org.kde.image
kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image \
    --group General --key Image "file://$HOME/.local/share/wallpapers/wall.png"

# Konsole profile reuses colors of alacritty theme, which is a port of konsole one
mkdir -p ~/.local/share/konsole
cp -rf configs/konsole/* ~/.local/share/konsole/
kwriteconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile "Clutcher.profile"
kwriteconfig6 --file konsolerc --group KonsoleWindow --key ShowMenuBarByDefault false
# Konsole saves menubar state per window, which wins over the default above
kwriteconfig6 --file konsolerc --group MainWindow --key MenuBar Disabled
kwriteconfig6 --file konsolerc --group TabBar --key TabBarVisibility ShowTabBarWhenNeeded

# Every installed runner is switched off first, so an unknown one does not stay on by default
__installed_krunner_runners=$(
    # Plugin id is the file name of a binary runner, X-KDE-PluginInfo-Name of a dbus one
    find /usr/lib/*/qt6/plugins/kf6/krunner -maxdepth 1 -name '*.so' -printf '%f\n' | sed 's/\.so$//'
    grep -h '^X-KDE-PluginInfo-Name=' /usr/share/krunner/dbusplugins/*.desktop | cut -d= -f2
)
for krunner_runner in $__installed_krunner_runners; do
    kwriteconfig6 --file krunnerrc --group Plugins --key "${krunner_runner}Enabled" false
done
unset __installed_krunner_runners

for krunner_runner in krunner_services krunner_systemsettings krunner_sessions; do
    kwriteconfig6 --file krunnerrc --group Plugins --key "${krunner_runner}Enabled" true
done

# Every invocation starts on an empty query instead of the previous search
kwriteconfig6 --file krunnerrc --group General --key RetainPriorSearch false

# Same file twice: kglobalaccel folder defines the shortcut, applications folder launches it
mkdir -p ~/.local/share/kglobalaccel/
cp -rf configs/kglobalaccel/* ~/.local/share/kglobalaccel/
cp -rf configs/kglobalaccel/* ~/.local/share/applications/

kbuildsycoca6 --noincremental
