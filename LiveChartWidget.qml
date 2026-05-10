import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// Required for OpacityMask rounding
import Qt5Compat.GraphicalEffects

PluginComponent {
    id: root
    
    // Configurable properties via pluginData (from Settings)
    property string timeFormat: pluginData.timeFormat || "12h"
    property bool showSeconds: pluginData.showSeconds !== undefined ? pluginData.showSeconds : false
    property int updateIntervalMs: {
        let val = parseFloat(pluginData.updateIntervalValue || "1");
        let unit = pluginData.updateIntervalUnit || "h";
        
        // Logical fallback for legacy settings
        if (!pluginData.updateIntervalValue && pluginData.updateInterval) {
            val = parseInt(pluginData.updateInterval);
            unit = "s";
        }

        switch (unit) {
            case "ms": return val;
            case "s":  return val * 1000;
            case "m":  return val * 60000;
            case "h":  return val * 3600000;
            default:   return 3600000;
        }
    }
    property string browserName: pluginData.browser || "firefox"
    
    // Click Action Settings
    property string cardClickAction: pluginData.cardClickAction || "anime_entry"
    property string coverClickAction: pluginData.coverClickAction || "anime_entry"
    property string watchStreamClickAction: pluginData.watchStreamClickAction || "watch_page"
    property string livechartIconClickAction: pluginData.livechartIconClickAction || "schedule"
    property string dankbarPill: pluginData.dankbarPill || "total_count"
    property int dankbarLimit: pluginData.dankbarLimit !== undefined ? parseInt(pluginData.dankbarLimit) : 1
    property string dynamicDisplayMode: "next" // toggles between next and recent
    property int daysToShow: parseInt(pluginData.daysToShow || "7", 10)
    property int startDayOffset: parseInt(pluginData.startDay || "0", 10)

    // Handle settings changes from pluginData
    onPluginDataChanged: {
        // Update daysToShow and trigger data filter update
        let newDays = parseInt(pluginData.daysToShow || "7", 10);
        if (newDays !== root.daysToShow) {
            root.daysToShow = newDays;
        }

        // Update startDayOffset which triggers onTargetDateChanged -> triggerFetch
        let newOffset = parseInt(pluginData.startDay || "0", 10);
        if (newOffset !== root.startDayOffset) {
            root.startDayOffset = newOffset;
        }

        // If browser changed, we must refetch even if date didn't change
        let newBrowser = pluginData.browser || "firefox";
        if (newBrowser !== root.browserName) {
            root.browserName = newBrowser;
            root.isLoading = true;
            root.triggerFetch("Browser changed, refetching...");
        }

        // Other visual settings (timeFormat, showSeconds, etc.) update via bindings or direct assignment
        root.timeFormat = pluginData.timeFormat || "12h";
        root.showSeconds = pluginData.showSeconds !== undefined ? pluginData.showSeconds : false;
        root.cardClickAction = pluginData.cardClickAction || "anime_entry";
        root.coverClickAction = pluginData.coverClickAction || "anime_entry";
        root.watchStreamClickAction = pluginData.watchStreamClickAction || "watch_page";
        root.livechartIconClickAction = pluginData.livechartIconClickAction || "schedule";
        root.dankbarPill = pluginData.dankbarPill || "total_count";
        root.dankbarLimit = pluginData.dankbarLimit !== undefined ? parseInt(pluginData.dankbarLimit) : 1;
    }

    onUpdateIntervalMsChanged: {
        updateTimer.restart();
    }

    // Helper for PWA support
    Process {
        id: pwaOpener
    }

    function openUrl(url) {
        if (!url || url === "") {
            return;
        }
        Qt.openUrlExternally(url);
    }

    // Track current date reactively for seamless midnight transitions
    property date today: new Date()

    // Calculate targetDate dynamically whenever startDayOffset or today changes
    property string targetDate: {
        var d = new Date(root.today);
        d.setDate(d.getDate() + root.startDayOffset);
        var year = d.getFullYear();
        var month = ("0" + (d.getMonth() + 1)).slice(-2);
        var day = ("0" + d.getDate()).slice(-2);
        return year + "-" + month + "-" + day;
    }
    
    // Automatically fetch when targetDate changes (user changes setting)
    onTargetDateChanged: {
        if (fetchProcess) {
            root.isLoading = true;
            root.fullScheduleData = []; // Clear current data instantly to show skeleton
            root.updateScheduleData();
            root.triggerFetch("Refetching from start date...");
        }
    }
    
    // Internal state
    property var fullScheduleData: []
    property var scheduleData: []
    property string statusMessage: "Initializing..."
    property bool isLoading: true
    property string errorType: ""
    property string installCommand: ""

    onDaysToShowChanged: updateScheduleData()
    onFullScheduleDataChanged: updateScheduleData()

    function updateScheduleData() {
        if (!root.fullScheduleData || root.fullScheduleData.length === 0) {
            root.scheduleData = [];
            return;
        }
        const limitedData = root.fullScheduleData.slice(0, root.daysToShow);
        root.scheduleData = limitedData;
        let count = 0;
        let targetIndex = 0;
        for (let i = 0; i < limitedData.length; i++) {
            count += limitedData[i].shows.length;
            if (limitedData[i].day === root.currentDayName) {
                targetIndex = i;
            }
        }
        root.statusMessage = "Loaded " + count + " active anime for " + limitedData.length + " day(s)";
        if (scrollTimer) {
            scrollTimer.focusIndex = targetIndex;
            scrollTimer.restart();
        }
    }

    function triggerFetch(message) {
        if (!fetchProcess) return;
        
        console.log("LiveChart: Triggering fetch for date:", root.targetDate, "| Reason:", message);
        
        if (message) {
            root.statusMessage = message;
        }

        // Restart process if already running to pick up new arguments (critical for date transitions)
        if (fetchProcess.running) {
            fetchProcess.running = false;
        }

        // Use a robust execution wrapper:
        // 1. If the script is executable (NixOS wrapper or correctly set permissions), run it directly.
        // 2. Otherwise, fallback to python3 (standard Linux/Windows-style execution).
        // This ensures compatibility across both NixOS and regular Linux distributions.
        fetchProcess.command = [
            "sh", "-c",
            'script="$1"; shift; if [ -x "$script" ]; then exec "$script" "$@"; else exec python3 "$script" "$@"; fi',
            "--",
            Qt.resolvedUrl("fetch_livechart.py").toString().replace("file://", ""),
            root.targetDate,
            root.browserName
        ];
        fetchProcess.running = true;
    }
    
    property bool minimumWidth: pluginData.minimumWidth !== undefined ? pluginData.minimumWidth : false
    
    // Day name for dynamic coloring
    // Day name for dynamic coloring - now reactive to "today" property
    property string currentDayName: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][root.today.getDay()]
    
    // Timer to update "Now" position
    property double currentTime: Date.now() / 1000
    Timer {
        interval: 1000 // 1 second for live updates
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            let now = new Date();
            root.currentTime = now.getTime() / 1000;
            
            // Seamless midnight transition: check if the day has changed
            if (now.getDate() !== root.today.getDate()) {
                console.log("LiveChart: Day transitioned, refreshing data...");
                root.today = now; 
                // Updating root.today triggers currentDayName and targetDate re-evaluation,
                // which in turn triggers triggerFetch via onTargetDateChanged.
            }
        }
    }

    // Standard DMS widget capability popout styling
    popoutWidth: Math.max(400, 300 * root.daysToShow) // Dynamically resize width per day

    Timer {
        id: updateTimer
        interval: Math.max(100, root.updateIntervalMs)
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.isLoading = true;
            root.triggerFetch("Fetching schedule...");
        }
    }

    Timer {
        id: dynamicDisplayTimer
        interval: 10000 // 10 seconds
        running: root.dankbarPill === "dynamic"
        repeat: true
        onTriggered: root.dynamicDisplayMode = (root.dynamicDisplayMode === "next" ? "recent" : "next")
    }

    function getDankbarText(isVertical) {
        if (root.isLoading) return isVertical ? "..." : "Fetching...";
        
        let todayCount = 0;
        for (let i = 0; i < root.fullScheduleData.length; i++) {
            if (root.fullScheduleData[i].day === root.currentDayName) {
                todayCount = root.fullScheduleData[i].shows.length;
                break;
            }
        }

        if (isVertical) return todayCount.toString();
        
        if (root.dankbarPill === "total_count") {
            let totalCount = 0;
            for (let i = 0; i < root.scheduleData.length; i++) {
                totalCount += root.scheduleData[i].shows.length;
            }
            return `Anime (${totalCount})`;
        }
        
        if (root.dankbarPill === "today_count") {
            return `Today (${todayCount})`;
        }

        let nextShows = [];
        let recentShows = [];

        for (let i = 0; i < root.fullScheduleData.length; i++) {
            let day = root.fullScheduleData[i];
            for (let j = 0; j < day.shows.length; j++) {
                let show = day.shows[j];
                let ts = parseFloat(show.timestamp);
                let diff = ts - root.currentTime;
                
                if (diff > 0) {
                    nextShows.push({ show: show, diff: diff });
                } else {
                    recentShows.push({ show: show, diff: Math.abs(diff) });
                }
            }
        }

        nextShows.sort((a, b) => a.diff - b.diff);
        recentShows.sort((a, b) => a.diff - b.diff);

        function formatTimeDiff(diff) {
            let absDiff = Math.abs(diff);
            let d = Math.floor(absDiff / 86400);
            let h = Math.floor((absDiff % 86400) / 3600);
            let m = Math.floor((absDiff % 3600) / 60);

            let res = "";
            if (d > 0) res += d + "d ";
            if (h > 0) res += h + "h ";
            if (m > 0 || (d === 0 && h === 0)) res += m + "m";
            
            return res.trim();
        }

        let mode = root.dankbarPill;
        if (mode === "dynamic") mode = (root.dynamicDisplayMode === "next" ? "next_airing" : "recently_aired");

        if (mode === "next_airing") {
            if (nextShows.length === 0) return "None Next";
            
            let displays = [];
            for (let i = 0; i < Math.min(nextShows.length, root.dankbarLimit); i++) {
                let ns = nextShows[i];
                let timeStr = formatTimeDiff(ns.diff);
                displays.push(`${ns.show.title} ${ns.show.ep ? "Ep " + ns.show.ep : ""} (in ${timeStr})`);
            }
            return displays.join("  •  ");
        }
        
        if (mode === "recently_aired") {
            if (recentShows.length === 0) return "None Recent";
            
            let displays = [];
            for (let i = 0; i < Math.min(recentShows.length, root.dankbarLimit); i++) {
                let rs = recentShows[i];
                let timeStr = formatTimeDiff(rs.diff);
                displays.push(`${rs.show.title} ${rs.show.ep ? "Ep " + rs.show.ep : ""} (${timeStr} ago)`);
            }
            return displays.join("  •  ");
        }

        return "Anime";
    }

    Timer {
        id: scrollTimer
        interval: 100
        repeat: false
        property int focusIndex: 0
        onTriggered: {
            if (mainListView) {
                mainListView.positionViewAtIndex(focusIndex, ListView.Beginning);
                mainListView.currentIndex = focusIndex;
            }
        }
    }

    Process {
        id: fetchProcess
        // Resolve the python script relative to this QML file
        // Initial command array using the same robust wrapper as triggerFetch
        command: [
            "sh", "-c",
            'script="$1"; shift; if [ -x "$script" ]; then exec "$script" "$@"; else exec python3 "$script" "$@"; fi',
            "--",
            Qt.resolvedUrl("fetch_livechart.py").toString().replace("file://", ""),
            root.targetDate,
            root.browserName
        ]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                root.isLoading = false;
                const output = text.trim();
                try {
                    const parsed = JSON.parse(output);
                    if (parsed.success) {
                        root.fullScheduleData = parsed.data;
                        root.errorType = "";
                        root.installCommand = "";
                    } else {
                        root.statusMessage = parsed.error || "Failed to fetch data";
                        root.errorType = parsed.error_type || "generic";
                        root.installCommand = parsed.install_cmd || "";
                        root.fullScheduleData = [];
                    }
                } catch (e) {
                    root.statusMessage = "Error parsing output from Python script.";
                    root.errorType = "parse_error";
                    console.error("LiveChart Parser Error:", e, "| Output:", output);
                }
            }
        }
        
        onExited: {
            if (exitCode !== 0) {
                root.isLoading = false;
                if (root.fullScheduleData.length === 0 && root.errorType === "") {
                    if (exitCode === 126) {
                        root.statusMessage = "Permission denied. Try: chmod +x fetch_livechart.py";
                    } else if (exitCode === 127) {
                        root.statusMessage = "Python 3 or Script not found.";
                    } else {
                        root.statusMessage = "Python script exited with code " + exitCode;
                    }
                    root.errorType = "exit_error";
                }
            }
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS
            Item {
                width: root.iconSize
                height: root.iconSize
                anchors.verticalCenter: parent.verticalCenter
                
                Image {
                    id: horizLiveChartLogo
                    source: "assets/LiveChart.svg"
                    anchors.fill: parent
                    sourceSize: Qt.size(64, 64)
                    smooth: true
                    visible: false
                }
                
                ColorOverlay {
                    anchors.fill: horizLiveChartLogo
                    source: horizLiveChartLogo
                    color: Theme.widgetTextColor
                }
            }
            Rectangle {
                id: textContainer
                anchors.verticalCenter: parent.verticalCenter
                color: "transparent"
                clip: true
                
                // Smoothly animate width changes
                width: Math.min(statusText.contentWidth, 180)
                height: 18 // Sufficient for Theme.fontSizeSmall
                
                Behavior on width {
                    NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing }
                }

                StyledText {
                    id: statusText
                    readonly property bool isLong: contentWidth > textContainer.width
                    property real scrollOffset: 0
                    
                    x: isLong ? -scrollOffset : 0
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.widgetTextColor
                    text: root.getDankbarText(false)
                    wrapMode: Text.NoWrap
                    
                    onTextChanged: {
                        scrollOffset = 0;
                        scrollAnimation.restart();
                    }

                    SequentialAnimation {
                        id: scrollAnimation
                        running: statusText.isLong && textContainer.visible
                        loops: Animation.Infinite

                        PauseAnimation { duration: 2000 }
                        NumberAnimation {
                            target: statusText
                            property: "scrollOffset"
                            from: 0
                            to: statusText.contentWidth - textContainer.width + 10
                            duration: Math.max(1000, (statusText.contentWidth - textContainer.width) * 40)
                            easing.type: Easing.Linear
                        }
                        PauseAnimation { duration: 2000 }
                        NumberAnimation {
                            target: statusText
                            property: "scrollOffset"
                            to: 0
                            duration: Theme.shortDuration
                            easing.type: Theme.standardEasing
                        }
                    }
                }
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 4
            Item {
                width: root.iconSize
                height: root.iconSize
                anchors.horizontalCenter: parent.horizontalCenter
                
                Image {
                    id: vertLiveChartLogo
                    source: "assets/LiveChart.svg"
                    anchors.fill: parent
                    sourceSize: Qt.size(64, 64)
                    smooth: true
                    visible: false
                }
                
                ColorOverlay {
                    anchors.fill: vertLiveChartLogo
                    source: vertLiveChartLogo
                    color: Theme.widgetTextColor
                }
            }
            StyledText {
                text: root.getDankbarText(true)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.widgetTextColor
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout
            
            Column {
                width: parent.width
                spacing: Theme.spacingM

                // Header card
                Item {
                    width: parent.width
                    height: 68

                    StyledRect {
                        anchors.fill: parent
                        radius: Theme.cornerRadius * 1.5
                        color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                        layer.enabled: true
                        layer.effect: DropShadow {
                            transparentBorder: true
                            horizontalOffset: 0
                            verticalOffset: 3
                            radius: 12.0
                            samples: 24
                            color: Theme.withAlpha(Theme.shadowColor || "#000000", 0.35)
                        }
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingM

                        Item {
                            width: 44
                            height: 44
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                id: logoBg
                                anchors.fill: parent
                                radius: 22
                                color: iconMA.containsMouse ? Theme.withAlpha(Theme.primary, 0.2) : Theme.withAlpha(Theme.primary, 0.1)
                                border.width: 1
                                border.color: iconMA.containsMouse ? Theme.primary : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                Behavior on border.color { ColorAnimation { duration: Theme.shortDuration } }
                                scale: iconMA.containsMouse ? 1.1 : 1.0
                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            }

                            DankRipple {
                                id: iconRipple
                                cornerRadius: 22
                                rippleColor: Theme.primary
                                anchors.fill: parent
                            }

                            Image {
                                source: "https://www.google.com/s2/favicons?domain=livechart.me&sz=64"
                                width: 24
                                height: 24
                                sourceSize: Qt.size(24, 24)
                                anchors.centerIn: parent
                                fillMode: Image.PreserveAspectFit
                                scale: iconMA.containsMouse ? 1.1 : 1.0
                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            }

                            MouseArea {
                                id: iconMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                z: 10
                                onPressed: (mouse) => iconRipple.trigger(mouse.x, mouse.y)
                                onClicked: {
                                    root.openUrl(root.livechartIconClickAction === "livechart" ? "https://www.livechart.me" : "https://www.livechart.me/schedule")
                                }
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            StyledText {
                                id: titleText
                                text: "LiveChart.me"
                                font.bold: true
                                font.pixelSize: Theme.fontSizeLarge
                                color: Theme.surfaceText
                                
                                onTextChanged: titleAnim.restart()
                                transform: Translate { id: titleTrans }
                                SequentialAnimation {
                                    id: titleAnim
                                    ParallelAnimation {
                                        NumberAnimation { target: titleText; property: "opacity"; to: 0; duration: 150; easing.type: Easing.OutQuad }
                                        NumberAnimation { target: titleTrans; property: "y"; to: 5; duration: 150; easing.type: Easing.OutQuad }
                                    }
                                    PropertyAction { target: titleTrans; property: "y"; value: -5 }
                                    ParallelAnimation {
                                        NumberAnimation { target: titleText; property: "opacity"; to: 1; duration: 150; easing.type: Easing.InQuad }
                                        NumberAnimation { target: titleTrans; property: "y"; to: 0; duration: 150; easing.type: Easing.InQuad }
                                    }
                                }
                            }

                            StyledText {
                                id: statusTextHeader
                                text: root.statusMessage
                                font.pixelSize: Theme.fontSizeSmall
                                color: root.isLoading ? Theme.secondary : Theme.primary
                                
                                onTextChanged: statusAnimHeader.restart()
                                transform: Translate { id: statusTransHeader }
                                SequentialAnimation {
                                    id: statusAnimHeader
                                    ParallelAnimation {
                                        NumberAnimation { target: statusTextHeader; property: "opacity"; to: 0; duration: 150; easing.type: Easing.OutQuad }
                                        NumberAnimation { target: statusTransHeader; property: "y"; to: 5; duration: 150; easing.type: Easing.OutQuad }
                                    }
                                    PropertyAction { target: statusTransHeader; property: "y"; value: -5 }
                                    ParallelAnimation {
                                        NumberAnimation { target: statusTextHeader; property: "opacity"; to: 1; duration: 150; easing.type: Easing.InQuad }
                                        NumberAnimation { target: statusTransHeader; property: "y"; to: 0; duration: 150; easing.type: Easing.InQuad }
                                    }
                                }
                            }
                        }
                    }

                    // Custom Navigation Group (Header Centered Version - Hidden on small layouts)
                    Row {
                        visible: root.daysToShow > 2
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS
                        
                        Repeater {
                            model: [
                                { text: "<<", action: () => root.triggerFetch(), offset: -7 },
                                { text: "<", action: () => root.triggerFetch(), offset: -1 },
                                { text: "Today", isTodayBtn: true, action: () => root.triggerFetch(), offset: 0 },
                                { text: ">", action: () => root.triggerFetch(), offset: 1 },
                                { text: ">>", action: () => root.triggerFetch(), offset: 7 }
                            ]
                            
                            Rectangle {
                                id: navBtn
                                property bool isFirst: index === 0
                                property bool isLast: index === 4
                                property bool isTodayAtDefault: (modelData.isTodayBtn === true) && (root.startDayOffset === parseInt(pluginData.startDay || "0", 10))
                                
                                width: Math.max(btnText.implicitWidth + Theme.spacingL * 2, 64) + (isTodayAtDefault ? 4 : 0)
                                height: 40
                                
                                // Pure base color mimicking DankButtonGroup default
                                color: isTodayAtDefault ? Theme.primary : Theme.surfaceVariant
                                
                                topLeftRadius: (isFirst || isTodayAtDefault) ? Theme.cornerRadius : Math.min(4, Theme.cornerRadius)
                                bottomLeftRadius: (isFirst || isTodayAtDefault) ? Theme.cornerRadius : Math.min(4, Theme.cornerRadius)
                                topRightRadius: (isLast || isTodayAtDefault) ? Theme.cornerRadius : Math.min(4, Theme.cornerRadius)
                                bottomRightRadius: (isLast || isTodayAtDefault) ? Theme.cornerRadius : Math.min(4, Theme.cornerRadius)
                                
                                Behavior on width { enabled: true; NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                Behavior on topLeftRadius { enabled: true; NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                Behavior on bottomLeftRadius { enabled: true; NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                Behavior on topRightRadius { enabled: true; NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                Behavior on bottomRightRadius { enabled: true; NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                Behavior on color { ColorAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                
                                // Overlay stateLayer directly extracted from DankButtonGroup source code 
                                // perfectly enforcing standardized interaction highlights.
                                Rectangle {
                                    id: stateLayer
                                    anchors.fill: parent
                                    topLeftRadius: parent.topLeftRadius
                                    bottomLeftRadius: parent.bottomLeftRadius
                                    topRightRadius: parent.topRightRadius
                                    bottomRightRadius: parent.bottomRightRadius
                                    color: {
                                        if (navHover.pressed) return isTodayAtDefault ? Theme.buttonPressed : Theme.surfaceTextHover;
                                        if (navHover.containsMouse) return isTodayAtDefault ? Theme.buttonHover : Theme.surfaceTextHover;
                                        return "transparent";
                                    }
                                    Behavior on color { ColorAnimation { duration: Theme.shorterDuration; easing.type: Theme.standardEasing } }
                                }
                                
                                DankRipple {
                                    id: navRipple
                                    cornerRadius: isFirst || isLast || isTodayAtDefault ? Theme.cornerRadius : Math.min(4, Theme.cornerRadius)
                                    rippleColor: isTodayAtDefault ? Theme.onPrimary : Theme.surfaceVariantText
                                }
                                
                                Item {
                                    anchors.fill: parent
                                    
                                    StyledText {
                                        id: btnText
                                        text: modelData.text
                                        font.pixelSize: Theme.fontSizeMedium
                                        anchors.centerIn: parent
                                        color: isTodayAtDefault ? Theme.surfaceVariant : Theme.surfaceVariantText
                                        font.weight: isTodayAtDefault ? Font.Medium : Font.Normal
                                        
                                        // Tactile scale zoom exclusively for the Today anchor
                                        scale: (navHover.containsMouse && modelData.isTodayBtn) ? 1.1 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                        
                                        transform: Translate {
                                            id: iconTranslate
                                            x: 0
                                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                        }
                                    }
                                }
                                
                                MouseArea {
                                    id: navHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: mouse => navRipple.trigger(mouse.x, mouse.y)
                                    onClicked: {
                                        if (modelData.isTodayBtn) {
                                            root.startDayOffset = parseInt(pluginData.startDay || "0", 10);
                                        } else {
                                            root.startDayOffset += modelData.offset;
                                        }
                                    }
                                    onEntered: {
                                        if (modelData.text === "<" || modelData.text === "<<") iconTranslate.x = -4;
                                        if (modelData.text === ">" || modelData.text === ">>") iconTranslate.x = 4;
                                    }
                                    onExited: {
                                        iconTranslate.x = 0;
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        id: refreshContainer
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        width: 42
                        height: 42
                        scale: refreshArea.pressed ? 0.9 : (refreshArea.containsMouse ? 1.1 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                        MouseArea {
                            id: refreshArea
                            anchors.fill: parent
                            hoverEnabled: !root.isLoading
                            enabled: !root.isLoading
                            cursorShape: root.isLoading ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onPressed: mouse => refreshRipple.trigger(mouse.x, mouse.y)
                            onClicked: {
                                if (root.isLoading) return;
                                root.isLoading = true;
                                root.fullScheduleData = [];
                                root.updateScheduleData();
                                root.triggerFetch("Fetching schedule...");
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.cornerRadius
                            color: refreshArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.4)
                            border.width: 1
                            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, refreshArea.containsMouse ? 0.3 : 0.15)
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }

                        DankIcon {
                            id: refreshIcon
                            name: root.isLoading ? "cached" : "refresh"
                            size: 22
                            color: Theme.primary
                            anchors.centerIn: parent

                            SequentialAnimation {
                                id: hoverSpinAnim
                                running: refreshArea.containsMouse && !root.isLoading
                                onStopped: refreshIcon.rotation = 0
                                NumberAnimation { target: refreshIcon; property: "rotation"; from: 0; to: 45; duration: 200; easing.type: Easing.OutQuad }
                                NumberAnimation { target: refreshIcon; property: "rotation"; from: 45; to: -45; duration: 400; easing.type: Easing.InOutQuad }
                                NumberAnimation { target: refreshIcon; property: "rotation"; from: -45; to: 0; duration: 200; easing.type: Easing.InQuad }
                            }

                            RotationAnimation on rotation {
                                from: 0
                                to: 360
                                duration: 1000
                                loops: Animation.Infinite
                                running: root.isLoading
                            }
                        }

                        DankRipple {
                            id: refreshRipple
                            rippleColor: Theme.surfaceText
                            cornerRadius: Theme.cornerRadius
                            anchors.fill: parent
                        }
                    }
                }

                // Dedicated Navigation Row (Standalone version for small layouts)
                // This appears between the header card and the schedule content when 1 or 2 days are shown.
                Rectangle {
                    visible: root.daysToShow <= 2
                    width: parent.width
                    height: 56
                    radius: Theme.cornerRadius * 1.5
                    color: Theme.withAlpha(Theme.surfaceContainer, 0.6)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.primary, 0.15)
                    
                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS
                        
                        Repeater {
                            model: [
                                { text: "<<", action: () => root.triggerFetch(), offset: -7 },
                                { text: "<", action: () => root.triggerFetch(), offset: -1 },
                                { text: "Today", isTodayBtn: true, action: () => root.triggerFetch(), offset: 0 },
                                { text: ">", action: () => root.triggerFetch(), offset: 1 },
                                { text: ">>", action: () => root.triggerFetch(), offset: 7 }
                            ]
                            
                            Rectangle {
                                id: navBtnStandalone
                                property bool isFirst: index === 0
                                property bool isLast: index === 4
                                property bool isTodayAtDefault: (modelData.isTodayBtn === true) && (root.startDayOffset === parseInt(pluginData.startDay || "0", 10))
                                
                                width: Math.max(btnTextStandalone.implicitWidth + Theme.spacingL * 2, 64) + (isTodayAtDefault ? 4 : 0)
                                height: 40
                                
                                // Pure base color mirroring DankButtonGroup default
                                color: isTodayAtDefault ? Theme.primary : Theme.surfaceVariant
                                
                                topLeftRadius: (isFirst || isTodayAtDefault) ? Theme.cornerRadius : Math.min(4, Theme.cornerRadius)
                                bottomLeftRadius: (isFirst || isTodayAtDefault) ? Theme.cornerRadius : Math.min(4, Theme.cornerRadius)
                                topRightRadius: (isLast || isTodayAtDefault) ? Theme.cornerRadius : Math.min(4, Theme.cornerRadius)
                                bottomRightRadius: (isLast || isTodayAtDefault) ? Theme.cornerRadius : Math.min(4, Theme.cornerRadius)
                                
                                Behavior on width { enabled: true; NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                Behavior on topLeftRadius { enabled: true; NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                Behavior on bottomLeftRadius { enabled: true; NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                Behavior on topRightRadius { enabled: true; NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                Behavior on bottomRightRadius { enabled: true; NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                Behavior on color { ColorAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                
                                Rectangle {
                                    id: stateLayerStandalone
                                    anchors.fill: parent
                                    topLeftRadius: parent.topLeftRadius
                                    bottomLeftRadius: parent.bottomLeftRadius
                                    topRightRadius: parent.topRightRadius
                                    bottomRightRadius: parent.bottomRightRadius
                                    color: {
                                        if (navHoverStandalone.pressed) return isTodayAtDefault ? Theme.buttonPressed : Theme.surfaceTextHover;
                                        if (navHoverStandalone.containsMouse) return isTodayAtDefault ? Theme.buttonHover : Theme.surfaceTextHover;
                                        return "transparent";
                                    }
                                    Behavior on color { ColorAnimation { duration: Theme.shorterDuration; easing.type: Theme.standardEasing } }
                                }
                                
                                DankRipple {
                                    id: navRippleStandalone
                                    cornerRadius: isFirst || isLast || isTodayAtDefault ? Theme.cornerRadius : Math.min(4, Theme.cornerRadius)
                                    rippleColor: isTodayAtDefault ? Theme.onPrimary : Theme.surfaceVariantText
                                }
                                
                                Item {
                                    anchors.fill: parent
                                    
                                    StyledText {
                                        id: btnTextStandalone
                                        text: modelData.text
                                        font.pixelSize: Theme.fontSizeMedium
                                        anchors.centerIn: parent
                                        color: isTodayAtDefault ? "#FFFFFF" : Theme.surfaceVariantText
                                        font.weight: isTodayAtDefault ? Font.Medium : Font.Normal
                                        
                                        scale: (navHoverStandalone.containsMouse && modelData.isTodayBtn) ? 1.1 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                        
                                        transform: Translate {
                                            id: iconTranslateStandalone
                                            x: 0
                                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                        }
                                    }
                                }
                                
                                MouseArea {
                                    id: navHoverStandalone
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: mouse => navRippleStandalone.trigger(mouse.x, mouse.y)
                                    onClicked: {
                                        if (modelData.isTodayBtn) {
                                            root.startDayOffset = parseInt(pluginData.startDay || "0", 10);
                                        } else {
                                            root.startDayOffset += modelData.offset;
                                        }
                                    }
                                    onEntered: {
                                        if (modelData.text === "<" || modelData.text === "<<") iconTranslateStandalone.x = -4;
                                        if (modelData.text === ">" || modelData.text === ">>") iconTranslateStandalone.x = 4;
                                    }
                                    onExited: {
                                        iconTranslateStandalone.x = 0;
                                    }
                                }
                            }
                        }
                    }
                }

                // Skeleton Loading State
                Row {
                    id: skeletonLoader
                    visible: root.isLoading
                    width: parent.width
                    height: 540
                    spacing: 12
                    
                    Repeater {
                        model: root.daysToShow
                        
                        Column {
                            width: (skeletonLoader.width - (skeletonLoader.spacing * Math.max(0, root.daysToShow - 1))) / root.daysToShow
                            height: parent.height
                            spacing: 0
                            
                            // Skeleton Header
                            Rectangle {
                                width: parent.width
                                height: 40
                                color: Theme.withAlpha(Theme.surfaceVariantText, 0.15)
                                radius: Theme.cornerRadius
                            }
                            
                            // Skeleton Cards Pattern
                            Repeater {
                                model: 3
                                
                                Item {
                                    width: parent.width
                                    height: 205 // Exact height equivalent: 16px gap + 190px card
                                    
                                    // Gap line precisely mirroring live card offsets
                                    Rectangle {
                                        width: 3
                                        height: 16
                                        color: Theme.withAlpha(Theme.surfaceVariantText, 0.1)
                                        anchors.left: parent.left
                                        anchors.leftMargin: 38.5 // Aligns with vertical timeline axis
                                    }
                                    
                                    // True dimension dummy card
                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.topMargin: 16
                                        width: parent.width - 16 // Accurately reserves 16px scrollbar gutter
                                        height: 190
                                        radius: 20
                                        color: Theme.withAlpha(Theme.surfaceVariantText, 0.1)
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.surfaceVariantText, 0.05)
                                    }
                                }
                            }
                        }
                    }

                    // Global Pulse Animation
                    SequentialAnimation on opacity {
                        running: root.isLoading
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 800; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutQuad }
                    }
                }

                // Enhanced Error State View
                Item {
                    id: errorView
                    visible: !root.isLoading && (root.scheduleData.length === 0 || root.errorType !== "")
                    width: parent.width
                    height: 540
                    clip: true

                    // Material 3 Expressive Background Shapes
                    Item {
                        anchors.fill: parent
                        z: -1
                        opacity: 0.6
                        
                        Repeater {
                            id: shapeRepeater
                            model: Math.floor(Math.random() * 3) + 3 // Initialize with 3-5 shapes
                            
                            // Re-randomize when error view becomes visible
                            Connections {
                                target: errorView
                                function onVisibleChanged() {
                                    if (errorView.visible) {
                                        shapeRepeater.model = Math.floor(Math.random() * 3) + 3;
                                    }
                                }
                            }

                            ExpressiveShape {
                                // Randomize base parameters for more variety
                                size: 180 + Math.random() * 200
                                duration: 15000 + Math.random() * 15000
                                color1: index % 2 === 0 ? Theme.primary : Theme.secondary
                                color2: index % 3 === 0 ? "transparent" : (index % 2 === 0 ? Theme.secondary : Theme.primary)
                                opacity: 0.3 + (Math.random() * 0.2)
                            }
                        }
                    }

                    // Background Day Segments (Mirroring skeleton/list structure)
                    Row {
                        anchors.fill: parent
                        spacing: 12
                        Repeater {
                            model: root.daysToShow
                            Rectangle {
                                width: (parent.width - (12 * Math.max(0, root.daysToShow - 1))) / root.daysToShow
                                height: parent.height
                                color: Theme.withAlpha(Theme.surfaceVariantText, 0.05)
                                radius: Theme.cornerRadius
                                
                                // Segment Header
                                Rectangle {
                                    width: parent.width
                                    height: 40
                                    color: Theme.withAlpha(Theme.surfaceVariantText, 0.1)
                                    radius: Theme.cornerRadius
                                }
                            }
                        }
                    }

                    // Error Content Card
                    Column {
                        anchors.centerIn: parent
                        width: Math.min(600, parent.width * 0.9)
                        spacing: Theme.spacingM

                        Rectangle {
                            width: parent.width
                            implicitHeight: errorLayout.implicitHeight + Theme.spacingL * 2
                            radius: 24
                            color: Theme.withAlpha(Theme.surfaceContainer, 0.8)
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.primary, 0.2)
                            
                            ColumnLayout {
                                id: errorLayout
                                anchors.fill: parent
                                anchors.margins: Theme.spacingL
                                spacing: Theme.spacingM

                                DankIcon {
                                    name: "error"
                                    size: 64
                                    color: Theme.primary
                                    Layout.alignment: Qt.AlignHCenter
                                }

                                StyledText {
                                    text: "Snap! Something went wrong"
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.bold: true
                                    color: Theme.surfaceText
                                    Layout.alignment: Qt.AlignHCenter
                                }

                                StyledText {
                                    text: root.statusMessage
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: Theme.surfaceVariantText
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }

                                // Dependency specific helper
                                ColumnLayout {
                                    visible: root.errorType === "missing_dependency" && root.installCommand !== ""
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingS

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 1
                                        color: Theme.withAlpha(Theme.surfaceVariantText, 0.1)
                                    }

                                    StyledText {
                                        text: "To fix this, please install the missing library:"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.secondary
                                        Layout.alignment: Qt.AlignHCenter
                                    }

                                    Rectangle {
                                        id: cmdBox
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 60
                                        radius: 12
                                        color: Theme.withAlpha("#000000", 0.3)
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.primary, 0.3)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: Theme.spacingM

                                            StyledText {
                                                text: root.installCommand
                                                font.family: "Monospace"
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.primary
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignVCenter
                                                verticalAlignment: Text.AlignVCenter
                                                elide: Text.ElideRight
                                            }

                                            DankButton {
                                                id: copyBtn
                                                width: 110
                                                height: 38
                                                Layout.alignment: Qt.AlignVCenter
                                                
                                                scale: hovered ? 1.05 : 1.0
                                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Theme.standardEasing } }

                                                onClicked: {
                                                    Quickshell.clipboardText = root.installCommand;
                                                    copyAnim.start();
                                                }
                                                
                                                Row {
                                                    anchors.centerIn: parent
                                                    spacing: 8
                                                    DankIcon {
                                                        id: copyBtnIcon
                                                        name: "content_copy"
                                                        size: 18
                                                        color: Theme.buttonText
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        
                                                        scale: copyBtn.hovered ? 1.2 : 1.0
                                                        Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                                                    }
                                                    StyledText {
                                                        text: "Copy"
                                                        color: Theme.buttonText
                                                        font.pixelSize: 13
                                                        font.weight: Font.Medium
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }
                                                
                                                SequentialAnimation {
                                                    id: copyAnim
                                                    PropertyAction { target: cmdBox; property: "border.color"; value: Theme.success }
                                                    PauseAnimation { duration: 1000 }
                                                    PropertyAction { target: cmdBox; property: "border.color"; value: Theme.withAlpha(Theme.primary, 0.3) }
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                DankButton {
                                    id: retryBtn
                                    Layout.alignment: Qt.AlignHCenter
                                    width: 160
                                    height: 48
                                    
                                    scale: hovered ? 1.05 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Theme.standardEasing } }

                                    onClicked: {
                                        root.isLoading = true;
                                        root.triggerFetch("Retrying...");
                                    }

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: Theme.spacingS
                                        DankIcon {
                                            id: retryBtnIcon
                                            name: "refresh"
                                            size: 20
                                            color: Theme.buttonText
                                            anchors.verticalCenter: parent.verticalCenter
                                            
                                            rotation: retryBtn.hovered ? 180 : 0
                                            Behavior on rotation { NumberAnimation { duration: 400; easing.type: Easing.OutBack } }
                                        }
                                        StyledText {
                                            text: "Retry Now"
                                            color: Theme.buttonText
                                            font.pixelSize: Theme.fontSizeMedium
                                            font.weight: Font.Medium
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Schedule List Weekly Horizontal Grid
                DankListView {
                    id: mainListView
                    visible: root.scheduleData.length > 0
                    width: parent.width
                    height: 540 // Increased to accommodate headers
                    orientation: ListView.Horizontal
                    model: root.scheduleData
                    spacing: 12 // Reduced gap
                    clip: true
                    
                    delegate: Item {
                        id: dayDelegate
                        width: (ListView.view.width - (ListView.view.spacing * Math.max(0, root.daysToShow - 1))) / root.daysToShow
                        height: ListView.view.height
                        
                        property int dayIndex: index
                        readonly property bool isToday: modelData.day === root.currentDayName && dayIndex === -root.startDayOffset

                        Column {
                            id: dayColumn
                            anchors.fill: parent
                            spacing: 0 // Flush connection
                            
                            readonly property int timelineX: 40 // Consistent left-aligned axis

                            // Custom Header Segment (Inside Delegate for scroll alignment)
                            Rectangle {
                                id: headerSegment
                                width: parent.width
                                height: 40
                                
                                property bool isToday: dayDelegate.isToday
                                
                                color: isToday ? Theme.withAlpha(Theme.buttonBg, 0.7) : Theme.withAlpha(Theme.surfaceVariant, 0.5)
                                Behavior on color { ColorAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                
                                // Selective corner rounding for pill effect
                                property int edgeRadius: Theme.cornerRadius
                                property int innerRadius: Math.min(4, Theme.cornerRadius) // Reverted to 4
                                
                                topLeftRadius: dayDelegate.dayIndex === 0 ? edgeRadius : innerRadius
                                bottomLeftRadius: dayDelegate.dayIndex === 0 ? edgeRadius : innerRadius
                                topRightRadius: dayDelegate.dayIndex === root.daysToShow - 1 ? edgeRadius : innerRadius
                                bottomRightRadius: dayDelegate.dayIndex === root.daysToShow - 1 ? edgeRadius : innerRadius

                                // Top highlight for 3D effect
                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: 1
                                    color: Theme.withAlpha("#FFFFFF", 0.1)
                                    topLeftRadius: parent.topLeftRadius
                                    topRightRadius: parent.topRightRadius
                                }
                                
                                // Shared component-level native interaction layer
                                Rectangle {
                                    id: dayStateLayer
                                    anchors.fill: parent
                                    topLeftRadius: parent.topLeftRadius
                                    bottomLeftRadius: parent.bottomLeftRadius
                                    topRightRadius: parent.topRightRadius
                                    bottomRightRadius: parent.bottomRightRadius
                                    color: {
                                        if (headerMouse.pressed) return headerSegment.isToday ? Theme.buttonPressed : Theme.surfaceTextHover;
                                        if (headerMouse.containsMouse) return headerSegment.isToday ? Theme.buttonHover : Theme.surfaceTextHover;
                                        return "transparent";
                                    }
                                    Behavior on color { ColorAnimation { duration: Theme.shorterDuration; easing.type: Theme.standardEasing } }
                                }

                                DankRipple {
                                    id: headerRipple
                                    cornerRadius: parent.radius
                                    rippleColor: isToday ? Theme.buttonText : Theme.surfaceVariantText
                                }

                                Row {
                                    id: headerTextRow
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingS
                                    
                                    DankIcon {
                                        name: "check"
                                        size: Theme.iconSizeSmall
                                        color: Theme.buttonText
                                        visible: headerSegment.isToday
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    
                                    StyledText {
                                        text: modelData.date !== "" ? modelData.day + ", " + modelData.date : modelData.day
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: headerSegment.isToday ? Font.Medium : Font.Normal
                                        color: headerSegment.isToday ? Theme.buttonText : Theme.surfaceVariantText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                
                                MouseArea {
                                    id: headerMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: (mouse) => {
                                        headerRipple.trigger(mouse.x, mouse.y);
                                    }
                                }
                            }

                            // Removed scrollAnimation as clicking headers should only give visual feedback.


                            // Vertical Line from Header to first card
                            Rectangle {
                                width: 3
                                height: 16
                                anchors.left: parent.left
                                anchors.leftMargin: dayColumn.timelineX - 1.5 // 1.5 is half of 3px width
                                color: dayDelegate.isToday ? "#0005FF" : Theme.withAlpha(Theme.surfaceVariantText, 0.2)
                                radius: 1.5
                            }

                            // Shows Inner List
                            DankListView {
                                id: innerListView
                                width: parent.width
                                height: parent.height - 40 - 16
                                model: modelData.shows
                                 spacing: 0 // Using internal delegate lines
                                 clip: true
                                 topMargin: 4
                                 bottomMargin: 4

                                readonly property Item outerDelegate: dayDelegate
                                readonly property int timelineX: dayColumn.timelineX

                                // Smooth scroll to "Now" marker
                                Timer {
                                    id: innerScrollTimer
                                    interval: 500
                                    repeat: false
                                    onTriggered: {
                                        if (!innerListView.outerDelegate.modelData || !innerListView.outerDelegate.modelData.shows) return;
                                        // Find index of the "Now" show
                                        let nowIdx = -1;
                                        for (let i = 0; i < innerListView.outerDelegate.modelData.shows.length; i++) {
                                            let show = innerListView.outerDelegate.modelData.shows[i];
                                            if (!show.timestamp) continue;
                                            let showTime = parseFloat(show.timestamp);
                                            let prevShowTime = i > 0 ? parseFloat(innerListView.outerDelegate.modelData.shows[i-1].timestamp) : 0;
                                            let now = root.currentTime;
                                            if (now >= prevShowTime && now < showTime) {
                                                nowIdx = i;
                                                break;
                                            }
                                        }

                                        if (nowIdx !== -1 && dayDelegate.isToday) { // Only scroll for today
                                            // Smooth scroll to target
                                            // positionViewAtIndex doesn't animate, so we could calculate Y
                                            // For simplicity, we'll just position it, but user wants "animation"
                                            // We'll use a number animation on contentY
                                            let targetY = 0;
                                            // Approximate height calculation or use a helper
                                            // Since cards vary height (Now marker), we'll just use a direct transition if possible
                                            innerListView.positionViewAtIndex(nowIdx, ListView.Beginning);
                                        }
                                    }
                                }

                                Connections {
                                    target: root
                                    onScheduleDataChanged: innerScrollTimer.restart()
                                }

                                 footer: Component {
                                     Item {
                                         width: innerListView.width
                                         height: 30
                                         visible: {
                                             if (!dayDelegate.isToday) return false;
                                             var shows = innerListView.model;
                                             if (!shows || shows.length === 0) return false;
                                             var lastShowTime = parseFloat(shows[shows.length-1].timestamp);
                                             return root.currentTime >= lastShowTime;
                                         }

                                         // Vertical Timeline Segment
                                         Rectangle {
                                             width: 3
                                             anchors.top: parent.top
                                             anchors.bottom: parent.bottom
                                             anchors.left: parent.left
                                             anchors.leftMargin: innerListView.timelineX - 1.5
                                             color: "#0005FF"
                                             z: -1
                                         }

                                         // Dot on timeline axis
                                         Rectangle {
                                             id: footerDot
                                             width: 8; height: 8; radius: 4
                                             color: Theme.withAlpha(Theme.buttonBg, 0.7)
                                             x: innerListView.timelineX - 4
                                             anchors.verticalCenter: parent.verticalCenter
                                             z: 2
                                         }

                                         // Horizontal line to chip
                                         Rectangle {
                                             height: 1
                                             anchors.left: footerDot.horizontalCenter
                                             anchors.right: footerChip.left
                                             anchors.rightMargin: 4
                                             anchors.verticalCenter: parent.verticalCenter
                                             color: Theme.withAlpha(Theme.primary, 0.4)
                                             z: 1
                                         }

                                         // Time Chip
                                         Rectangle {
                                             id: footerChip
                                             anchors.right: parent.right
                                             anchors.rightMargin: 16 // Room for scrollbar
                                             anchors.verticalCenter: parent.verticalCenter
                                             width: Math.max(footerTime.implicitWidth + 12, 50)
                                             height: 30
                                             radius: 10
                                             color: Theme.withAlpha(Theme.buttonBg, 0.7)

                                             StyledText {
                                                 id: footerTime
                                                  anchors.centerIn: parent
                                                  text: {
                                                      var fmt = root.timeFormat === "24h" ? "HH:mm" : "h:mm AP";
                                                      if (root.showSeconds) {
                                                          fmt = root.timeFormat === "24h" ? "HH:mm:ss" : "h:mm:ss AP";
                                                      }
                                                      return Qt.formatTime(new Date(root.currentTime * 1000), fmt);
                                                  }
                                                  color: Theme.buttonText
                                                 font.bold: true
                                                 font.pixelSize: 10
                                             }
                                         }
                                     }
                                 }

                                 delegate: Item {
                                     width: innerListView.width
                                     height: (nowMarker.visible ? nowMarker.height : 0) + (gapLine.visible ? gapLine.height : 0) + cardRect.height - 1 // -1 matches Column spacing to avoid gaps

                                      Column {
                                          anchors.fill: parent
                                          z: cardMouseArea.containsMouse ? 10 : 1 // Bring to front on hover
                                         spacing: -1 // Negative spacing to ensure lines overlap slightly and connect seamlessly

                                         // Now Marker
                                         Item {
                                             id: nowMarker
                                             width: parent.width
                                             height: 30
                                             visible: {
                                                 if (!dayDelegate.isToday) return false;
                                                 if (!modelData.timestamp) return false;
                                                 var shows = innerListView.model;
                                                 if (!shows) return false;
                                                 var showTime = parseFloat(modelData.timestamp);
                                                 var prevShowTime = index > 0 ? parseFloat(shows[index-1].timestamp) : 0;
                                                 var now = root.currentTime;
                                                 return now >= prevShowTime && now < showTime;
                                             }

                                             // Vertical Timeline Segment inside marker
                                             Rectangle {
                                                 width: 3
                                                 anchors.top: parent.top
                                                 anchors.bottom: parent.bottom
                                                 anchors.bottomMargin: -2 // Bleed into card for perfect connectivity
                                                 anchors.left: parent.left
                                                 anchors.leftMargin: innerListView.timelineX - 1.5
                                                 color: "#0005FF"
                                                 z: -1 // Behind potential card border/overlap
                                             }

                                             // Dot on timeline axis
                                             Rectangle {
                                                 id: nowDot
                                                 width: 8; height: 8; radius: 4
                                                 color: Theme.withAlpha(Theme.buttonBg, 0.7)
                                                 x: innerListView.timelineX - 4
                                                 anchors.verticalCenter: parent.verticalCenter
                                                 z: 3
                                             }

                                             // Horizontal line to chip
                                             Rectangle {
                                                 height: 1
                                                 anchors.left: nowDot.horizontalCenter
                                                 anchors.right: nowChip.left
                                                 anchors.rightMargin: 4
                                                 anchors.verticalCenter: parent.verticalCenter
                                                 color: Theme.withAlpha(Theme.primary, 0.4)
                                                 z: 1
                                             }

                                             // Time Chip
                                              Rectangle {
                                                  id: nowChip
                                                  anchors.right: parent.right
                                                  anchors.rightMargin: 16 // Room for scrollbar
                                                 anchors.verticalCenter: parent.verticalCenter
                                                 width: Math.max(nowTime.implicitWidth + 12, 50)
                                                 height: 20
                                                 radius: 10
                                                 color: Theme.withAlpha(Theme.buttonBg, 0.7)

                                                  StyledText {
                                                      id: nowTime
                                                      anchors.centerIn: parent
                                                      text: {
                                                          var fmt = root.timeFormat === "24h" ? "HH:mm" : "h:mm AP";
                                                          if (root.showSeconds) {
                                                              fmt = root.timeFormat === "24h" ? "HH:mm:ss" : "h:mm:ss AP";
                                                          }
                                                          return Qt.formatTime(new Date(root.currentTime * 1000), fmt);
                                                      }
                                                      color: Theme.buttonText
                                                      font.bold: true
                                                      font.pixelSize: 12
                                                  }
                                              }
                                          }

                                         // Vertical Gap between cards
                                         Rectangle {
                                             id: gapLine
                                             width: 3
                                             height: 16
                                             anchors.left: parent.left
                                             anchors.leftMargin: innerListView.timelineX - 1.5
                                             anchors.bottomMargin: -2 // Bleed into card
                                             color: dayDelegate.isToday ? "#0005FF" : Theme.withAlpha(Theme.surfaceVariantText, 0.2)
                                             visible: !nowMarker.visible
                                             z: -1
                                         }

                                        StyledRect {
                                            id: cardRect
                                            width: parent.width - 16 // Room for scrollbar
                                            anchors.horizontalCenter: parent.horizontalCenter // Center to prevent clipping on edges
                                            height: 190
                                            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                                            radius: 20
                                            
                                            property bool hasStatus: modelData.libraryStatus !== "none" && modelData.libraryStatus !== "" && modelData.libraryStatus !== undefined
                                            
                                            property color statusColor: {
                                                if (!hasStatus) return Theme.primary;
                                                switch(modelData.libraryStatus) {
                                                    case "watching": return "#4CAF50"; // Green
                                                    case "rewatching": return "#4CAF50"; // Green
                                                    case "completed": return "#6B89C9"; // Blue
                                                    case "planning": return "#9C27B0"; // Purple
                                                    case "considering": return "#FFC107"; // Gold/Yellow
                                                    case "paused": return "#FE8E14"; // Orange
                                                    case "dropped": return "#AC675D"; // Reddish-Brown
                                                    case "skipping": return "#F44336"; // Red
                                                    case "in-list": return Theme.primary;
                                                    default: return Theme.primary;
                                                }
                                            }

                                            border.width: 2
                                            border.color: cardMouseArea.containsMouse 
                                                ? Theme.withAlpha(statusColor, 0.7)
                                                : Theme.withAlpha(Theme.surfaceVariantText, 0.15)

                                            layer.enabled: true
                                            layer.smooth: true
                                            layer.effect: DropShadow {
                                                transparentBorder: true
                                                horizontalOffset: 0
                                                verticalOffset: 3
                                                radius: 12.0
                                                samples: 24
                                                color: Theme.withAlpha(Theme.shadowColor || "#000000", 0.35)
                                            }

                                            Behavior on border.color { ColorAnimation { duration: 200; easing.type: Easing.OutQuad } }
                                            Behavior on border.width { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                                            
                                            scale: cardMouseArea.containsMouse ? 1.02 : 1.0
                                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

                                            DankRipple {
                                                id: cardRipple
                                                cornerRadius: parent.radius
                                                rippleColor: Theme.primary
                                                anchors.fill: parent
                                            }

                                            MouseArea {
                                                id: cardMouseArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: root.cardClickAction === "none" ? Qt.ArrowCursor : Qt.PointingHandCursor
                                                // No z-index explicitly, just defined before the layouts 
                                                // so buttons inside layouts can take precedence.
                                                onPressed: (mouse) => {
                                                    if (root.cardClickAction !== "none") cardRipple.trigger(mouse.x, mouse.y);
                                                }
                                                onClicked: {
                                                    if (root.cardClickAction === "anime_entry" && modelData.animeLink) {
                                                        root.openUrl(modelData.animeLink)
                                                    } else if (root.cardClickAction === "watch_page" && modelData.watchLink) {
                                                        root.openUrl(modelData.watchLink)
                                                    }
                                                }
                                            }

                                            ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 8

                                            // Top Bar: Time, Countdown, and Bookmark
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 4

                                                // Time Chip
                                                Rectangle {
                                                    id: timeChip
                                                    Layout.preferredWidth: timeText.implicitWidth + 12
                                                    Layout.preferredHeight: 18
                                                    color: dayDelegate.isToday ? Theme.withAlpha(Theme.buttonBg, 0.7) : Theme.withAlpha(Theme.surfaceVariant, 0.5)
                                                    radius: 9
                                                    // Center on timelineX (40 - 12px margin = 28)
                                                    Layout.leftMargin: (dayColumn.timelineX - 12) - (width / 2)

                                                    StyledText {
                                                        id: timeText
                                                        anchors.centerIn: parent
                                                        text: {
                                                            if (modelData.timestamp) {
                                                                var d = new Date(modelData.timestamp * 1000);
                                                                if (root.timeFormat === "24h") {
                                                                    return Qt.formatTime(d, "HH:mm");
                                                                } else {
                                                                    return Qt.formatTime(d, "h:mm AP");
                                                                }
                                                            }
                                                            return modelData.time;
                                                        }
                                                        font.pixelSize: 9
                                                        font.weight: Font.Black
                                                        font.capitalization: Font.AllUppercase
                                                        color: dayDelegate.isToday ? Theme.buttonText : Theme.surfaceVariantText
                                                    }
                                                }

                                                StyledText {
                                                    id: countdownText
                                                    text: modelData.countdown
                                                    font.pixelSize: 12
                                                    color: Theme.surfaceVariantText
                                                    opacity: 0.6
                                                    Layout.fillWidth: true
                                                    horizontalAlignment: Text.AlignHCenter
                                                    visible: text !== ""
                                                }

                                                // Spacer to push bookmark to the right when countdown is hidden
                                                Item {
                                                    Layout.fillWidth: !countdownText.visible
                                                }

                                                  // Bookmark & Progress Container
                                                  RowLayout {
                                                      id: statusContainer
                                                      spacing: 4
                                                      Layout.rightMargin: (dayColumn.timelineX - 12) - (timeText.implicitWidth / 2)



                                                      // Bookmark Button
                                                      Item {
                                                          id: bookmarkItem
                                                          width: 24
                                                          height: 24
                                                          Layout.alignment: Qt.AlignVCenter

                                                          property color statusColor: cardRect.statusColor === "transparent" ? Theme.surfaceVariantText : cardRect.statusColor

                                                          property string iconName: modelData.libraryStatus === "none" ? "unmarked" : modelData.libraryStatus

                                                          Image {
                                                              id: statusIcon
                                                              source: "file:///home/JD/Downloads/Projects/LiveChartPlugin/icons/" + bookmarkItem.iconName + ".svg"
                                                              width: 20
                                                              height: 20
                                                              anchors.centerIn: parent
                                                              anchors.verticalCenterOffset: -1 // Shift up for visual balance in bookmark
                                                              visible: modelData.libraryStatus !== "none" || bookmarkMA.containsMouse
                                                              smooth: true
                                                              mipmap: true
                                                              opacity: bookmarkMA.containsMouse ? 1.0 : 0.8
                                                          }

                                                          // Default bookmark icon for "none" status if hovered (optional, fallback)
                                                          DankIcon {
                                                              visible: modelData.libraryStatus === "none" && !bookmarkMA.containsMouse
                                                              name: "bookmark-outline"
                                                              size: 20
                                                              color: Theme.surfaceVariantText
                                                              opacity: 0.6
                                                              anchors.centerIn: parent
                                                          }

                                                          DankRipple {
                                                              id: bookmarkRipple
                                                              cornerRadius: 12
                                                              rippleColor: Theme.primary
                                                          }

                                                          MouseArea {
                                                              id: bookmarkMA
                                                              anchors.fill: parent
                                                              hoverEnabled: true
                                                              cursorShape: Qt.PointingHandCursor
                                                              onPressed: (mouse) => {
                                                                  bookmarkRipple.trigger(mouse.x, mouse.y);
                                                              }
                                                              onClicked: {
                                                                  if (modelData.animeLink) {
                                                                      root.openUrl(modelData.animeLink)
                                                                  }
                                                              }
                                                          }
                                                      }
                                                  }
                                            }

                                            // Edge-to-Edge Unified Separator
                                            Item {
                                                Layout.fillWidth: true
                                                Layout.leftMargin: -12
                                                Layout.rightMargin: -12
                                                Layout.preferredHeight: 13 // 1px line + 12px shadow

                                                Rectangle {
                                                    id: sepLine
                                                    anchors.top: parent.top
                                                    width: parent.width
                                                    height: 1
                                                    color: Theme.withAlpha(Theme.surfaceVariantText, 0.15)
                                                }

                                                Rectangle {
                                                    anchors.top: sepLine.bottom
                                                    width: parent.width
                                                    height: 12
                                                    gradient: Gradient {
                                                        GradientStop { position: 0.0; color: Theme.withAlpha("#000000", 0.06) }
                                                        GradientStop { position: 0.3; color: Theme.withAlpha("#000000", 0.02) }
                                                        GradientStop { position: 1.0; color: "transparent" }
                                                    }
                                                }
                                            }

                                            // Main Content
                                            // Main Content Container (Prevents layout interference between MouseArea and Layout children)
                                            Item {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true

                                                RowLayout {
                                                    anchors.fill: parent
                                                    spacing: 12

                                                    // Cover Area (Poster)
                                                    Item {
                                                        id: coverArea
                                                        Layout.preferredWidth: 80 
                                                        Layout.preferredHeight: 110 
                                                        Layout.alignment: Qt.AlignTop

                                                        Rectangle {
                                                            id: coverMask
                                                            anchors.fill: parent
                                                            radius: 12
                                                            visible: false
                                                        }

                                                        Item {
                                                            anchors.fill: parent
                                                            layer.enabled: true
                                                            layer.effect: OpacityMask {
                                                                maskSource: coverMask
                                                            }

                                                            Image {
                                                                anchors.fill: parent
                                                                source: modelData.image || ""
                                                                fillMode: Image.PreserveAspectCrop
                                                            }
                                                        }

                                                        // Cover Image MouseArea
                                                        // This sits exactly on the cover image and beneath the watch button.
                                                        MouseArea {
                                                            id: coverImageMA
                                                            anchors.fill: parent
                                                            enabled: root.coverClickAction !== "none"
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (root.coverClickAction === "anime_entry" && modelData.animeLink) {
                                                                    root.openUrl(modelData.animeLink)
                                                                }
                                                            }
                                                        }

                                                        // Watch Button
                                                        Rectangle {
                                                            id: watchBtn
                                                            anchors.horizontalCenter: parent.horizontalCenter
                                                            anchors.bottom: parent.bottom
                                                            anchors.bottomMargin: -10
                                                            width: 28
                                                            height: 28
                                                            radius: 14
                                                            color: "white"
                                                            border.width: 3
                                                            border.color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 1)
                                                            visible: modelData.watchLink !== ""
                                                            z: 10 // Ensure it's above cover click handler

                                                            DankRipple {
                                                                id: watchRipple
                                                                cornerRadius: parent.radius
                                                                rippleColor: Theme.primary
                                                            }

                                                            Rectangle {
                                                                id: watchIconMask
                                                                anchors.fill: parent
                                                                anchors.margins: 4
                                                                radius: width / 2
                                                                visible: false
                                                            }

                                                            Item {
                                                                anchors.fill: parent
                                                                anchors.margins: 4
                                                                layer.enabled: true
                                                                layer.effect: OpacityMask {
                                                                    maskSource: watchIconMask
                                                                }

                                                                Image {
                                                                    id: watchIcon
                                                                    anchors.fill: parent
                                                                    // Robust favicon fallback
                                                                    source: modelData.sourceIcon || (modelData.siteDomain ? "https://www.google.com/s2/favicons?domain=" + modelData.siteDomain + "&sz=64" : "")
                                                                    visible: source.toString() !== ""
                                                                }
                                                            }

                                                            DankIcon {
                                                                anchors.centerIn: parent
                                                                name: "link"
                                                                size: 16
                                                                color: Theme.withAlpha(Theme.buttonBg, 0.7)
                                                                visible: watchIcon.source.toString() === ""
                                                            }

                                                            MouseArea {
                                                                id: watchStreamMA
                                                                anchors.fill: parent
                                                                cursorShape: root.watchStreamClickAction === "none" ? Qt.ArrowCursor : Qt.PointingHandCursor
                                                                onPressed: (mouse) => {
                                                                    if (root.watchStreamClickAction !== "none") watchRipple.trigger(mouse.x, mouse.y);
                                                                }
                                                                onClicked: {
                                                                    if (root.watchStreamClickAction === "watch_page" && modelData.watchLink) {
                                                                        root.openUrl(modelData.watchLink);
                                                                    }
                                                                    // Click is consumed here
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // Info Content
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        Layout.alignment: Qt.AlignTop
                                                        spacing: 4

                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: modelData.title
                                                            font.pixelSize: Theme.fontSizeMedium
                                                            font.weight: Font.DemiBold
                                                            color: Theme.surfaceText
                                                            wrapMode: Text.Wrap
                                                            maximumLineCount: 2
                                                            elide: Text.ElideRight
                                                        }

                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: modelData.episodeInfo
                                                            font.pixelSize: Theme.fontSizeSmall
                                                            color: Theme.surfaceVariantText
                                                            opacity: 0.8
                                                            wrapMode: Text.Wrap
                                                            elide: Text.ElideRight
                                                        }
                                                    } // ColumnLayout (Info)
                                                } // RowLayout (Main Content)


                                            } // Item (Main Content Container)
                                        } // ColumnLayout (Card)

                                        // Mark as Watched Button
                                        Rectangle {
                                            id: markWatchedBtn
                                            width: 24
                                            height: 24
                                            radius: 12
                                            color: "white"
                                            border.width: 3
                                            border.color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 1)
                                            visible: !modelData.isWatched
                                            z: 30

                                            // EDIT POSITION HERE:
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.rightMargin: 12
                                            anchors.bottomMargin: 12

                                            DankIcon {
                                                anchors.centerIn: parent
                                                name: "check"
                                                size: 14
                                                color: Theme.isDark ? Theme.primary : "black"
                                            }

                                            DankRipple {
                                                id: markRipple
                                                cornerRadius: parent.radius
                                                rippleColor: Theme.primary
                                            }

                                             MouseArea {
                                                 anchors.fill: parent
                                                 enabled: root.coverClickAction !== "none"
                                                 cursorShape: Qt.PointingHandCursor
                                                 onPressed: (mouse) => {
                                                     markRipple.trigger(mouse.x, mouse.y);
                                                 }
                                                 onClicked: {
                                                     if (root.coverClickAction === "anime_entry" && modelData.animeLink) {
                                                         root.openUrl(modelData.animeLink)
                                                     }
                                                 }
                                             }
                                        }
                                    } // Rectangle (cardRect)
                                } // Column (Show Column)
                            } // Item (Inner delegate)
                        } // DankListView (Inner)
                    } // Column (Weekly column)
                } // Item (Weekly delegate)
            } // DankListView (Weekly)
        } // Column (Popout Main Column)
    } // PopoutComponent
} // Component (popoutContent)
} // PluginComponent
