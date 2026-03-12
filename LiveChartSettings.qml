import QtQuick
import Quickshell

import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "liveChartSchedule"

    StyledText {
        width: parent.width
        text: "LiveChart Schedule"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Displays LiveChart anime schedule data pulled from a local browser session."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SelectionSetting {
        settingKey: "browser"
        label: "Browser Session"
        description: "Which browser's cookies to use for authentication and filtering. (Make sure you are logged into livechart.me)"
        options: [
            { label: "Firefox", value: "firefox" },
            { label: "Chrome", value: "chrome" },
            { label: "Chrome Beta", value: "chrome_beta" }
        ]
        defaultValue: "firefox"
    }

    SelectionSetting {
        settingKey: "timeFormat"
        label: "Time Format"
        description: "Choose between 12-hour and 24-hour time display."
        options: [
            { label: "12 Hours", value: "12h" },
            { label: "24 Hours", value: "24h" }
        ]
        defaultValue: "12h"
    }

    StringSetting {
        settingKey: "updateInterval"
        label: "Update Interval (s)"
        description: "How often to refresh the schedule."
        defaultValue: "3600"
    }
}
