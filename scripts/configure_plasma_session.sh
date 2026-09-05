#!/bin/bash

# Session starts empty, so applications from a previous login are not restored
kwriteconfig6 --file ksmserverrc --group General --key loginMode emptySession

# Splash screen between login and desktop is not needed
kwriteconfig6 --file ksplashrc --group KSplash --key Engine none
kwriteconfig6 --file ksplashrc --group KSplash --key Theme None

mkdir -p ~/.config/autostart
cp -rf configs/autostart/* ~/.config/autostart/

# Panel is applied on first login, because plasma scripting api needs a running plasmashell
mkdir -p ~/.local/share/plasma-panel
cp configs/plasma/panel-layout.js ~/.local/share/plasma-panel/layout.js

# Wallpaper is the one awesome used, kept in repo, as its theme is no longer cloned
mkdir -p ~/.local/share/wallpapers
cp configs/wallpaper/wall.png ~/.local/share/wallpapers/wall.png

cat <<'EOT' > ~/.local/share/plasma-panel/apply-layout.sh
#!/bin/bash

layout=$(cat ~/.local/share/plasma-panel/layout.js)

# Plasmashell needs a moment to claim its dbus name after login
for attempt in {1..30}; do
    if qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$layout"; then
        # Containment type is read only in scripting api, so it is written with plasmashell stopped
        desktop_ids=$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
            'var d = desktops(); var ids = []; for (var i = 0; i < d.length; i++) ids.push(d[i].id); print(ids.join(" "));')
        systemctl --user stop plasma-plasmashell.service
        for desktop_id in $desktop_ids; do
            kwriteconfig6 --file plasma-org.kde.plasma.desktop-appletsrc \
                --group Containments --group "$desktop_id" --key plugin org.kde.desktopcontainment
        done
        systemctl --user start plasma-plasmashell.service

        # Wallpaper is applied last, when plasmashell is up again with the new containment
        for wallpaper_attempt in {1..30}; do
            plasma-apply-wallpaperimage ~/.local/share/wallpapers/wall.png && break
            sleep 2
        done

        rm -f ~/.config/autostart/apply-panel-layout.desktop
        exit 0
    fi
    sleep 2
done

exit 1
EOT
chmod +x ~/.local/share/plasma-panel/apply-layout.sh

cat <<EOT > ~/.config/autostart/apply-panel-layout.desktop
[Desktop Entry]
Type=Application
Name=Apply panel layout
Exec=$HOME/.local/share/plasma-panel/apply-layout.sh
StartupNotify=false
Terminal=false
X-KDE-autostart-after=panel
EOT
