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
    property string currentDayName: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][new Date().getDay()]
    
    // Timer to update "Now" position
    property double currentTime: Date.now() / 1000
    Timer {
        interval: 1000 // 1 second for live updates
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.currentTime = Date.now() / 1000
    }

    // Standard DMS widget capability popout styling
    // Standard DMS widget capability popout styling
    popoutWidth: 2100 // Increased from 2000 to give more padding for scrollbars

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
                                color: iconMA.containsMouse ? Theme.withAlpha(Theme.primary, 0.2) : Theme.withAlpha(Theme.primary, 0.1)
                                border.width: 1
                                border.color: iconMA.containsMouse ? Theme.primary : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                Behavior on border.color { ColorAnimation { duration: Theme.shortDuration } }
                            }

                            DankRipple {
                                id: iconRipple
                                cornerRadius: 20
                                rippleColor: Theme.primary
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

                            MouseArea {
                                id: iconMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onPressed: (mouse) => iconRipple.trigger(mouse.x, mouse.y)
                                onClicked: Qt.openUrlExternally("https://www.livechart.me/schedule")
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
                        height: 40
                        horizontalPadding: 0
                        iconName: "refresh"
                        iconSize: 22
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
                        
                        property int dayIndex: index

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
                                
                                topLeftRadius: dayDelegate.dayIndex === 0 ? edgeRadius : innerRadius
                                bottomLeftRadius: dayDelegate.dayIndex === 0 ? edgeRadius : innerRadius
                                topRightRadius: dayDelegate.dayIndex === 6 ? edgeRadius : innerRadius
                                bottomRightRadius: dayDelegate.dayIndex === 6 ? edgeRadius : innerRadius

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

                                // Subtle bottom shadow for depth
                                Rectangle {
                                    anchors.top: parent.bottom
                                    width: parent.width
                                    height: 8
                                    z: -1 
                                    bottomLeftRadius: parent.bottomLeftRadius
                                    bottomRightRadius: parent.bottomRightRadius
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: Theme.withAlpha("#000000", 0.08) }
                                        GradientStop { position: 0.3; color: Theme.withAlpha("#000000", 0.03) }
                                        GradientStop { position: 1.0; color: "transparent" }
                                    }
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
                                color: dayDelegate.dayIndex === 0 ? "#0005FF" : Theme.withAlpha(Theme.surfaceVariantText, 0.2)
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

                                        if (nowIdx !== -1 && dayDelegate.dayIndex === 0) { // Only scroll for today
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
                                             if (dayDelegate.dayIndex !== 0) return false;
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
                                             color: Theme.primary
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
                                             color: Theme.primary

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
                                                  color: "#FFFFFF"
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
                                         z: 1 // On top of the line
                                         spacing: -1 // Negative spacing to ensure lines overlap slightly and connect seamlessly

                                         // Now Marker
                                         Item {
                                             id: nowMarker
                                             width: parent.width
                                             height: 30
                                             visible: {
                                                 if (dayDelegate.dayIndex !== 0) return false;
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
                                                 color: Theme.primary
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
                                                 color: Theme.primary

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
                                                     color: "#FFFFFF"
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
                                             color: dayDelegate.dayIndex === 0 ? "#0005FF" : Theme.withAlpha(Theme.surfaceVariantText, 0.2)
                                             visible: !nowMarker.visible
                                             z: -1
                                         }

                                        Rectangle {
                                            id: cardRect
                                            width: parent.width - 16 // Room for scrollbar
                                            height: 190
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

                                                 // Bookmark Button (Custom 24px)
                                                 Item {
                                                     id: bookmarkItem
                                                     Layout.preferredWidth: 24
                                                     Layout.preferredHeight: 24
                                                     // Mirrored margin: exactly match timeText's left margin
                                                     Layout.rightMargin: (dayColumn.timelineX - 12) - (timeText.implicitWidth / 2)

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
