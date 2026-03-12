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
    property int updateIntervalSeconds: pluginData.updateInterval || 3600
    property string browserName: pluginData.browser || "firefox"

    // Dynamic today date for default fetching
    property string todayDateStr: {
        var d = new Date();
        var year = d.getFullYear();
        var month = ("0" + (d.getMonth() + 1)).slice(-2);
        var day = ("0" + d.getDate()).slice(-2);
        return year + "-" + month + "-" + day;
    }
    property string targetDate: todayDateStr
    
    // Internal state
    property var scheduleData: []
    property string statusMessage: "Initializing..."
    property bool isLoading: true
    
    property bool minimumWidth: pluginData.minimumWidth !== undefined ? pluginData.minimumWidth : false
    
    // Day name for dynamic coloring
    property string currentDayName: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][new Date().getDay()]
    
    // Timer to update "Now" position
    property double currentTime: Date.now() / 1000
    Timer {
        interval: 30000 // 30 seconds
        running: true
        repeat: true
        onTriggered: root.currentTime = Date.now() / 1000
    }

    // Standard DMS widget capability popout styling
    // Standard DMS widget capability popout styling
    popoutWidth: 2000 // Increased from 1800 to accommodate wider cards

    Timer {
        id: updateTimer
        interval: root.updateIntervalSeconds * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.isLoading = true;
            root.statusMessage = "Fetching schedule...";
            fetchProcess.running = true;
        }
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
        command: [
            "python3",
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
                        root.scheduleData = parsed.data;
                        let count = 0;
                        let targetIndex = 0;
                        for (let i = 0; i < parsed.data.length; i++) {
                            count += parsed.data[i].shows.length;
                            if (parsed.data[i].day === root.currentDayName) {
                                targetIndex = i;
                            }
                        }
                        root.statusMessage = "Loaded " + count + " active anime for next 7 days";
                        scrollTimer.focusIndex = targetIndex;
                        scrollTimer.restart();
                    } else {
                        root.statusMessage = parsed.error || "Failed to fetch data";
                        root.scheduleData = [];
                    }
                } catch (e) {
                    root.statusMessage = "Error parsing output from Python script.";
                    console.error("LiveChart Parser Error:", e, "| Output:", output);
                }
            }
        }
        
        onExited: {
            if (exitCode !== 0) {
                root.isLoading = false;
                root.statusMessage = "Python script exited with code " + exitCode;
            }
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS
            DankIcon { 
                name: "calendar_month"
                size: root.iconSize
                color: Theme.widgetIconColor
                anchors.verticalCenter: parent.verticalCenter 
            }
            Item {
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: statusText.paintedWidth
                implicitHeight: statusText.implicitHeight
                width: implicitWidth; height: implicitHeight
                
                StyledText {
                    id: statusText
                    anchors.fill: parent
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.widgetTextColor
                    text: {
                        if (root.isLoading) return "Fetching...";
                        let count = 0;
                        for (let i = 0; i < root.scheduleData.length; i++) {
                            count += root.scheduleData[i].shows.length;
                        }
                        return `Anime (${count})`;
                    }
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 1
            DankIcon {
                name: "calendar_month"
                size: root.iconSize
                color: Theme.widgetIconColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                text: {
                    if (root.isLoading) return "...";
                    let count = 0;
                    for (let i = 0; i < root.scheduleData.length; i++) {
                        count += root.scheduleData[i].shows.length;
                    }
                    return count.toString();
                }
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.widgetTextColor
                anchors.horizontalCenter: parent.horizontalCenter
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

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.cornerRadius * 1.5
                        gradient: Gradient {
                            GradientStop {
                                position: 0.0
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                            }
                            GradientStop {
                                position: 1.0
                                color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.08)
                            }
                        }
                        border.width: 1
                        border.color: Theme.withAlpha(Theme.primary, 0.15)
                        color: Theme.withAlpha(Theme.surfaceContainer, 0.6)
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingM

                        Item {
                            width: 40
                            height: 40
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                anchors.fill: parent
                                radius: 20
                                color: Theme.withAlpha(Theme.primary, 0.1)
                            }

                            Image {
                                source: "https://www.google.com/s2/favicons?domain=livechart.me&sz=64"
                                width: 24
                                height: 24
                                sourceSize.width: 24
                                sourceSize.height: 24
                                anchors.centerIn: parent
                                fillMode: Image.PreserveAspectFit
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            StyledText {
                                text: "LiveChart.me"
                                font.bold: true
                                font.pixelSize: Theme.fontSizeLarge
                                color: Theme.surfaceText
                            }

                            StyledText {
                                text: root.statusMessage
                                font.pixelSize: Theme.fontSizeSmall
                                color: root.isLoading ? Theme.secondary : Theme.primary
                            }
                        }
                    }

                    // Refresh button
                    DankButton {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        buttonHeight: 40
                        horizontalPadding: 0
                        iconName: "refresh"
                        iconSize: 22
                        backgroundColor: "transparent"
                        textColor: Theme.primary
                        enableRipple: true

                        onClicked: {
                            root.isLoading = true;
                            root.statusMessage = "Fetching schedule...";
                            fetchProcess.running = true;
                        }
                    }
                }

                // Error state explicitly shown if not loading and no data
                StyledText {
                    id: errorText
                    visible: !root.isLoading && root.scheduleData.length === 0
                    text: root.statusMessage
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeMedium
                    width: parent.width
                    wrapMode: Text.Wrap
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
                        width: (ListView.view.width - (ListView.view.spacing * 6)) / 7
                        height: ListView.view.height

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
                                
                                property bool isToday: modelData.day === root.currentDayName
                                
                                color: isToday ? Theme.withAlpha(Theme.buttonBg, 0.7) : Theme.withAlpha(Theme.surfaceVariant, 0.5)
                                
                                // Selective corner rounding for pill effect
                                property int edgeRadius: Theme.cornerRadius
                                property int innerRadius: Math.min(4, Theme.cornerRadius) // Reverted to 4
                                
                                topLeftRadius: index === 0 ? edgeRadius : innerRadius
                                bottomLeftRadius: index === 0 ? edgeRadius : innerRadius
                                topRightRadius: index === 6 ? edgeRadius : innerRadius
                                bottomRightRadius: index === 6 ? edgeRadius : innerRadius

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
                                    anchors.fill: parent
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
                                color: modelData.day === root.currentDayName ? "#0005FF" : Theme.withAlpha(Theme.surfaceVariantText, 0.2)
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

                                        if (nowIdx !== -1) {
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
                                            if (innerListView.outerDelegate.modelData.day !== root.currentDayName) return false;
                                            var shows = innerListView.outerDelegate.modelData.shows;
                                            if (!shows || shows.length === 0) return false;
                                            var lastShowTime = parseFloat(shows[shows.length-1].timestamp);
                                            return root.currentTime >= lastShowTime;
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 4
                                            anchors.rightMargin: 12
                                            spacing: 8

                                            Rectangle {
                                                width: 3
                                                height: parent.height
                                                anchors.left: parent.left
                                                anchors.leftMargin: innerListView.timelineX - 1.5 - 4
                                                color: Theme.withAlpha(Theme.surfaceVariantText, 0.2)
                                            }

                                            Rectangle {
                                                Layout.preferredWidth: 10
                                                height: 10
                                                radius: 5
                                                color: Theme.error
                                                Layout.leftMargin: innerListView.timelineX - 4 - 5
                                            }

                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 1
                                                color: Theme.withAlpha(Theme.error, 0.4)
                                            }

                                            StyledText {
                                                text: (root.timeFormat === "24h" ?
                                                    Qt.formatTime(new Date(), "HH:mm") :
                                                    Qt.formatTime(new Date(), "h:mm AP"))
                                                color: Theme.error
                                                font.bold: true
                                                font.pixelSize: 10
                                                font.capitalization: Font.AllUppercase
                                            }
                                        }
                                    }
                                }

                                delegate: Item {
                                    width: innerListView.width
                                    height: (nowMarker.visible ? nowMarker.height : 0) + (connectorLine.visible ? connectorLine.height : 0) + cardRect.height + 1 // +1 for overlap/no gap

                                    Column {
                                        anchors.fill: parent
                                        spacing: -1 // Negative spacing to ensure lines overlap slightly and connect seamlessly

                                        // Now Marker
                                        Item {
                                            id: nowMarker
                                            width: parent.width
                                            height: 30
                                            // Show "Now" marker if this show is the next one to air
                                            visible: {
                                                if (!modelData.timestamp) return false;
                                                var shows = ListView.view ? ListView.view.model : null;
                                                if (!shows) return false;
                                                var showTime = parseFloat(modelData.timestamp);
                                                var prevShowTime = index > 0 ? parseFloat(shows[index-1].timestamp) : 0;
                                                var now = root.currentTime;
                                                return now >= prevShowTime && now < showTime;
                                            }

                                             RowLayout {
                                                 anchors.fill: parent
                                                 anchors.leftMargin: 4 // Match card internal padding for alignment
                                                 anchors.rightMargin: 12
                                                 spacing: 8

                                                 // Vertical line through marker
                                                 Rectangle {
                                                     width: 3
                                                     height: parent.height
                                                     anchors.left: parent.left
                                                     anchors.leftMargin: innerListView.timelineX - 1.5 - 4 // -4 for RowLayout margin
                                                     visible: index > 0
                                                     color: Theme.withAlpha(Theme.surfaceVariantText, 0.2)
                                                 }

                                                 Rectangle {
                                                     id: nowCircle
                                                     Layout.preferredWidth: 10
                                                     height: 10
                                                     radius: 5
                                                     color: Theme.error
                                                     Layout.leftMargin: innerListView.timelineX - 4 - 5
                                                 }

                                                 Rectangle {
                                                     Layout.fillWidth: true
                                                     height: 1
                                                     color: Theme.withAlpha(Theme.error, 0.4)
                                                 }

                                                 StyledText {
                                                     text: (root.timeFormat === "24h" ?
                                                         Qt.formatTime(new Date(), "HH:mm") :
                                                         Qt.formatTime(new Date(), "h:mm AP"))
                                                     color: Theme.error
                                                     font.bold: true
                                                     font.pixelSize: 10
                                                     font.capitalization: Font.AllUppercase
                                                 }
                                             }
                                        }

                                        // Connector Line (Vertical) between cards
                                        Rectangle {
                                            id: connectorLine
                                            width: 3
                                            height: 16
                                            anchors.left: parent.left
                                            anchors.leftMargin: innerListView.timelineX - 1.5
                                            color: dayDelegate.modelData.day === root.currentDayName ? "#0005FF" : Theme.withAlpha(Theme.surfaceVariantText, 0.2)
                                            radius: 1.5
                                            visible: index > 0 && !nowMarker.visible
                                        }

                                        Rectangle {
                                            id: cardRect
                                            width: parent.width
                                            height: 190 // Further increased height
                                            color: cardMouseArea.containsMouse ? Theme.withAlpha(Theme.surfaceVariant, 0.9) : Theme.withAlpha(Theme.surfaceContainer, 0.8)
                                            radius: 20
                                            border.width: 1
                                            border.color: cardMouseArea.containsMouse ? Theme.primary : Theme.withAlpha(Theme.surfaceVariantText, 0.15)

                                            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                            Behavior on border.color { ColorAnimation { duration: Theme.shortDuration } }

                                            DankRipple {
                                                id: cardRipple
                                                cornerRadius: parent.radius
                                                rippleColor: Theme.primary
                                            }

                                            MouseArea {
                                                id: cardMouseArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onPressed: (mouse) => {
                                                    cardRipple.trigger(mouse.x, mouse.y);
                                                }
                                                onClicked: {
                                                    if (modelData.animeLink) {
                                                        Qt.openUrlExternally(modelData.animeLink)
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

                                                StyledText {
                                                    id: timeText
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
                                                    font.pixelSize: 10
                                                    font.weight: Font.ExtraBold
                                                    font.capitalization: Font.AllUppercase
                                                    color: Theme.primary
                                                    // Strictly centered on timelineX (40 - 12px margin = 28)
                                                    Layout.leftMargin: (dayColumn.timelineX - 12) - (implicitWidth / 2)
                                                }

                                                StyledText {
                                                    text: modelData.countdown
                                                    font.pixelSize: 10
                                                    color: Theme.surfaceVariantText
                                                    opacity: 0.6
                                                    Layout.fillWidth: true
                                                    horizontalAlignment: Text.AlignHCenter
                                                    visible: text !== ""
                                                }

                                                 // Bookmark Button (Custom 24px)
                                                 Item {
                                                     Layout.preferredWidth: 24
                                                     Layout.preferredHeight: 24
                                                     // Mirrored margin: timeline axis is at 40. Card RowLayout starts at 12.
                                                     // Axis offset from RowLayout edge is 28. Half icon width is 12.
                                                     // Gap from RowLayout right edge = 28 - 12 = 16.
                                                     Layout.rightMargin: 16

                                                     DankIcon {
                                                         name: "bookmark"
                                                         filled: false
                                                         size: 20
                                                         color: bookmarkMA.containsMouse ? Theme.primary : Theme.surfaceVariantText
                                                         opacity: bookmarkMA.containsMouse ? 1.0 : 0.6
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
                                                     }
                                                 }
                                            }

                                            // Glowing POP Ceiling Separator
                                            Item {
                                                Layout.fillWidth: true
                                                Layout.leftMargin: -12
                                                Layout.rightMargin: -12
                                                Layout.preferredHeight: 16
                                                clip: true

                                                Rectangle {
                                                    anchors.top: parent.top
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    height: 100
                                                    color: "transparent"
                                                    border.width: 1
                                                    border.color: Qt.rgba(0.5, 0.5, 0.5, 0.3)
                                                    radius: 12

                                                    // Generic drop shadow
                                                    Rectangle {
                                                        anchors.top: parent.top
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        height: 8 // Narrow for sharp shadow depth
                                                        radius: 12
                                                        z: -1

                                                        gradient: Gradient {
                                                            GradientStop {
                                                                position: 0.0
                                                                color: Qt.rgba(0, 0, 0, 0.35) // Neutral dark shadow
                                                            }
                                                            GradientStop {
                                                                position: 1.0
                                                                color: "transparent" // Fade to no shadow quickly
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // Main Content
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                spacing: 12

                                                // Poster Area
                                                Item {
                                                    Layout.preferredWidth: 80 // Increased
                                                    Layout.preferredHeight: 110 // Increased
                                                    Layout.alignment: Qt.AlignTop

                                                    Rectangle {
                                                        id: posterMask
                                                        anchors.fill: parent
                                                        radius: 12
                                                        visible: false
                                                    }

                                                    Item {
                                                        anchors.fill: parent
                                                        layer.enabled: true
                                                        layer.effect: OpacityMask {
                                                            maskSource: posterMask
                                                        }

                                                        Image {
                                                            anchors.fill: parent
                                                            source: modelData.image || ""
                                                            fillMode: Image.PreserveAspectCrop
                                                        }
                                                    }

                                                    // Watch Button
                                                    Rectangle {
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
                                                        z: 10

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
                                                            color: Theme.primary
                                                            visible: watchIcon.source.toString() === ""
                                                        }

                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onPressed: (mouse) => {
                                                                watchRipple.trigger(mouse.x, mouse.y);
                                                            }
                                                            onClicked: {
                                                                Qt.openUrlExternally(modelData.watchLink);
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
                                        } // ColumnLayout (Card)
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
