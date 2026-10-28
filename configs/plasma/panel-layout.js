// Reproduces awesome wibar, with a panel per monitor so each one shows its own tag

function createPanel(screen) {
    var panel = new Panel;
    panel.location = "top";
    panel.height = 26;
    panel.hiding = "none";
    panel.screen = screen;

    // Panel is docked to the screen edge instead of floating above windows
    panel.floating = false;

    // Opacity is read only in scripting api, so the config key is written, where 2 is opaque
    panel.currentConfigGroup = ["General"];
    panel.writeConfig("panelOpacity", 2);
    panel.reloadConfig();

    return panel;
}

// Tags are shown by name, like awesome taglist did, and without window icons
function addTagsWidget(panel) {
    var pager = panel.addWidget("org.kde.plasma.pager");

    pager.currentConfigGroup = ["General"];
    pager.writeConfig("displayedText", "Name");
    pager.writeConfig("showWindowIcons", false);
    pager.writeConfig("showOnlyCurrentScreen", true);
    pager.reloadConfig();
}

// All sensors share one widget, so the panel does not pay padding three times
function addSensorsWidget(panel, sensorIds) {
    var widget = panel.addWidget("org.kde.plasma.systemmonitor");

    widget.currentConfigGroup = ["Appearance"];
    widget.writeConfig("chartFace", "org.kde.ksysguard.textonly");
    widget.writeConfig("title", "");
    widget.writeConfig("showTitle", false);

    widget.currentConfigGroup = ["Sensors"];
    widget.writeConfig("highPrioritySensorIds", JSON.stringify(sensorIds));
    widget.writeConfig("lowPrioritySensorIds", JSON.stringify([]));
    widget.writeConfig("totalSensors", JSON.stringify([]));

    for (var i = 0; i < sensorIds.length; i++) {
        // Empty label falls back to a long sensor name, so a non breaking space leaves only the value
        widget.currentConfigGroup = ["SensorLabels"];
        widget.writeConfig(sensorIds[i], "\u00a0");

        // Color indicator has no switch to hide it, so it is painted in the panel background color
        widget.currentConfigGroup = ["SensorColors"];
        widget.writeConfig(sensorIds[i], "32,35,38");
    }

    widget.reloadConfig();
}

// Window list of the current tag, with launchers emptied so only open windows are shown
function addTasksWidget(panel) {
    var tasks = panel.addWidget("org.kde.plasma.icontasks");

    tasks.currentConfigGroup = ["General"];
    tasks.writeConfig("launchers", "");
    tasks.writeConfig("showOnlyCurrentDesktop", true);
    tasks.writeConfig("showOnlyCurrentScreen", true);
    tasks.writeConfig("groupingStrategy", 0);
    tasks.reloadConfig();
}

function addBatteryWidget(panel) {
    var battery = panel.addWidget("org.kde.plasma.battery");

    battery.currentConfigGroup = ["General"];
    battery.writeConfig("showPercentage", true);
    battery.reloadConfig();
}

function addClockWidget(panel) {
    var clock = panel.addWidget("org.kde.plasma.digitalclock");

    clock.currentConfigGroup = ["Appearance"];
    clock.writeConfig("dateFormat", "custom");
    clock.writeConfig("customDateFormat", "ddd dd MMM");
    clock.reloadConfig();
}

var existingPanels = panels();
for (var i = 0; i < existingPanels.length; i++) {
    existingPanels[i].remove();
}

for (var screen = 0; screen < screenCount; screen++) {
    var panel = createPanel(screen);

    // Application launcher, which awesome opened with the same Meta+W binding
    panel.addWidget("org.kde.plasma.kickoff");
    addTagsWidget(panel);
    addTasksWidget(panel);

    // Indicators and tray are needed once, so they live on the primary screen only
    if (screen === 0) {
        addSensorsWidget(panel, ["memory/physical/used", "cpu/all/usage", "cpu/all/averageTemperature"]);
        addBatteryWidget(panel);
        panel.addWidget("org.kde.plasma.keyboardindicator");
        panel.addWidget("org.kde.plasma.systemtray");
    }

    addClockWidget(panel);
}
