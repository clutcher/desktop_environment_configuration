cp -rf dotfiles/* ~/.config/

START_MARKER="# BEGIN awesome-wm-config"
END_MARKER="# END awesome-wm-config"
BASH_CONFIG=$(cat <<EOT

$START_MARKER
if [ -d "\$HOME/.config/bash" ] && [ "\$(ls -A \$HOME/.config/bash)" ]; then
    for file in "\$HOME/.config/bash/.bash_"*; do
        if [ -f "\$file" ]; then
            source "\$file"
        fi
    done
fi
$END_MARKER
EOT
)

if grep -qF "$START_MARKER" ~/.bashrc; then
    sed -i "/$START_MARKER/,/$END_MARKER/d" ~/.bashrc
fi

echo "$BASH_CONFIG" >> ~/.bashrc
