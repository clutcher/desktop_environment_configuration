// Kwin centers on screen displays and has no setting for it, so the popup is moved after placement

const MARGIN = 8;

function moveToTopRight(window) {
    const area = workspace.clientArea(KWin.PlacementArea, window);
    const geometry = window.frameGeometry;
    const x = area.x + area.width - geometry.width - MARGIN;
    const y = area.y + MARGIN;

    if (geometry.x === x && geometry.y === y) {
        return;
    }

    window.frameGeometry = {x: x, y: y, width: geometry.width, height: geometry.height};
}

function keepOsdInTopRight(window) {
    if (!window.onScreenDisplay) {
        return;
    }

    moveToTopRight(window);

    // The popup is resized after it is shown, once its contents are laid out
    window.frameGeometryChanged.connect(() => moveToTopRight(window));
}

workspace.windowAdded.connect(keepOsdInTopRight);
workspace.windowList().forEach(keepOsdInTopRight);
