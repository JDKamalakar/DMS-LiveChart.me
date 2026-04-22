import QtQuick
import Quickshell

import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "liveChartSchedule"

    Rectangle {
        width: parent.width
        height: pillGroup.implicitHeight + Theme.spacingM * 2
        color: Theme.surfaceContainer
        radius: Theme.cornerRadius
        border.color: Theme.outline
        border.width: 1
        opacity: 0.8

        function loadValue() {
            for (var i = 0; i < pillGroup.children.length; i++) {
                var row = pillGroup.children[i];
                for (var j = 0; j < row.children.length; j++) {
                    if (row.children[j].loadValue) row.children[j].loadValue();
                }
            }
        }

        Column {
            id: pillGroup
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingM

            Row {
                width: parent.width
                spacing: Theme.spacingM
                DankIcon { name: "view_day"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                SelectionSetting {
                    width: parent.width - 22 - Theme.spacingM
                    settingKey: "dankbarPill"
                    label: "Horizontal Pill Mode"
                    description: "What information to show in the Dankbar pill."
                    options: [
                        { label: "Total Shows", value: "total_count" },
                        { label: "Today's Shows", value: "today_count" },
                        { label: "Next Airing", value: "next_airing" },
                        { label: "Recently Aired", value: "recently_aired" },
                        { label: "Dynamic (Next / Recent)", value: "dynamic" }
                    ]
                    defaultValue: "total_count"
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacingM
                DankIcon { name: "format_list_numbered"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                SelectionSetting {
                    width: parent.width - 22 - Theme.spacingM
                    settingKey: "dankbarLimit"
                    label: "Pill Limit"
                    description: "How many shows to display in Next / Recent modes."
                    options: [
                        { label: "1 Show", value: "1" },
                        { label: "2 Shows", value: "2" },
                        { label: "3 Shows", value: "3" },
                        { label: "4 Shows", value: "4" },
                        { label: "5 Shows", value: "5" }
                    ]
                    defaultValue: "1"
                }
            }
        }
    }

    Rectangle {
        width: parent.width
        height: generalGroup.implicitHeight + Theme.spacingM * 2
        color: Theme.surfaceContainer
        radius: Theme.cornerRadius
        border.color: Theme.outline
        border.width: 1
        opacity: 0.8

        function loadValue() {
            for (var i = 0; i < generalGroup.children.length; i++) {
                var item = generalGroup.children[i];
                if (item.loadValue) item.loadValue();
                else if (item.children) {
                    for (var j = 0; j < item.children.length; j++) {
                        var subItem = item.children[j];
                        if (subItem.loadValue) subItem.loadValue();
                        else if (subItem.children) {
                            for (var k = 0; k < subItem.children.length; k++) {
                                if (subItem.children[k].loadValue) subItem.children[k].loadValue();
                            }
                        }
                    }
                }
            }
        }

        Column {
            id: generalGroup
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingM

            Row {
                width: parent.width
                spacing: Theme.spacingM
                DankIcon { name: "cookie"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                SelectionSetting {
                    width: parent.width - 22 - Theme.spacingM
                    settingKey: "browser"
                    label: "Browser Session"
                    description: "Which browser's cookies to use for authentication and filtering."
                    options: [
                        { label: "Firefox", value: "firefox" },
                        { label: "Zen Browser", value: "zen" },
                        { label: "Chrome", value: "chrome" },
                        { label: "Chrome Beta", value: "chrome_beta" }
                    ]
                    defaultValue: "firefox"
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacingM
                DankIcon { name: "schedule"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                SelectionSetting {
                    width: parent.width - 22 - Theme.spacingM
                    settingKey: "timeFormat"
                    label: "Time Format"
                    description: "Choose between 12-hour and 24-hour time display."
                    options: [
                        { label: "12 Hours", value: "12h" },
                        { label: "24 Hours", value: "24h" }
                    ]
                    defaultValue: "12h"
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacingM
                DankIcon { name: "timer"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                ToggleSetting {
                    width: parent.width - 22 - Theme.spacingM
                    settingKey: "showSeconds"
                    label: "Show Seconds"
                    description: "Display seconds in the current time highlighter."
                    defaultValue: false
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacingM
                DankIcon { name: "refresh"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                Column {
                    width: parent.width - 22 - Theme.spacingM
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "Update Interval"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }

                    StyledText {
                        text: "How often to refresh the anime schedule data."
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacingM

                StringSetting {
                    id: intervalValueSetting
                    width: parent.width * 0.5 - Theme.spacingM / 2
                    settingKey: "updateIntervalValue"
                    label: ""
                    description: ""
                    placeholder: "Value"
                    defaultValue: "1"
                }

                SelectionSetting {
                    id: intervalUnitSetting
                    width: parent.width * 0.5 - Theme.spacingM / 2
                    settingKey: "updateIntervalUnit"
                    label: ""
                    description: ""
                    options: [
                        { label: "MiliSec", value: "ms" },
                        { label: "Sec", value: "s" },
                        { label: "Minutes", value: "m" },
                        { label: "Hour", value: "h" }
                    ]
                    defaultValue: "h"
                }
            }
        }
    }

    Rectangle {
        width: parent.width
        height: displayGroup.implicitHeight + Theme.spacingM * 2
        color: Theme.surfaceContainer
        radius: Theme.cornerRadius
        border.color: Theme.outline
        border.width: 1
        opacity: 0.8

        function loadValue() {
            for (var i = 0; i < displayGroup.children.length; i++) {
                var row = displayGroup.children[i];
                for (var j = 0; j < row.children.length; j++) {
                    if (row.children[j].loadValue) row.children[j].loadValue();
                }
                // Handle the one setting I missed wrapping if it exists
                if (row.loadValue) row.loadValue();
            }
        }

        Column {
            id: displayGroup
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingM

            Row {
                width: parent.width
                spacing: Theme.spacingM
                DankIcon { name: "calendar_view_week"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                SelectionSetting {
                    width: parent.width - 22 - Theme.spacingM
                    settingKey: "daysToShow"
                    label: "Days to Show"
                    description: "Number of days of schedule to display."
                    options: [
                        { label: "1 Day", value: "1" },
                        { label: "2 Days", value: "2" },
                        { label: "3 Days", value: "3" },
                        { label: "5 Days", value: "5" },
                        { label: "7 Days", value: "7" }
                    ]
                    defaultValue: "7"
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacingM
                DankIcon { name: "event"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                SelectionSetting {
                    width: parent.width - 22 - Theme.spacingM
                    settingKey: "startDay"
                    label: "Start Day"
                    description: "Which day the schedule should start from."
                    options: [
                        { label: "Day Before Yesterday", value: "-2" },
                        { label: "Yesterday", value: "-1" },
                        { label: "Today", value: "0" },
                        { label: "Tomorrow", value: "1" }
                    ]
                    defaultValue: "0"
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacingM
                DankIcon { name: "touch_app"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                SelectionSetting {
                    width: parent.width - 22 - Theme.spacingM
                    settingKey: "cardClickAction"
                    label: "Anime Card"
                    description: "Action when clicking the background of an anime card."
                    options: [
                        { label: "Disable", value: "none" },
                        { label: "Watch Page", value: "watch_page" },
                        { label: "Anime Entry", value: "anime_entry" }
                    ]
                    defaultValue: "anime_entry"
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacingM
                DankIcon { name: "image"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                SelectionSetting {
                    width: parent.width - 22 - Theme.spacingM
                    settingKey: "coverTitleClickAction"
                    label: "Cover"
                    description: "Action when clicking the cover image of an anime."
                    options: [
                        { label: "Disable", value: "none" },
                        { label: "Anime Entry", value: "anime_entry" }
                    ]
                    defaultValue: "anime_entry"
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacingM
                DankIcon { name: "link"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                SelectionSetting {
                    width: parent.width - 22 - Theme.spacingM
                    settingKey: "watchStreamClickAction"
                    label: "Watch Stream"
                    description: "Action when clicking the source favicon/link."
                    options: [
                        { label: "Disable", value: "none" },
                        { label: "Watch Page", value: "watch_page" }
                    ]
                    defaultValue: "watch_page"
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacingM
                DankIcon { name: "home"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                SelectionSetting {
                    width: parent.width - 22 - Theme.spacingM
                    settingKey: "livechartIconClickAction"
                    label: "LiveChart.me Icon"
                    description: "Action when clicking the top LiveChart logo."
                    options: [
                        { label: "Schedule", value: "schedule" },
                        { label: "LiveChart.me", value: "livechart" }
                    ]
                    defaultValue: "schedule"
                }
            }
        }
    }
}
