import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects

import qs.Common
import qs.Widgets

Item {
    id: scheduleUI
    required property var widgetRoot
    property bool showSettingsMenu: false
    signal hideRequested()
    
    implicitWidth: 400
    implicitHeight: 640

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
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
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
                        sourceSize: Qt.size(24, 24)
                        anchors.centerIn: parent
                        fillMode: Image.PreserveAspectFit
                    }

                    MouseArea {
                        id: iconMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        z: 10
                        onPressed: (mouse) => iconRipple.trigger(mouse.x, mouse.y)
                        onClicked: {
                            widgetRoot.openUrl(widgetRoot.livechartIconClickAction === "livechart" ? "https://www.livechart.me" : "https://www.livechart.me/schedule")
                        }
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
                        text: widgetRoot.statusMessage
                        font.pixelSize: Theme.fontSizeSmall
                        color: widgetRoot.isLoading ? Theme.secondary : Theme.primary
                    }
                }
            }

            // Custom Navigation Group (Header Centered Version - Hidden on small layouts)
            Row {
                visible: widgetRoot.daysToShow > 2
                anchors.centerIn: parent
                spacing: Theme.spacingXS
                
                Repeater {
                    model: [
                        { text: "<<", action: () => widgetRoot.triggerFetch(), offset: -7 },
                        { text: "<", action: () => widgetRoot.triggerFetch(), offset: -1 },
                        { text: "Today", isTodayBtn: true, action: () => widgetRoot.triggerFetch(), offset: 0 },
                        { text: ">", action: () => widgetRoot.triggerFetch(), offset: 1 },
                        { text: ">>", action: () => widgetRoot.triggerFetch(), offset: 7 }
                    ]
                    
                    Rectangle {
                        id: navBtn
                        property bool isFirst: index === 0
                        property bool isLast: index === 4
                        property bool isTodayAtDefault: (modelData.isTodayBtn === true) && (widgetRoot.startDayOffset === parseInt(widgetRoot.pluginData.startDay || "0", 10))
                        
                        width: Math.max(0, Math.max(btnText.implicitWidth + Theme.spacingL * 2, 64) + (isTodayAtDefault ? 4 : 0))
                        height: 40
                        
                        color: isTodayAtDefault ? Theme.withAlpha(Theme.primary, 0.18) : (navHover.containsMouse ? Theme.withAlpha(Theme.primary, 0.10) : Theme.withAlpha(Theme.secondary, 0.04))
                        border.width: 1
                        border.color: isTodayAtDefault ? Theme.withAlpha(Theme.primary, 0.60) : (navHover.containsMouse ? Theme.withAlpha(Theme.primary, 0.40) : Theme.withAlpha(Theme.secondary, 0.15))
                        
                        topLeftRadius: isTodayAtDefault ? (height / 2) : (isFirst ? Theme.cornerRadius : Math.min(4, Theme.cornerRadius))
                        bottomLeftRadius: isTodayAtDefault ? (height / 2) : (isFirst ? Theme.cornerRadius : Math.min(4, Theme.cornerRadius))
                        topRightRadius: isTodayAtDefault ? (height / 2) : (isLast ? Theme.cornerRadius : Math.min(4, Theme.cornerRadius))
                        bottomRightRadius: isTodayAtDefault ? (height / 2) : (isLast ? Theme.cornerRadius : Math.min(4, Theme.cornerRadius))
                        
                        Behavior on width { enabled: true; NumberAnimation { duration: 150; easing.type: Easing.OutExpo } }
                        Behavior on topLeftRadius { enabled: true; NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                        Behavior on bottomLeftRadius { enabled: true; NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                        Behavior on topRightRadius { enabled: true; NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                        Behavior on bottomRightRadius { enabled: true; NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        
                        DankRipple {
                            id: navRipple
                            cornerRadius: isTodayAtDefault ? (parent.height / 2) : (isFirst || isLast ? Theme.cornerRadius : Math.min(4, Theme.cornerRadius))
                            rippleColor: Theme.primary
                        }
                        
                        Item {
                            anchors.fill: parent
                            
                            StyledText {
                                id: btnText
                                text: modelData.text
                                font.pixelSize: Theme.fontSizeMedium
                                anchors.centerIn: parent
                                color: isTodayAtDefault ? Theme.primary : Theme.surfaceVariantText
                                font.weight: isTodayAtDefault ? Font.Medium : Font.Normal
                                
                                // Tactile scale zoom exclusively for the Today anchor
                                scale: (navHover.containsMouse && modelData.isTodayBtn) ? 1.1 : 1.0
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                
                                transform: Translate {
                                    id: iconTranslate
                                    x: 0
                                    Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
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
                                    widgetRoot.startDayOffset = parseInt(widgetRoot.pluginData.startDay || "0", 10);
                                } else {
                                    widgetRoot.startDayOffset += modelData.offset;
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

            // Refresh Button using DankButton with Custom Animation
            DankButton {
                id: refreshButton
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                height: 40
                horizontalPadding: 0
                enableRipple: true
                radius: widgetRoot.isLoading ? (height / 2) : Theme.cornerRadius
                Behavior on radius { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }

                Connections {
                    target: widgetRoot
                    function onIsLoadingChanged() {
                        if (!widgetRoot.isLoading) {
                            refreshIcon.rotation = 0;
                        }
                    }
                }

                // Custom animated icon inside DankButton
                DankIcon {
                    id: refreshIcon
                    name: "refresh"
                    size: 22
                    color: Theme.primary
                    anchors.centerIn: parent

                    // Continuous rotation when loading
                    RotationAnimation {
                        id: loadingRotation
                        target: refreshIcon
                        property: "rotation"
                        from: 0
                        to: 360
                        duration: 1200
                        loops: Animation.Infinite
                        running: widgetRoot.isLoading
                    }

                    // Discrete rotation on hover
                    RotationAnimation {
                        id: hoverRotation
                        target: refreshIcon
                        property: "rotation"
                        from: 0
                        to: 360
                        duration: 2400
                        easing.type: Easing.OutQuart
                    }

                    // Rotation back to zero when hover ends
                    RotationAnimation {
                        id: resetRotation
                        target: refreshIcon
                        property: "rotation"
                        from: 360
                        to: 0
                        duration: 1000
                        easing.type: Easing.OutQuart
                    }
                }

                onHoveredChanged: {
                    if (widgetRoot.isLoading) return;
                    if (hovered) {
                        resetRotation.stop();
                        hoverRotation.start();
                    } else {
                        hoverRotation.stop();
                        resetRotation.start();
                    }
                }

                onClicked: {
                    if (widgetRoot.isLoading) return;
                    widgetRoot.isLoading = true;
                    // Ensure animations reset for loading state
                    hoverRotation.stop();
                    resetRotation.stop();
                    refreshIcon.rotation = 0;
                    
                    widgetRoot.fullScheduleData = []; // Clear current data instantly to show skeleton
                    widgetRoot.updateScheduleData();
                    widgetRoot.triggerFetch("Fetching schedule...");
                }
            }
        }

        // Dedicated Navigation Row (Standalone version for small layouts)
        // This appears between the header card and the schedule content when 1 or 2 days are shown.
        Rectangle {
            visible: widgetRoot.daysToShow <= 2
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
                        { text: "<<", action: () => widgetRoot.triggerFetch(), offset: -7 },
                        { text: "<", action: () => widgetRoot.triggerFetch(), offset: -1 },
                        { text: "Today", isTodayBtn: true, action: () => widgetRoot.triggerFetch(), offset: 0 },
                        { text: ">", action: () => widgetRoot.triggerFetch(), offset: 1 },
                        { text: ">>", action: () => widgetRoot.triggerFetch(), offset: 7 }
                    ]
                    
                    Rectangle {
                        id: navBtnStandalone
                        property bool isFirst: index === 0
                        property bool isLast: index === 4
                        property bool isTodayAtDefault: (modelData.isTodayBtn === true) && (widgetRoot.startDayOffset === parseInt(widgetRoot.pluginData.startDay || "0", 10))
                        
                        width: Math.max(0, Math.max(btnTextStandalone.implicitWidth + Theme.spacingL * 2, 64) + (isTodayAtDefault ? 4 : 0))
                        height: 40
                        
                        color: isTodayAtDefault ? Theme.withAlpha(Theme.primary, 0.18) : (navHoverStandalone.containsMouse ? Theme.withAlpha(Theme.primary, 0.10) : Theme.withAlpha(Theme.secondary, 0.04))
                        border.width: 1
                        border.color: isTodayAtDefault ? Theme.withAlpha(Theme.primary, 0.60) : (navHoverStandalone.containsMouse ? Theme.withAlpha(Theme.primary, 0.40) : Theme.withAlpha(Theme.secondary, 0.15))
                        
                        topLeftRadius: isTodayAtDefault ? (height / 2) : (isFirst ? Theme.cornerRadius : Math.min(4, Theme.cornerRadius))
                        bottomLeftRadius: isTodayAtDefault ? (height / 2) : (isFirst ? Theme.cornerRadius : Math.min(4, Theme.cornerRadius))
                        topRightRadius: isTodayAtDefault ? (height / 2) : (isLast ? Theme.cornerRadius : Math.min(4, Theme.cornerRadius))
                        bottomRightRadius: isTodayAtDefault ? (height / 2) : (isLast ? Theme.cornerRadius : Math.min(4, Theme.cornerRadius))
                        
                        Behavior on width { enabled: true; NumberAnimation { duration: 150; easing.type: Easing.OutExpo } }
                        Behavior on topLeftRadius { enabled: true; NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                        Behavior on bottomLeftRadius { enabled: true; NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                        Behavior on topRightRadius { enabled: true; NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                        Behavior on bottomRightRadius { enabled: true; NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        
                        DankRipple {
                            id: navRippleStandalone
                            cornerRadius: isTodayAtDefault ? (parent.height / 2) : (isFirst || isLast ? Theme.cornerRadius : Math.min(4, Theme.cornerRadius))
                            rippleColor: Theme.primary
                        }
                        
                        Item {
                            anchors.fill: parent
                            
                            StyledText {
                                id: btnTextStandalone
                                text: modelData.text
                                font.pixelSize: Theme.fontSizeMedium
                                anchors.centerIn: parent
                                color: isTodayAtDefault ? Theme.primary : Theme.surfaceVariantText
                                font.weight: isTodayAtDefault ? Font.Medium : Font.Normal
                                
                                scale: (navHoverStandalone.containsMouse && modelData.isTodayBtn) ? 1.1 : 1.0
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                
                                transform: Translate {
                                    id: iconTranslateStandalone
                                    x: 0
                                    Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
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
                                    widgetRoot.startDayOffset = parseInt(widgetRoot.pluginData.startDay || "0", 10);
                                } else {
                                    widgetRoot.startDayOffset += modelData.offset;
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
            visible: widgetRoot.isLoading
            width: parent.width
            height: 540
            spacing: 12
            
            Repeater {
                model: widgetRoot.daysToShow
                
                Column {
                    width: Math.max(0, (skeletonLoader.width - (skeletonLoader.spacing * Math.max(0, widgetRoot.daysToShow - 1))) / widgetRoot.daysToShow)
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
                                width: Math.max(0, parent.width - 16) // Accurately reserves 16px scrollbar gutter
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
                running: widgetRoot.isLoading
                loops: Animation.Infinite
                NumberAnimation { to: 0.3; duration: 800; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutQuad }
            }
        }

        // Error state explicitly shown if not loading and no data
        StyledText {
            id: errorText
            visible: !widgetRoot.isLoading && widgetRoot.scheduleData.length === 0
            text: widgetRoot.statusMessage
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeMedium
            width: parent.width
            wrapMode: Text.Wrap
        }

        // Schedule List Weekly Horizontal Grid
        DankListView {
            id: mainListView
            visible: widgetRoot.scheduleData.length > 0
            width: parent.width
            height: 540 // Increased to accommodate headers
            orientation: ListView.Horizontal
            model: widgetRoot.scheduleData
            spacing: 12 // Reduced gap
            clip: true
            
            delegate: Item {
                id: dayDelegate
                width: Math.max(0, (ListView.view.width - (ListView.view.spacing * Math.max(0, widgetRoot.daysToShow - 1))) / widgetRoot.daysToShow)
                height: ListView.view.height
                
                property int dayIndex: index
                readonly property bool isToday: modelData.day === widgetRoot.currentDayName && dayIndex === -widgetRoot.startDayOffset

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
                        Behavior on color { ColorAnimation { duration: 150; easing.type: Theme.standardEasing } }
                        
                        // Selective corner rounding for pill effect
                        property int edgeRadius: Theme.cornerRadius
                        property int innerRadius: Math.min(4, Theme.cornerRadius) // Reverted to 4
                        
                        topLeftRadius: dayDelegate.dayIndex === 0 ? edgeRadius : innerRadius
                        bottomLeftRadius: dayDelegate.dayIndex === 0 ? edgeRadius : innerRadius
                        topRightRadius: dayDelegate.dayIndex === widgetRoot.daysToShow - 1 ? edgeRadius : innerRadius
                        bottomRightRadius: dayDelegate.dayIndex === widgetRoot.daysToShow - 1 ? edgeRadius : innerRadius

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
                            Behavior on color { ColorAnimation { duration: 150; easing.type: Theme.standardEasing } }
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
                                    let prevShowTime = index > 0 ? parseFloat(shows[index-1].timestamp) : 0;
                                    let now = widgetRoot.currentTime;
                                    if (now >= prevShowTime && now < showTime) {
                                        nowIdx = i;
                                        break;
                                    }
                                }

                                if (nowIdx !== -1 && dayDelegate.isToday) { // Only scroll for today
                                    innerListView.positionViewAtIndex(nowIdx, ListView.Beginning);
                                }
                            }
                        }

                        Connections {
                            target: widgetRoot
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
                                     return widgetRoot.currentTime >= lastShowTime;
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
                                             var fmt = widgetRoot.timeFormat === "24h" ? "HH:mm" : "h:mm AP";
                                             if (widgetRoot.showSeconds) {
                                                 fmt = widgetRoot.timeFormat === "24h" ? "HH:mm:ss" : "h:mm:ss AP";
                                             }
                                             return Qt.formatTime(new Date(widgetRoot.currentTime * 1000), fmt);
                                         }
                                         color: Theme.buttonText
                                         font.bold: true
                                         font.pixelSize: Theme.fontSizeSmall
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
                                         if (!dayDelegate.isToday) return false;
                                         if (!modelData.timestamp) return false;
                                         var shows = innerListView.model;
                                         if (!shows) return false;
                                         var showTime = parseFloat(modelData.timestamp);
                                         var prevShowTime = index > 0 ? parseFloat(shows[index-1].timestamp) : 0;
                                         var now = widgetRoot.currentTime;
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
                                                 var fmt = widgetRoot.timeFormat === "24h" ? "HH:mm" : "h:mm AP";
                                                 if (widgetRoot.showSeconds) {
                                                     fmt = widgetRoot.timeFormat === "24h" ? "HH:mm:ss" : "h:mm:ss AP";
                                                 }
                                                 return Qt.formatTime(new Date(widgetRoot.currentTime * 1000), fmt);
                                             }
                                             color: Theme.buttonText
                                             font.bold: true
                                             font.pixelSize: Theme.fontSizeSmall
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

                                Rectangle {
                                    id: cardRect
                                    width: Math.max(0, parent.width - 16) // Room for scrollbar
                                    height: 190
                                    color: cardMouseArea.containsMouse ? Theme.withAlpha(Theme.surfaceVariant, 0.9) : Theme.withAlpha(Theme.surfaceContainer, 0.8)
                                    radius: 20
                                    border.width: 1
                                    border.color: cardMouseArea.containsMouse ? Theme.primary : Theme.withAlpha(Theme.surfaceVariantText, 0.15)

                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on border.color { ColorAnimation { duration: 150 } }

                                    DankRipple {
                                        id: cardRipple
                                        cornerRadius: parent.radius
                                        rippleColor: Theme.primary
                                    }

                                    MouseArea {
                                        id: cardMouseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: widgetRoot.cardClickAction === "none" ? Qt.ArrowCursor : Qt.PointingHandCursor
                                        onPressed: (mouse) => {
                                            if (widgetRoot.cardClickAction !== "none") cardRipple.trigger(mouse.x, mouse.y);
                                        }
                                        onClicked: {
                                            if (widgetRoot.cardClickAction === "anime_entry" && modelData.animeLink) {
                                                widgetRoot.openUrl(modelData.animeLink)
                                            } else if (widgetRoot.cardClickAction === "watch_page" && modelData.watchLink) {
                                                widgetRoot.openUrl(modelData.watchLink)
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
                                                            if (widgetRoot.timeFormat === "24h") {
                                                                return Qt.formatTime(d, "HH:mm");
                                                            } else {
                                                                return Qt.formatTime(d, "h:mm AP");
                                                            }
                                                        }
                                                        return modelData.time;
                                                    }
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    font.weight: Font.Black
                                                    font.capitalization: Font.AllUppercase
                                                    color: dayDelegate.isToday ? Theme.buttonText : Theme.surfaceVariantText
                                                }
                                            }

                                            StyledText {
                                                id: countdownText
                                                text: modelData.countdown
                                                font.pixelSize: Theme.fontSizeSmall
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

                                                    property color statusColor: {
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
                                                            default: return Theme.surfaceVariantText;
                                                        }
                                                    }

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
                                                                widgetRoot.openUrl(modelData.animeLink)
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

                                        // Main Content Container
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
                                                        color: "white"
                                                        visible: false
                                                        layer.enabled: true
                                                    }

                                                    Item {
                                                        id: coverImgSrc
                                                        anchors.fill: parent
                                                        visible: false
                                                        layer.enabled: true

                                                        Image {
                                                            anchors.fill: parent
                                                            source: modelData.image || ""
                                                            fillMode: Image.PreserveAspectCrop
                                                        }
                                                    }

                                                    MultiEffect {
                                                        anchors.fill: parent
                                                        source: coverImgSrc
                                                        maskEnabled: true
                                                        maskSource: coverMask
                                                    }

                                                    // Cover Image MouseArea
                                                    MouseArea {
                                                        id: coverImageMA
                                                        anchors.fill: parent
                                                        enabled: widgetRoot.coverClickAction !== "none"
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (widgetRoot.coverClickAction === "anime_entry" && modelData.animeLink) {
                                                                widgetRoot.openUrl(modelData.animeLink)
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
                                                            color: "white"
                                                            visible: false
                                                            layer.enabled: true
                                                        }

                                                        Item {
                                                            id: watchIconSrc
                                                            anchors.fill: parent
                                                            anchors.margins: 4
                                                            visible: false
                                                            layer.enabled: true

                                                            Image {
                                                                id: watchIcon
                                                                anchors.fill: parent
                                                                source: modelData.sourceIcon || (modelData.siteDomain ? "https://www.google.com/s2/favicons?domain=" + modelData.siteDomain + "&sz=64" : "")
                                                                visible: source.toString() !== ""
                                                            }
                                                        }

                                                        MultiEffect {
                                                            anchors.fill: watchIconSrc
                                                            source: watchIconSrc
                                                            maskEnabled: true
                                                            maskSource: watchIconMask
                                                            visible: watchIcon.source.toString() !== ""
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
                                                            cursorShape: widgetRoot.watchStreamClickAction === "none" ? Qt.ArrowCursor : Qt.PointingHandCursor
                                                            onPressed: (mouse) => {
                                                                if (widgetRoot.watchStreamClickAction !== "none") watchRipple.trigger(mouse.x, mouse.y);
                                                            }
                                                            onClicked: {
                                                                if (widgetRoot.watchStreamClickAction === "watch_page" && modelData.watchLink) {
                                                                    widgetRoot.openUrl(modelData.watchLink);
                                                                }
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
                                             enabled: widgetRoot.coverClickAction !== "none"
                                             cursorShape: Qt.PointingHandCursor
                                             onPressed: (mouse) => {
                                                 markRipple.trigger(mouse.x, mouse.y);
                                             }
                                             onClicked: {
                                                 if (widgetRoot.coverClickAction === "anime_entry" && modelData.animeLink) {
                                                     widgetRoot.openUrl(modelData.animeLink)
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
    }

    Loader {
        id: settingsLoader
        anchors.fill: parent
        active: showSettingsMenu
        asynchronous: true
        sourceComponent: settingsComponent
    }

    Component {
        id: settingsComponent
        LiveChartSettings {
            widgetRoot: scheduleUI.widgetRoot
            onCloseRequested: showSettingsMenu = false
        }
    }
}
