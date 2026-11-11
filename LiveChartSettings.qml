import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Modules.Settings.Widgets
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
                }

                SettingsToggleItem {
                    iconName: "info"
                    title: "Show Scheduling Notices"
                    description: "Display announcement and schedule delay cards in the timeline"
                    settingKey: "showInfoNotes"
                    defaultValue: true
                }

                SettingsToggleItem {
                    id: customStatusFilterToggle
                    iconName: "filter_list"
                    title: "Custom Schedule Status Filter"
                    description: "Filter visible anime by watch status independently of website schedule settings"
                    settingKey: "useCustomStatusFilter"
                    defaultValue: false
                    isLast: !checked

                    Behavior on bottomLeftRadius { NumberAnimation { duration: 150 } }
                    Behavior on bottomRightRadius { NumberAnimation { duration: 150 } }
                }

                // Expandable Status Visibility Grid (matching DMS-DNS_Switcher Provider Visibility)
                Item {
                    id: statusVisContainer
                    width: parent.width
                    property bool expanded: customStatusFilterToggle.checked
                    height: expanded ? visInnerRect.implicitHeight : 0
                    opacity: expanded ? 1.0 : 0.0
                    visible: height > 0 || expanded
                    clip: true

                    Behavior on height {
                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
                    }

                    property var statusList: ["watching", "rewatching", "planning", "considering"]

                    function loadValue() {
                        let saved = root.loadValue("customStatusList", null);
                        if (saved) {
                            try {
                                statusVisContainer.statusList = JSON.parse(saved);
                            } catch (e) {
                                statusVisContainer.statusList = ["watching", "rewatching", "planning", "considering"];
                            }
                        } else {
                            statusVisContainer.statusList = ["watching", "rewatching", "planning", "considering"];
                        }
                    }

                    Component.onCompleted: loadValue()

                    Rectangle {
                        id: visInnerRect
                        width: parent.width
                        implicitHeight: visInnerCol.implicitHeight + Theme.spacingM * 2
                        radius: root.innerR
                        bottomLeftRadius: root.outerR
                        bottomRightRadius: root.outerR
                        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.5)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)

                        Column {
                            id: visInnerCol
                            width: parent.width - Theme.spacingM * 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: Theme.spacingM
                            spacing: Theme.spacingM

                            RowLayout {
                                width: parent.width
                                spacing: Theme.spacingS

                                StyledText {
                                    text: "Select which anime statuses appear in the schedule timeline"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                }

                                Rectangle {
                                    width: resetText.implicitWidth + 16
                                    height: 26
                                    radius: 13
                                    color: resetMa.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18) : Qt.rgba(Theme.surfaceContainerHighest.r, Theme.surfaceContainerHighest.g, Theme.surfaceContainerHighest.b, 0.4)
                                    border.width: 1
                                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)

                                    StyledText {
                                        id: resetText
                                        text: "Reset Default"
                                        font.pixelSize: Theme.fontSizeSmall - 1
                                        font.weight: Font.Medium
                                        color: Theme.primary
                                        anchors.centerIn: parent
                                    }

                                    MouseArea {
                                        id: resetMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            let def = ["watching", "rewatching", "planning", "considering"];
                                            statusVisContainer.statusList = def;
                                            root.saveValue("customStatusList", JSON.stringify(def));
                                        }
                                    }
                                }
                            }

                            Flow {
                                id: statusVisFlow
                                width: parent.width
                                spacing: Theme.spacingS

                                readonly property var statusDefs: [
                                    { key: "watching", label: "Watching", icon: "visibility", accent: Theme.success || "#4CAF50" },
                                    { key: "planning", label: "Planning", icon: "schedule", accent: Theme.secondary || "#80CBC4" },
                                    { key: "considering", label: "Considering", icon: "help_outline", accent: Theme.warning || "#FFC107" },
                                    { key: "rewatching", label: "Rewatching", icon: "replay", accent: Theme.success || "#4CAF50" },
                                    { key: "paused", label: "Paused", icon: "pause_circle", accent: Theme.warning || "#FE8E14" },
                                    { key: "completed", label: "Completed", icon: "check_circle", accent: Theme.primary },
                                    { key: "dropped", label: "Dropped", icon: "cancel", accent: Theme.error || "#AC675D" },
                                    { key: "none", label: "Unmarked / None", icon: "cancel", accent: Theme.surfaceVariantText }
                                ]

                                Repeater {
                                    model: statusVisFlow.statusDefs
                                    delegate: Rectangle {
                                        id: statusPill
                                        width: Math.max(0, (statusVisFlow.width - Theme.spacingS) / 2 - 1)
                                        height: 44

                                        readonly property bool isTopRow: index < 2
                                        readonly property bool isBottomRow: index >= 6
                                        readonly property bool isLeftCol: index % 2 === 0
                                        readonly property bool isRightCol: index % 2 === 1

                                        topLeftRadius: (isTopRow && isLeftCol) ? root.outerR : root.innerR
                                        topRightRadius: (isTopRow && isRightCol) ? root.outerR : root.innerR
                                        bottomLeftRadius: (isBottomRow && isLeftCol) ? root.outerR : root.innerR
                                        bottomRightRadius: (isBottomRow && isRightCol) ? root.outerR : root.innerR

                                        readonly property bool isVisible: statusVisContainer.statusList.indexOf(modelData.key) !== -1

                                        color: !isVisible 
                                            ? Qt.rgba(Theme.surfaceContainerHighest.r, Theme.surfaceContainerHighest.g, Theme.surfaceContainerHighest.b, 0.4) 
                                            : Theme.withAlpha(modelData.accent || Theme.primary, 0.15)
                                        border.color: !isVisible 
                                            ? Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.3) 
                                            : Theme.withAlpha(modelData.accent || Theme.primary, 0.45)
                                        border.width: 1

                                        scale: maStatusPill.pressed ? 0.98 : (maStatusPill.containsMouse ? 1.02 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Behavior on border.color { ColorAnimation { duration: 150 } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: Theme.spacingS

                                            Item {
                                                width: 18
                                                height: 18
                                                Layout.alignment: Qt.AlignVCenter

                                                DankIcon {
                                                    name: modelData.icon
                                                    size: 18
                                                    color: !statusPill.isVisible ? Theme.surfaceVariantText : (modelData.accent || Theme.primary)
                                                    anchors.centerIn: parent
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                }
                                            }

                                            StyledText {
                                                text: modelData.label
                                                Layout.fillWidth: true
                                                color: !statusPill.isVisible ? Theme.surfaceVariantText : Theme.surfaceText
                                                font.weight: !statusPill.isVisible ? Font.Normal : Font.Medium
                                                font.pixelSize: Theme.fontSizeSmall
                                                elide: Text.ElideRight
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                            }

                                            Rectangle {
                                                width: 26
                                                height: 26
                                                radius: 13
                                                color: !statusPill.isVisible 
                                                    ? Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.05) 
                                                    : Theme.withAlpha(modelData.accent || Theme.primary, 0.20)
                                                Behavior on color { ColorAnimation { duration: 150 } }

                                                DankIcon {
                                                    name: !statusPill.isVisible ? "visibility_off" : "visibility"
                                                    size: 15
                                                    color: !statusPill.isVisible ? Theme.surfaceVariantText : (modelData.accent || Theme.primary)
                                                    anchors.centerIn: parent
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: maStatusPill
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                let list = Array.from(statusVisContainer.statusList);
                                                let idx = list.indexOf(modelData.key);
                                                if (idx === -1) {
                                                    list.push(modelData.key);
                                                } else {
                                                    list.splice(idx, 1);
                                                }
                                                statusVisContainer.statusList = list;
                                                root.saveValue("customStatusList", JSON.stringify(list));
                                            }
                                            onPressed: (m) => ripStatusPill.trigger(m.x, m.y)
                                        }

                                        DankRipple {
                                            id: ripStatusPill
                                            anchors.fill: parent
                                            cornerRadius: root.innerR
                                            rippleColor: modelData.accent || Theme.primary
                                        }
                                    }
                                }
                            }
                        }
                    }
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

        // ---------------------------------------------------------------------
        // 5. REQUIRED PACKAGES (Segmented Collapsible Section matching DMS UI)
        // ---------------------------------------------------------------------
        Column {
            id: depsWrapper
            width: parent.width
            spacing: Theme.spacingS

            property bool expanded: false
            property var depStatus: ({
                "python3": true,
                "bs4": true,
                "browser_cookie3": true,
                "keyring": true
            })
            property bool isChecking: true

            Process {
                id: depChecker
                command: [
                    "python3", "-c",
                    "import json, sys\n" +
                    "results = {}\n" +
                    "results['python3'] = True\n" +
                    "for pkg, mod in [('bs4', 'bs4'), ('browser_cookie3', 'browser_cookie3'), ('keyring', 'keyring')]:\n" +
                    "    try:\n" +
                    "        __import__(mod)\n" +
                    "        results[pkg] = True\n" +
                    "    except Exception:\n" +
                    "        results[pkg] = False\n" +
                    "sys.stdout.write(json.dumps(results))\n"
                ]
                stdout: StdioCollector {
                    onStreamFinished: {
                        depsWrapper.isChecking = false;
                        try {
                            if (text && text.trim() !== "") {
                                depsWrapper.depStatus = JSON.parse(text.trim());
                            }
                        } catch (e) {
                            console.warn("Failed to parse dependency status:", e);
                        }
                    }
                }
            }

            Component.onCompleted: {
                depChecker.running = true;
            }

                Item {
                    id: depsHeaderRow
                    width: parent.width
                    height: 40

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS

                        DankIcon {
                            name: "extension"
                            size: 16
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: I18n.tr("Required packages")
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    DankIcon {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        name: "expand_more"
                        size: Theme.iconSize || 20
                        color: Theme.surfaceVariantText
                        rotation: depsWrapper.expanded ? 180 : 0

                        Behavior on rotation {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            depsWrapper.expanded = !depsWrapper.expanded;
                            if (depsWrapper.expanded) {
                                depsWrapper.isChecking = true;
                                depChecker.running = true;
                            }
                        }
                    }
                }

                Item {
                    id: animHost
                    width: parent.width
                    clip: true
                    height: depsWrapper.expanded ? groupContent.implicitHeight : 0
                    opacity: depsWrapper.expanded ? 1.0 : 0.0
                    visible: height > 0 || depsWrapper.expanded

                    Behavior on height {
                        NumberAnimation {
                            duration: 250
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutQuad
                        }
                    }

                    SettingsGroup {
                        id: groupContent
                        width: parent.width

                        SettingsRow {
                            visible: depsWrapper.isChecking
                            iconName: "hourglass_top"
                            title: I18n.tr("Checking packages...")
                        }

                        Repeater {
                            model: [
                                {
                                    id: "python3",
                                    pkg: "python3",
                                    features: "Executing the LiveChart.me scraper & CLI operations",
                                    present: Boolean(depsWrapper.depStatus.python3)
                                },
                                {
                                    id: "bs4",
                                    pkg: "beautifulsoup4",
                                    features: "Parsing schedule timetable markup and CSRF tokens",
                                    present: Boolean(depsWrapper.depStatus.bs4)
                                },
                                {
                                    id: "browser_cookie3",
                                    pkg: "browser-cookie3",
                                    features: "Syncing watchlist session tokens from installed browsers",
                                    present: Boolean(depsWrapper.depStatus.browser_cookie3)
                                },
                                {
                                    id: "keyring",
                                    pkg: "keyring",
                                    features: "Decrypting Chromium-based session cookies securely",
                                    present: Boolean(depsWrapper.depStatus.keyring)
                                }
                            ]

                            delegate: SettingsRow {
                                iconName: modelData.present ? "check_circle" : "error"
                                iconColor: modelData.present ? Theme.success : Theme.error
                                title: modelData.pkg
                                subtitle: I18n.tr("Used for: %1").arg(modelData.features)
                                trailingBadge: modelData.present ? I18n.tr("Installed") : I18n.tr("Missing")
                                trailingBadgeColor: modelData.present ? Theme.surfaceVariantText : Theme.error
                            }
                        }
                    }
                }

        }

        // -----------------------------------------------------------------
        // LOCAL USER CHANGES BACKUP / SYNC AUDIT
        // -----------------------------------------------------------------
            Column {
                id: backupSection
                width: parent.width
                spacing: Theme.spacingS

                property bool expanded: false
                property var backupData: ({})
                property int entryCount: Object.keys(backupData).length

                Process {
                    id: backupReader
                    running: false
                    stdout: StdioCollector {
                        onStreamFinished: {
                            try {
                                backupSection.backupData = JSON.parse(text.trim()) || {};
                            } catch (e) {
                                backupSection.backupData = {};
                            }
                        }
                    }
                }

                Process {
                    id: backupCleaner
                    running: false
                    onExited: {
                        backupSection.backupData = {};
                    }
                }

                Component.onCompleted: {
                    backupReader.command = ["cat", "/home/JD/.config/dms/livechart_backup.json"];
                    backupReader.running = true;
                }

                    Rectangle {
                        width: parent.width
                        height: 52
                        radius: Theme.cornerRadius
                        color: Theme.withAlpha(Theme.surfaceContainer, 0.4)
                        border.width: 1
                        border.color: Theme.withAlpha(Theme.primary, 0.15)

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "history"
                                size: Theme.iconSize || 20
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: I18n.tr("Local Mutation Backup & Sync History")
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.DemiBold
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Rectangle {
                                width: Math.max(countTxt.implicitWidth + 12, 24)
                                height: 22
                                radius: 11
                                color: Theme.withAlpha(Theme.primary, 0.2)
                                anchors.verticalCenter: parent.verticalCenter
                                StyledText {
                                    id: countTxt
                                    anchors.centerIn: parent
                                    text: String(backupSection.entryCount) + " " + I18n.tr("Entries")
                                    font.pixelSize: 11
                                    color: Theme.primary
                                }
                            }

                            DankIcon {
                                name: "expand_more"
                                size: Theme.iconSize || 20
                                color: Theme.surfaceVariantText
                                rotation: backupSection.expanded ? 180 : 0
                                anchors.verticalCenter: parent.verticalCenter

                                Behavior on rotation {
                                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                backupSection.expanded = !backupSection.expanded;
                                if (backupSection.expanded) {
                                    backupReader.command = ["cat", "/home/JD/.config/dms/livechart_backup.json"];
                                    backupReader.running = true;
                                }
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        clip: true
                        height: backupSection.expanded ? backupContent.implicitHeight : 0
                        opacity: backupSection.expanded ? 1.0 : 0.0
                        visible: height > 0 || backupSection.expanded

                        Behavior on height {
                            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
                        }

                        SettingsGroup {
                            id: backupContent
                            width: parent.width

                            SettingsRow {
                                iconName: "info"
                                title: I18n.tr("Tracks user modifications (EP counts & statuses)")
                                subtitle: I18n.tr("Persisted in ~/.config/dms/livechart_backup.json to detect external reverts or desyncs.")
                            }

                            Repeater {
                                model: Object.keys(backupSection.backupData)

                                delegate: SettingsRow {
                                    property var itemData: backupSection.backupData[modelData] || {}
                                    iconName: "bookmark"
                                    iconColor: Theme.primary
                                    title: itemData.title || ("Anime #" + modelData)
                                    subtitle: I18n.tr("Status: %1 | Episodes: %2").arg(itemData.status || "N/A").arg(itemData.episodesWatched !== undefined ? itemData.episodesWatched : "N/A")
                                    trailingBadge: itemData.ignored ? I18n.tr("Ignored") : I18n.tr("Tracked")
                                    trailingBadgeColor: itemData.ignored ? Theme.surfaceVariantText : Theme.success
                                }
                            }

                            SettingsRow {
                                visible: backupSection.entryCount > 0
                                iconName: "delete_sweep"
                                title: I18n.tr("Clear Backup History")
                                subtitle: I18n.tr("Reset all locally tracked modification states")
                                clickable: true
                                onClicked: {
                                    backupCleaner.command = ["rm", "-f", "/home/JD/.config/dms/livechart_backup.json"];
                                    backupCleaner.running = true;
                                }
                            }
                        }
                    }
        }
    }
}
