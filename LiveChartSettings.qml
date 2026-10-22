import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Services

PluginSettings {
    id: root
    pluginId: "liveChartSchedule"

    readonly property real outerR: Theme.cornerRadius || 12
    readonly property real innerR: 4

    function loadValue(key, def) {
        if (typeof PluginService !== "undefined" && PluginService && PluginService.loadPluginData) {
            return PluginService.loadPluginData(root.pluginId, key, def);
        }
        return def;
    }

    function saveValue(key, val) {
        if (typeof PluginService !== "undefined" && PluginService && PluginService.savePluginData) {
            PluginService.savePluginData(root.pluginId, key, val);
            if (PluginService.setGlobalVar) {
                PluginService.setGlobalVar(root.pluginId, key, val);
            }
        }
    }

    Connections {
        target: PluginService
        ignoreUnknownSignals: true
        function onPluginDataChanged(pId) {
            if (pId === root.pluginId) {
                rootWrapper.loadValue();
            }
        }
        function onGlobalVarChanged(pId, varName) {
            if (pId === root.pluginId) {
                rootWrapper.loadValue();
            }
        }
    }

    // -------------------------------------------------------------------------
    // REUSABLE COMPONENTS (Matching New DMS Full Screen Power Menu Style)
    // -------------------------------------------------------------------------

    component SectionHeader: Row {
        property string title: ""
        property string iconName: ""

        spacing: Theme.spacingXS
        leftPadding: Theme.spacingM

        DankIcon {
            name: iconName
            size: 16
            color: Theme.primary
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            text: title
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.DemiBold
            color: Theme.primary
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    component SettingsSelectItem: Rectangle {
        id: selectCard
        width: parent.width
        implicitHeight: selectCol.implicitHeight + Theme.spacingM * 2
        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.5)
        border.width: 1
        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)

        property string iconName: ""
        property string title: ""
        property string description: ""
        property string settingKey: ""
        property var defaultValue: ""
        property var options: []

        property bool isFirst: false
        property bool isLast: false
        property bool isSingle: false

        topLeftRadius: (isFirst || isSingle) ? root.outerR : root.innerR
        topRightRadius: (isFirst || isSingle) ? root.outerR : root.innerR
        bottomLeftRadius: (isLast || isSingle) ? root.outerR : root.innerR
        bottomRightRadius: (isLast || isSingle) ? root.outerR : root.innerR

        function loadValue() {
            dropdown.loadValue();
        }

        Column {
            id: selectCol
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            RowLayout {
                width: parent.width
                spacing: Theme.spacingM

                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                    Layout.alignment: Qt.AlignVCenter

                    DankIcon {
                        name: selectCard.iconName
                        size: 18
                        color: Theme.primary
                        anchors.centerIn: parent
                    }
                }

                Column {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2
                    StyledText {
                        text: selectCard.title
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }
                    StyledText {
                        text: selectCard.description
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
            }

            DankDropdown {
                id: dropdown
                width: parent.width
                options: selectCard.options.map(opt => (typeof opt === "object" ? opt.label : opt))
                property var rawOptions: selectCard.options
                property var valueMap: {
                    var map = {};
                    for (var i = 0; i < selectCard.options.length; i++) {
                        var o = selectCard.options[i];
                        if (typeof o === "object") {
                            map[o.label] = o.value;
                            map[o.value] = o.label;
                        }
                    }
                    return map;
                }

                function loadValue() {
                    var val = root.loadValue(selectCard.settingKey, selectCard.defaultValue);
                    currentValue = valueMap[val] || val;
                }

                Component.onCompleted: loadValue()

                onValueChanged: (val) => {
                    var actualVal = valueMap[val] !== undefined ? valueMap[val] : val;
                    root.saveValue(selectCard.settingKey, actualVal);
                }
            }
        }
    }

    component SettingsToggleItem: Rectangle {
        id: toggleCard
        width: parent.width
        height: 56
        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.5)
        border.width: 1
        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)

        property string iconName: ""
        property string title: ""
        property string description: ""
        property string settingKey: ""
        property bool defaultValue: false

        property bool isFirst: false
        property bool isLast: false
        property bool isSingle: false

        property alias checked: toggle.checked

        topLeftRadius: (isFirst || isSingle) ? root.outerR : root.innerR
        topRightRadius: (isFirst || isSingle) ? root.outerR : root.innerR
        bottomLeftRadius: (isLast || isSingle) ? root.outerR : root.innerR
        bottomRightRadius: (isLast || isSingle) ? root.outerR : root.innerR

        function loadValue() {
            if (root) {
                var loaded = root.loadValue(settingKey, defaultValue);
                checked = loaded === true || loaded === "true";
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingM
            spacing: Theme.spacingM

            Rectangle {
                width: 32
                height: 32
                radius: 16
                color: toggle.checked ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Qt.rgba(Theme.surfaceContainerHighest.r, Theme.surfaceContainerHighest.g, Theme.surfaceContainerHighest.b, 0.5)
                Layout.alignment: Qt.AlignVCenter
                Behavior on color { ColorAnimation { duration: 150 } }

                DankIcon {
                    name: toggleCard.iconName
                    size: 18
                    color: toggle.checked ? Theme.primary : Theme.surfaceVariantText
                    anchors.centerIn: parent
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }

            Column {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                StyledText {
                    text: toggleCard.title
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }
                StyledText {
                    text: toggleCard.description
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }

            DankToggle {
                id: toggle
                Layout.alignment: Qt.AlignVCenter
                Component.onCompleted: toggleCard.loadValue()
                onToggled: function (newChecked) {
                    root.saveValue(toggleCard.settingKey, newChecked);
                }
            }
        }
    }

    component SettingsIntervalItem: Rectangle {
        id: intervalCard
        width: parent.width
        implicitHeight: intervalCol.implicitHeight + Theme.spacingM * 2
        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.5)
        border.width: 1
        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)

        property string iconName: "refresh"
        property string title: "Update Interval"
        property string description: "How often to refresh anime schedule data (minimum 5 minutes)."

        property bool isFirst: false
        property bool isLast: false
        property bool isSingle: false

        topLeftRadius: (isFirst || isSingle) ? root.outerR : root.innerR
        topRightRadius: (isFirst || isSingle) ? root.outerR : root.innerR
        bottomLeftRadius: (isLast || isSingle) ? root.outerR : root.innerR
        bottomRightRadius: (isLast || isSingle) ? root.outerR : root.innerR

        function loadValue() {
            valInput.loadValue();
            unitDropdown.loadValue();
        }

        Column {
            id: intervalCol
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            RowLayout {
                width: parent.width
                spacing: Theme.spacingM

                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                    Layout.alignment: Qt.AlignVCenter

                    DankIcon {
                        name: intervalCard.iconName
                        size: 18
                        color: Theme.primary
                        anchors.centerIn: parent
                    }
                }

                Column {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2
                    StyledText {
                        text: intervalCard.title
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }
                    StyledText {
                        text: intervalCard.description
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
            }

            RowLayout {
                width: parent.width
                spacing: Theme.spacingM

                Rectangle {
                    Layout.preferredWidth: 90
                    height: 36
                    color: Theme.surfaceContainerHigh
                    radius: 8
                    border.color: valInput.activeFocus ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20)
                    border.width: 1

                    TextInput {
                        id: valInput
                        anchors.fill: parent
                        anchors.margins: 4
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        selectByMouse: true

                        function loadValue() {
                            text = root.loadValue("updateIntervalValue", "1");
                        }
                        Component.onCompleted: loadValue()

                        onEditingFinished: {
                            var clean = text.replace(/[^0-9.]/g, "").trim();
                            var parsed = parseFloat(clean);
                            if (!isNaN(parsed) && parsed > 0) {
                                root.saveValue("updateIntervalValue", parsed.toString());
                            } else {
                                text = "1";
                                root.saveValue("updateIntervalValue", "1");
                            }
                            focus = false;
                        }
                    }
                }

                DankDropdown {
                    id: unitDropdown
                    Layout.fillWidth: true
                    options: ["Minutes", "Hours"]
                    property var valMap: { "Minutes": "m", "Hours": "h", "m": "Minutes", "h": "Hours" }

                    function loadValue() {
                        var u = root.loadValue("updateIntervalUnit", "h");
                        currentValue = valMap[u] || "Hours";
                    }
                    Component.onCompleted: loadValue()

                    onValueChanged: (v) => {
                        root.saveValue("updateIntervalUnit", valMap[v] || "h");
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // SETTINGS LAYOUT
    // -------------------------------------------------------------------------

    Column {
        id: rootWrapper
        width: parent.width
        spacing: Theme.spacingL

        function loadValue() {
            var groups = [pillGroup, syncGroup, displayGroup, actionsGroup];
            for (var g = 0; g < groups.length; g++) {
                var group = groups[g];
                for (var i = 0; i < group.children.length; i++) {
                    var item = group.children[i];
                    if (item && item.loadValue)
                        item.loadValue();
                }
            }
        }

        // ---------------------------------------------------------------------
        // 1. DANKBAR PILL DISPLAY
        // ---------------------------------------------------------------------
        Column {
            width: parent.width
            spacing: Theme.spacingS

            SectionHeader {
                title: "DankBar Status Pill"
                iconName: "view_day"
            }

            Column {
                id: pillGroup
                width: parent.width
                spacing: 2

                SettingsSelectItem {
                    iconName: "view_day"
                    title: "Horizontal Pill Mode"
                    description: "What information to show in the Dankbar pill"
                    settingKey: "dankbarPill"
                    defaultValue: "total_count"
                    options: [
                        { label: "Total Shows", value: "total_count" },
                        { label: "Today's Shows", value: "today_count" },
                        { label: "Next Airing", value: "next_airing" },
                        { label: "Recently Aired", value: "recently_aired" },
                        { label: "Dynamic (Next / Recent)", value: "dynamic" }
                    ]
                    isFirst: true
                }

                SettingsSelectItem {
                    iconName: "format_list_numbered"
                    title: "Pill Limit"
                    description: "Number of upcoming or recent shows to display in pill"
                    settingKey: "dankbarLimit"
                    defaultValue: "1"
                    options: [
                        { label: "1 Show", value: "1" },
                        { label: "2 Shows", value: "2" },
                        { label: "3 Shows", value: "3" },
                        { label: "4 Shows", value: "4" },
                        { label: "5 Shows", value: "5" }
                    ]
                    isLast: true
                }
            }
        }

        // ---------------------------------------------------------------------
        // 2. DATA SYNC & AUTHENTICATION
        // ---------------------------------------------------------------------
        Column {
            width: parent.width
            spacing: Theme.spacingS

            SectionHeader {
                title: "Data Sync & Authentication"
                iconName: "sync"
            }

            Column {
                id: syncGroup
                width: parent.width
                spacing: 2

                SettingsSelectItem {
                    iconName: "cookie"
                    title: "Browser Session"
                    description: "Which browser's cookies to inspect for watchlist synchronization"
                    settingKey: "browser"
                    defaultValue: "firefox"
                    options: [
                        { label: "Firefox", value: "firefox" },
                        { label: "Zen Browser", value: "zen" },
                        { label: "Chrome", value: "chrome" },
                        { label: "Chrome Beta", value: "chrome_beta" }
                    ]
                    isFirst: true
                }

                SettingsIntervalItem {
                    isLast: true
                }
            }
        }

        // ---------------------------------------------------------------------
        // 3. SCHEDULE DISPLAY
        // ---------------------------------------------------------------------
        Column {
            width: parent.width
            spacing: Theme.spacingS

            SectionHeader {
                title: "Schedule Display"
                iconName: "calendar_view_week"
            }

            Column {
                id: displayGroup
                width: parent.width
                spacing: 2

                SettingsSelectItem {
                    iconName: "calendar_view_week"
                    title: "Days to Show"
                    description: "Number of schedule day columns to display in popout"
                    settingKey: "daysToShow"
                    defaultValue: "7"
                    options: [
                        { label: "1 Day", value: "1" },
                        { label: "2 Days", value: "2" },
                        { label: "3 Days", value: "3" },
                        { label: "5 Days", value: "5" },
                        { label: "7 Days", value: "7" }
                    ]
                    isFirst: true
                }

                SettingsSelectItem {
                    iconName: "event"
                    title: "Start Day"
                    description: "Which day the schedule timeline begins on"
                    settingKey: "startDay"
                    defaultValue: "0"
                    options: [
                        { label: "Day Before Yesterday", value: "-2" },
                        { label: "Yesterday", value: "-1" },
                        { label: "Today", value: "0" },
                        { label: "Tomorrow", value: "1" }
                    ]
                }

                SettingsSelectItem {
                    iconName: "schedule"
                    title: "Time Format"
                    description: "Choose between 12-hour (AM/PM) and 24-hour time display"
                    settingKey: "timeFormat"
                    defaultValue: "12h"
                    options: [
                        { label: "12 Hours (AM/PM)", value: "12h" },
                        { label: "24 Hours", value: "24h" }
                    ]
                }

                SettingsToggleItem {
                    iconName: "timer"
                    title: "Show Seconds"
                    description: "Display seconds in the popout current time highlighter"
                    settingKey: "showSeconds"
                    defaultValue: false
                    isLast: true
                }
            }
        }

        // ---------------------------------------------------------------------
        // 4. CLICK ACTIONS
        // ---------------------------------------------------------------------
        Column {
            width: parent.width
            spacing: Theme.spacingS

            SectionHeader {
                title: "Click Actions"
                iconName: "touch_app"
            }

            Column {
                id: actionsGroup
                width: parent.width
                spacing: 2

                SettingsSelectItem {
                    iconName: "touch_app"
                    title: "Anime Card Action"
                    description: "Action triggered when clicking the card background"
                    settingKey: "cardClickAction"
                    defaultValue: "anime_entry"
                    options: [
                        { label: "Disable", value: "none" },
                        { label: "Open Watch Page", value: "watch_page" },
                        { label: "Open Anime Entry", value: "anime_entry" }
                    ]
                    isFirst: true
                }

                SettingsSelectItem {
                    iconName: "image"
                    title: "Cover Poster Action"
                    description: "Action triggered when clicking an anime poster"
                    settingKey: "coverClickAction"
                    defaultValue: "anime_entry"
                    options: [
                        { label: "Disable", value: "none" },
                        { label: "Open Anime Entry", value: "anime_entry" }
                    ]
                }

                SettingsSelectItem {
                    iconName: "link"
                    title: "Watch Stream Action"
                    description: "Action triggered when clicking the streaming service button"
                    settingKey: "watchStreamClickAction"
                    defaultValue: "watch_page"
                    options: [
                        { label: "Disable", value: "none" },
                        { label: "Open Watch Page", value: "watch_page" }
                    ]
                }

                SettingsSelectItem {
                    iconName: "home"
                    title: "LiveChart.me Logo Action"
                    description: "Action triggered when clicking the header LiveChart logo"
                    settingKey: "livechartIconClickAction"
                    defaultValue: "schedule"
                    options: [
                        { label: "Open Schedule", value: "schedule" },
                        { label: "Open LiveChart Home", value: "livechart" }
                    ]
                    isLast: true
                }
            }
        }
    }
}
