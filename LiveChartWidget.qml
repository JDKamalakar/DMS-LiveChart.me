import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.UPower

import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

// Required for MultiEffect rounding and shadow
import QtQuick.Effects

PluginComponent {
    id: root
    pluginId: "liveChartSchedule"
    pluginService: PluginService

    IpcHandler {
        target: "liveChartSchedule"

        function triggerConflictModal(): string {
            if (root.conflictItems.length === 0) {
                // For testing/debugging, populate dummy conflicts with multiple types if empty
                root.conflictItems = [
                    {
                        animeId: "test_1",
                        title: "Test Anime Progress Desync (Long Title Marquee Scroll)",
                        reason: "Progress dropped to EP 4 (recorded: EP 5)",
                        conflictType: "progress",
                        hasEpDiff: true,
                        hasStatusDiff: false,
                        image: ""
                    },
                    {
                        animeId: "test_2",
                        title: "Test Anime Status Changed",
                        reason: "Status changed to 'completed' (recorded: 'watching')",
                        conflictType: "status",
                        hasEpDiff: false,
                        hasStatusDiff: true,
                        image: ""
                    },
                    {
                        animeId: "test_3",
                        title: "Test Anime Multiple Desyncs (Both Ep & Status)",
                        reason: "Progress dropped to EP 2 (recorded: EP 6) • Status changed to 'planning' (recorded: 'watching')",
                        conflictType: "both",
                        hasEpDiff: true,
                        hasStatusDiff: true,
                        image: ""
                    }
                ];
            }
            root.openConflictModal();
            return "SUCCESS";
        }

        function closeConflictModal(): string {
            root.dismissConflictModal();
            return "SUCCESS";
        }
    }
    
    // Configurable properties via pluginData (from Settings)
    property string timeFormat: pluginData.timeFormat || "12h"
    property bool showSeconds: pluginData.showSeconds !== undefined ? pluginData.showSeconds : false
    property int updateIntervalMs: {
        let val = parseFloat(pluginData.updateIntervalValue || "1");
        let unit = pluginData.updateIntervalUnit || "h";
        let ms = 3600000;
        
        switch (unit) {
            case "m": ms = val * 60000; break;
            case "h": ms = val * 3600000; break;
            default:  ms = val * 3600000; break;
        }
        // Enforce a minimum floor of at least 5 minutes (300,000 ms)
        return Math.max(ms, 300000);
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
    property bool showInfoNotes: pluginData.showInfoNotes !== undefined ? (pluginData.showInfoNotes === true || pluginData.showInfoNotes === "true") : true
    property bool useCustomStatusFilter: pluginData.useCustomStatusFilter !== undefined ? (pluginData.useCustomStatusFilter === true || pluginData.useCustomStatusFilter === "true") : false
    property var customStatusList: {
        if (!pluginData.customStatusList) {
            return ["watching", "rewatching", "planning", "considering"];
        }
        try {
            return JSON.parse(pluginData.customStatusList);
        } catch (e) {
            return ["watching", "rewatching", "planning", "considering"];
        }
    }

    // Calculate theme mode dynamically
    readonly property bool isDarkTheme: (Theme.surface.r * 0.299 + Theme.surface.g * 0.587 + Theme.surface.b * 0.114) < 0.5

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
        let newShowNotes = pluginData.showInfoNotes !== undefined ? (pluginData.showInfoNotes === true || pluginData.showInfoNotes === "true") : true;
        let newUseCustomFilter = pluginData.useCustomStatusFilter !== undefined ? (pluginData.useCustomStatusFilter === true || pluginData.useCustomStatusFilter === "true") : false;
        let newCustomStatusList = ["watching", "rewatching", "planning", "considering"];
        if (pluginData.customStatusList) {
            try {
                newCustomStatusList = JSON.parse(pluginData.customStatusList);
            } catch (e) {}
        }
        let filterChanged = (newUseCustomFilter !== root.useCustomStatusFilter) || (JSON.stringify(newCustomStatusList) !== JSON.stringify(root.customStatusList));
        let customFilterModeChanged = (newUseCustomFilter !== root.useCustomStatusFilter);
        root.useCustomStatusFilter = newUseCustomFilter;
        root.customStatusList = newCustomStatusList;

        if (customFilterModeChanged) {
            // When custom filter toggle changes, we must refetch with/without all statuses
            root.isLoading = true;
            root.triggerFetch("Filter mode changed, refetching schedule...");
        } else if (newShowNotes !== root.showInfoNotes || filterChanged) {
            root.showInfoNotes = newShowNotes;
            root.updateScheduleData();
        }
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
        const limitedData = root.fullScheduleData.slice(0, root.daysToShow).map(day => {
            const filteredShows = (day.shows || []).filter(show => {
                if (show.isInfoNote && !root.showInfoNotes) return false;
                if (!show.isInfoNote && root.useCustomStatusFilter) {
                    let st = String(show.libraryStatus || "none").toLowerCase().replace('-', '_');
                    if (!root.customStatusList || !root.customStatusList.includes(st)) {
                        return false;
                    }
                }
                return true;
            });
            return Object.assign({}, day, { shows: filteredShows });
        });
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
        
        root.activeStatusMenuAnimeId = "";
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
            root.browserName,
            root.useCustomStatusFilter ? "true" : "false"
        ];
        fetchProcess.running = true;
    }
    
    property bool minimumWidth: pluginData.minimumWidth !== undefined ? pluginData.minimumWidth : false
    
    // Day name for dynamic coloring
    // Day name for dynamic coloring - now reactive to "today" property
    property string currentDayName: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][root.today.getDay()]
    
    // Check if system is running on battery or power-saver profile
    readonly property bool isPowerSaving: {
        let onBattery = (typeof BatteryService !== "undefined" && BatteryService && BatteryService.batteryAvailable && !BatteryService.isPluggedIn);
        let powerSaver = false;
        if (typeof PowerProfileWatcher !== "undefined" && PowerProfileWatcher && PowerProfileWatcher.available) {
            powerSaver = (PowerProfileWatcher.currentProfile === 0 || PowerProfileWatcher.currentProfile === PowerProfile.PowerSaver);
        } else if (typeof PowerProfiles !== "undefined" && PowerProfiles) {
            powerSaver = (PowerProfiles.profile === 0 || PowerProfiles.profile === PowerProfile.PowerSaver);
        }
        return Boolean(onBattery || powerSaver);
    }

    // Timer to update "Now" position
    property double currentTime: Date.now() / 1000
    Timer {
        // Tick once a minute (60s) normally, or 1s only when seconds are displayed or popout is actively open
        interval: (root.popoutOpen && root.showSeconds) ? 1000 : 60000
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
    popoutWidth: Math.min(Screen.width ? Screen.width - 64 : 1200, Math.max(400, 300 * root.daysToShow)) // Dynamically resize width per day but prevent clipping
    popoutHeight: 68 + (root.daysToShow <= 2 ? 56 + Theme.spacingM : 0) + 540 + Theme.spacingM + 32

    Timer {
        id: updateTimer
        // Temporarily reduce refresh interval when in error state (e.g., missing internet or keyring lock)
        // to automatically recover without requiring a manual refresh click.
        interval: (root.errorType !== "") ? Math.min(30000, root.updateIntervalMs) : root.updateIntervalMs
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

    function formatScheduleDate(dayName, dateStr) {
        if (!dateStr || dateStr === "") return dayName;
        // Strip current year (e.g. ", 2026") if matches current year
        var currentYear = String(new Date().getFullYear());
        var cleanDate = dateStr.replace(new RegExp(",\\s*" + currentYear + "$"), "");
        return dayName + ", " + cleanDate;
    }

    function getDankbarText(isVertical) {
        if (root.isLoading) return isVertical ? "..." : "Fetching...";
        
        let todayCount = 0;
        for (let i = 0; i < root.scheduleData.length; i++) {
            if (root.scheduleData[i].day === root.currentDayName) {
                let sList = root.scheduleData[i].shows || [];
                todayCount = sList.filter(s => !s.isInfoNote).length;
                break;
            }
        }

        if (isVertical) return todayCount.toString();
        
        if (root.dankbarPill === "total_count") {
            let totalCount = 0;
            for (let i = 0; i < root.scheduleData.length; i++) {
                let sList = root.scheduleData[i].shows || [];
                totalCount += sList.filter(s => !s.isInfoNote).length;
            }
            return `Anime (${totalCount})`;
        }
        
        if (root.dankbarPill === "today_count") {
            return `Today (${todayCount})`;
        }

        let nextShows = [];
        let recentShows = [];

        for (let i = 0; i < root.scheduleData.length; i++) {
            let day = root.scheduleData[i];
            for (let j = 0; j < (day.shows || []).length; j++) {
                let show = day.shows[j];
                if (show.isInfoNote) continue;
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

        function formatShowEp(show) {
            if (show.cardEpisode) return "Ep " + show.cardEpisode;
            if (show.time && String(show.time).toUpperCase().startsWith("EP")) return show.time;
            return "";
        }

        let mode = root.dankbarPill;
        if (mode === "dynamic") mode = (root.dynamicDisplayMode === "next" ? "next_airing" : "recently_aired");

        if (mode === "next_airing") {
            if (nextShows.length === 0) return "None Next";
            
            let displays = [];
            for (let i = 0; i < Math.min(nextShows.length, root.dankbarLimit); i++) {
                let ns = nextShows[i];
                let timeStr = formatTimeDiff(ns.diff);
                let epStr = formatShowEp(ns.show);
                displays.push(`${ns.show.title}${epStr ? " " + epStr : ""} (in ${timeStr})`);
            }
            return displays.join("  •  ");
        }
        
        if (mode === "recently_aired") {
            if (recentShows.length === 0) return "None Recent";
            
            let displays = [];
            for (let i = 0; i < Math.min(recentShows.length, root.dankbarLimit); i++) {
                let rs = recentShows[i];
                let timeStr = formatTimeDiff(rs.diff);
                let epStr = formatShowEp(rs.show);
                displays.push(`${rs.show.title}${epStr ? " " + epStr : ""} (${timeStr} ago)`);
            }
            return displays.join("  •  ");
        }

        return "Anime";
    }

    function getServiceIcon(modelData) {
        if (!modelData) return "";
        let domain = (modelData.siteDomain || "").toLowerCase();
        let name = (modelData.siteName || "").toLowerCase();
        let link = (modelData.watchLink || "").toLowerCase();

        // 1. Official vector brand SVG assets with authentic colors (check brand first!)
        if (domain.includes("crunchyroll") || name.includes("crunchyroll") || link.includes("crunchyroll"))
            return "assets/services/crunchyroll.svg";
        if (domain.includes("netflix") || name.includes("netflix") || link.includes("netflix"))
            return "assets/services/netflix.svg";
        if (domain.includes("youtube") || name.includes("youtube") || link.includes("youtube") || domain.includes("youtu.be"))
            return "assets/services/youtube.svg";
        if (domain.includes("amazon") || domain.includes("primevideo") || name.includes("prime") || link.includes("amazon") || link.includes("primevideo"))
            return "assets/services/primevideo.svg";
        if (domain.includes("iqiyi") || name.includes("iqiyi") || domain.includes("iq.com") || link.includes("iq.com"))
            return "assets/services/iqiyi.svg";
        if (domain.includes("wetv") || name.includes("wetv") || link.includes("wetv.vip"))
            return "assets/services/wetv.svg";
        if (domain.includes("bilibili") || name.includes("bilibili") || link.includes("bilibili"))
            return "assets/services/bilibili.svg";
        if (domain.includes("disney") || name.includes("disney") || link.includes("disneyplus"))
            return "assets/services/disneyplus.svg";
        if (domain.includes("hidive") || name.includes("hidive") || link.includes("hidive"))
            return "assets/services/hidive.svg";
        if (domain.includes("hulu") || name.includes("hulu") || link.includes("hulu"))
            return "assets/services/hulu.svg";
        if (domain.includes("max.com") || name.includes("max") || link.includes("max.com"))
            return "assets/services/max.svg";
        if (domain.includes("shahid") || name.includes("shahid") || link.includes("shahid.mbc.net"))
            return "assets/services/shahid.svg";

        // 2. Direct scraped icon if provided (cached local SVG from LiveChart mask or custom host)
        if (modelData.sourceIcon && modelData.sourceIcon !== "")
            return modelData.sourceIcon;

        // 3. Fallback to Google Favicon service if domain exists
        if (modelData.siteDomain && modelData.siteDomain !== "")
            return "https://www.google.com/s2/favicons?domain=" + modelData.siteDomain + "&sz=64";

        return "";
    }

    function applyOptimisticProgress(animeId, episodesWatched, status) {
        if (!animeId || !root.fullScheduleData || root.fullScheduleData.length === 0) return;
        var aid = String(animeId);
        var targetEp = episodesWatched !== undefined && episodesWatched !== null ? parseInt(episodesWatched, 10) : 0;
        var targetStatus = status ? status.toLowerCase() : "";

        var updatedFull = root.fullScheduleData.map(function(day) {
            var shows = (day.shows || []).map(function(show) {
                if (String(show.animeId || "") === aid) {
                    var newShow = Object.assign({}, show);
                    if (targetEp > 0) {
                        newShow.currentProgress = targetEp;
                        var cardEp = newShow.cardEpisode || 0;
                        if (cardEp > 0) {
                            newShow.isWatched = (targetEp >= cardEp);
                        }
                    }
                    if (targetStatus) {
                        newShow.libraryStatus = targetStatus;
                        if (targetStatus === "completed") {
                            newShow.isWatched = true;
                        }
                    }
                    return newShow;
                }
                return show;
            });
            return Object.assign({}, day, { shows: shows });
        });

        root.fullScheduleData = updatedFull;
        root.updateScheduleData();
    }

    NumberAnimation {
        id: mainScrollAnim
        target: mainListView
        property: "contentX"
        duration: 450
        easing.type: Easing.OutCubic
    }

    Timer {
        id: scrollTimer
        interval: 150
        repeat: false
        property int focusIndex: 0
        onTriggered: {
            if (typeof mainListView !== "undefined" && mainListView) {
                mainListView.currentIndex = focusIndex;
                let dayWidth = (mainListView.width - (mainListView.spacing * Math.max(0, root.daysToShow - 1))) / Math.max(1, root.daysToShow);
                let targetX = focusIndex * (dayWidth + mainListView.spacing);
                let maxX = Math.max(0, mainListView.contentWidth - mainListView.width);
                targetX = Math.max(0, Math.min(maxX, targetX));
                
                mainScrollAnim.stop();
                mainScrollAnim.from = mainListView.contentX;
                mainScrollAnim.to = targetX;
                mainScrollAnim.start();
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
            root.browserName,
            root.useCustomStatusFilter ? "true" : "false"
        ]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                root.isLoading = false;
                const output = text.trim();
                if (!output) {
                    console.warn("LiveChart: Received empty stdout stream");
                    return;
                }
                try {
                    const parsed = JSON.parse(output);
                    if (parsed.success) {
                        root.fullScheduleData = parsed.data;
                        root.errorType = "";
                        root.installCommand = "";
                        root.checkForConflicts(parsed.data);
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

        stderr: StdioCollector {
            onStreamFinished: {
                if (text && text.trim()) {
                    console.warn("LiveChart stderr:", text.trim());
                }
            }
        }
        
        onExited: (exitCode) => {
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

    property var backupRecords: ({})
    property var conflictItems: []
    property string conflictFilter: "all" // "all", "progress", "status"
    function getFilteredConflicts(filterKey) {
        let items = root.conflictItems || [];
        if (!items || items.length === 0) return [];
        let key = filterKey !== undefined ? filterKey : root.conflictFilter;
        if (key === "all") return items;
        if (key === "progress") {
            return items.filter(item => item.hasEpDiff === true || item.conflictType === "progress" || item.conflictType === "both");
        }
        if (key === "status") {
            return items.filter(item => item.hasStatusDiff === true || item.conflictType === "status" || item.conflictType === "both");
        }
        return items;
    }

    readonly property var filteredConflictItems: getFilteredConflicts(root.conflictFilter)
    property bool showConflictModal: false
    property bool reopenPopoutOnModalClose: false
    property string activeStatusMenuAnimeId: ""

    ListModel {
        id: stableConflictModel
    }

    function syncConflictData() {
        let rawList = root.getFilteredConflicts(root.conflictFilter);
        let newIds = rawList.map(item => String(item.animeId));
        let currIds = [];
        for (let i = 0; i < stableConflictModel.count; i++) {
            currIds.push(String(stableConflictModel.get(i).animeId));
        }

        // If order or IDs completely mismatch, clear and append to guarantee no items are dropped
        let orderMatches = (newIds.length === currIds.length) && newIds.every((id, idx) => id === currIds[idx]);
        if (orderMatches) {
            for (let i = 0; i < rawList.length; i++) {
                let item = rawList[i];
                stableConflictModel.setProperty(i, "title", item.title || "");
                stableConflictModel.setProperty(i, "reason", item.reason || "");
                stableConflictModel.setProperty(i, "conflictType", item.conflictType || "progress");
                stableConflictModel.setProperty(i, "hasEpDiff", item.hasEpDiff === true || item.conflictType === "progress" || item.conflictType === "both");
                stableConflictModel.setProperty(i, "hasStatusDiff", item.hasStatusDiff === true || item.conflictType === "status" || item.conflictType === "both");
                stableConflictModel.setProperty(i, "image", item.image || "");
                stableConflictModel.setProperty(i, "expectedEp", item.expectedEp !== undefined ? item.expectedEp : 0);
                stableConflictModel.setProperty(i, "expectedStatus", item.expectedStatus || "");
            }
        } else {
            stableConflictModel.clear();
            for (let i = 0; i < rawList.length; i++) {
                let item = rawList[i];
                stableConflictModel.append({
                    animeId: item.animeId,
                    title: item.title || "",
                    reason: item.reason || "",
                    conflictType: item.conflictType || "progress",
                    hasEpDiff: item.hasEpDiff === true || item.conflictType === "progress" || item.conflictType === "both",
                    hasStatusDiff: item.hasStatusDiff === true || item.conflictType === "status" || item.conflictType === "both",
                    image: item.image || "",
                    expectedEp: item.expectedEp !== undefined ? item.expectedEp : 0,
                    expectedStatus: item.expectedStatus || ""
                });
            }
        }
    }

    onConflictFilterChanged: syncConflictData()
    onConflictItemsChanged: syncConflictData()

    function openConflictModal() {
        if (root.conflictItems.length === 0) return;
        root.syncConflictData();
        root.reopenPopoutOnModalClose = true;
        if (typeof root.closePopout === "function") {
            root.closePopout();
        }
        // Open modal after popout starts closing
        Qt.callLater(() => {
            root.showConflictModal = true;
        });
    }

    function dismissConflictModal() {
        root.showConflictModal = false;
        if (root.reopenPopoutOnModalClose) {
            root.reopenPopoutOnModalClose = false;
            popoutReopenTimer.restart();
        }
    }

    Timer {
        id: popoutReopenTimer
        interval: 160
        repeat: false
        onTriggered: {
            if (typeof root.triggerPopout === "function") {
                root.triggerPopout();
            }
        }
    }

    // Load backup records on start
    Component.onCompleted: {
        root.loadBackupRecords();
    }

    function getBackupFilePath() {
        // Safe storage in ~/.config/dms/livechart_backup.json
        return "/home/JD/.config/dms/livechart_backup.json";
    }

    Process {
        id: backupSaveProc
        running: false
    }

    Process {
        id: backupLoadProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var content = text.trim();
                if (content) {
                    try {
                        root.backupRecords = JSON.parse(content) || {};
                    } catch (e) {
                        root.backupRecords = {};
                    }
                }
            }
        }
    }

    function loadBackupRecords() {
        backupLoadProc.command = ["cat", root.getBackupFilePath()];
        backupLoadProc.running = true;
    }

    function recordUserChange(animeId, title, episodesWatched, status, image) {
        if (!animeId) return;
        var map = Object.assign({}, root.backupRecords);
        var prev = map[String(animeId)] || {};
        map[String(animeId)] = {
            animeId: String(animeId),
            title: title || prev.title || "Anime #" + animeId,
            image: image || prev.image || "",
            episodesWatched: episodesWatched !== undefined && episodesWatched !== null ? parseInt(episodesWatched, 10) : prev.episodesWatched,
            status: status ? status.toLowerCase() : prev.status,
            timestamp: Date.now(),
            ignored: false
        };
        root.backupRecords = map;
        saveBackupRecords();
    }

    function saveBackupRecords() {
        var jsonStr = JSON.stringify(root.backupRecords, null, 2);
        // Save via python/sh to ensure atomic file write
        backupSaveProc.command = [
            "python3", "-c",
            "import sys, os; p = sys.argv[1]; d = sys.argv[2]; open(p, 'w').write(d)",
            root.getBackupFilePath(),
            jsonStr
        ];
        backupSaveProc.running = true;
    }

    function checkForConflicts(scheduleDataList) {
        if (!scheduleDataList || !root.backupRecords) return;
        var found = [];
        var backups = root.backupRecords;

        for (var i = 0; i < scheduleDataList.length; i++) {
            var day = scheduleDataList[i];
            if (!day.shows) continue;
            for (var j = 0; j < day.shows.length; j++) {
                var show = day.shows[j];
                var aid = String(show.animeId || "");
                if (!aid || !backups[aid]) continue;

                var b = backups[aid];
                if (b.ignored) continue; // User ignored once

                var epReason = "";
                var hasEpDiff = false;
                var currentEp = show.currentProgress || 0;
                var expectedEp = (b.episodesWatched !== undefined && b.episodesWatched !== null) ? b.episodesWatched : null;

                // Check episode regression
                if (expectedEp !== null && currentEp < expectedEp) {
                    hasEpDiff = true;
                    epReason = "Progress dropped to EP " + currentEp + " (recorded: EP " + expectedEp + ")";
                }

                // Check status mismatch
                var statusReason = "";
                var hasStatusDiff = false;
                var expectedStatus = b.status || "";
                var currentStatus = show.libraryStatus || "";
                if (expectedStatus && currentStatus) {
                    var sCurrent = String(currentStatus).toLowerCase().replace('-', '_');
                    var sExpected = String(expectedStatus).toLowerCase().replace('-', '_');
                    if (sCurrent !== sExpected) {
                        hasStatusDiff = true;
                        statusReason = "Status changed to '" + currentStatus + "' (recorded: '" + expectedStatus + "')";
                    }
                }

                if (hasEpDiff || hasStatusDiff) {
                    // Check if already in found list
                    var exists = false;
                    for (var k = 0; k < found.length; k++) {
                        if (found[k].animeId === aid) { exists = true; break; }
                    }
                    if (!exists) {
                        var conflictType = (hasEpDiff && hasStatusDiff) ? "both" : (hasEpDiff ? "progress" : "status");
                        var fullReason = "";
                        if (hasEpDiff && hasStatusDiff) {
                            fullReason = epReason + " • " + statusReason;
                        } else if (hasEpDiff) {
                            fullReason = epReason;
                        } else {
                            fullReason = statusReason;
                        }

                        found.push({
                            animeId: aid,
                            title: show.title || b.title,
                            image: show.image || b.image || "",
                            reason: fullReason,
                            conflictType: conflictType,
                            hasEpDiff: hasEpDiff,
                            hasStatusDiff: hasStatusDiff,
                            epReason: epReason,
                            statusReason: statusReason,
                            expectedEp: expectedEp !== null ? expectedEp : 0,
                            expectedStatus: expectedStatus
                        });
                    }
                }
            }
        }
        root.conflictItems = found;
    }

    function ignoreConflict(animeId) {
        var map = Object.assign({}, root.backupRecords);
        if (map[String(animeId)]) {
            map[String(animeId)].ignored = true;
            root.backupRecords = map;
            root.saveBackupRecords();
        }
        // Remove from current conflict list
        var updated = [];
        for (var i = 0; i < root.conflictItems.length; i++) {
            if (root.conflictItems[i].animeId !== String(animeId)) {
                updated.push(root.conflictItems[i]);
            }
        }
        root.conflictItems = updated;
        if (root.conflictItems.length === 0) {
            root.dismissConflictModal();
        }
    }

    function ignoreAllConflicts() {
        var map = Object.assign({}, root.backupRecords);
        for (var i = 0; i < root.conflictItems.length; i++) {
            var aid = root.conflictItems[i].animeId;
            if (map[aid]) {
                map[aid].ignored = true;
            }
        }
        root.backupRecords = map;
        root.saveBackupRecords();
        root.conflictItems = [];
        root.dismissConflictModal();
    }

    Process {
        id: updateProcess
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim();
                if (!out) return;
                try {
                    const res = JSON.parse(out);
                    if (res.success) {
                        console.log("LiveChart: Entry updated successfully", JSON.stringify(res.entry));
                        // Silently refresh in background to synchronize any state changes
                        root.triggerFetch();
                    } else {
                        console.warn("LiveChart update failed:", res.error);
                    }
                } catch (e) {
                    console.error("LiveChart update JSON error:", e, out);
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text && text.trim()) console.warn("LiveChart update stderr:", text.trim());
            }
        }
    }

    function updateAnimeProgress(animeId, episodesWatched, status, animeTitle, totalEpisodes, currentStatus, coverImage) {
        if (!animeId) {
            console.warn("LiveChart: Cannot update progress without animeId");
            return;
        }
        var targetEp = episodesWatched !== undefined && episodesWatched !== null ? episodesWatched : 1;
        var targetStatus = status || "WATCHING";
        var scriptPath = Qt.resolvedUrl("fetch_livechart.py").toString().replace("file://", "");
        
        // Auto-complete if reaches total episodes
        var todayStr = new Date().toISOString().split("T")[0];
        var startedAt = null;
        var finishedAt = null;

        var totalEp = parseInt(totalEpisodes, 10) || 0;
        if (totalEp > 0 && targetEp >= totalEp) {
            targetStatus = "COMPLETED";
            finishedAt = todayStr;
        } else if (targetStatus !== "COMPLETED") {
            // Any progression should set status to WATCHING if not already watching
            var curStat = String(currentStatus || "").toLowerCase();
            if (curStat !== "watching" && curStat !== "rewatching") {
                targetStatus = "WATCHING";
                startedAt = todayStr;
            }
        }

        // Optimistically update UI so numbers / tick update instantly
        root.applyOptimisticProgress(animeId, targetEp, targetStatus);

        // Record backup change with cover image
        root.recordUserChange(animeId, animeTitle, targetEp, targetStatus, coverImage);

        var cmdArgs = [
            "sh", "-c",
            'script="$1"; shift; if [ -x "$script" ]; then exec "$script" "$@"; else exec python3 "$script" "$@"; fi',
            "--",
            scriptPath,
            "--update",
            String(animeId),
            String(targetEp),
            String(targetStatus),
            root.browserName
        ];
        if (startedAt || finishedAt) {
            cmdArgs.push(startedAt ? String(startedAt) : "null");
            cmdArgs.push(finishedAt ? String(finishedAt) : "null");
        }

        updateProcess.command = cmdArgs;
        updateProcess.running = true;
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS
            Item {
                readonly property int iconSz: Math.min(root.iconSize, 20)
                width: iconSz
                height: iconSz
                anchors.verticalCenter: parent.verticalCenter
                
                Image {
                    id: horizLiveChartLogo
                    source: root.isDarkTheme ? "assets/LiveChart_White.svg" : "assets/LiveChart.svg"
                    width: parent.iconSz
                    height: parent.iconSz
                    anchors.centerIn: parent
                    fillMode: Image.PreserveAspectFit
                    sourceSize: Qt.size(64, 64)
                    smooth: true
                    
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
                    NumberAnimation { duration: 150; easing.type: Theme.standardEasing }
                }

                StyledText {
                    id: statusText
                    readonly property bool isLong: contentWidth > textContainer.width
                    property real scrollOffset: 0
                    
                    x: (isLong && !root.isPowerSaving) ? -scrollOffset : 0
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.widgetTextColor
                    text: root.getDankbarText(false)
                    wrapMode: Text.NoWrap
                    elide: root.isPowerSaving ? Text.ElideRight : Text.ElideNone
                    
                    onTextChanged: {
                        scrollOffset = 0;
                        scrollAnimation.restart();
                    }

                    SequentialAnimation {
                        id: scrollAnimation
                        running: statusText.isLong && textContainer.visible && !root.isPowerSaving
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
                            duration: 150
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
                readonly property int iconSz: Math.min(root.iconSize, 20)
                width: iconSz
                height: iconSz
                anchors.horizontalCenter: parent.horizontalCenter
                
                Image {
                    id: vertLiveChartLogo
                    source: root.isDarkTheme ? "assets/LiveChart_White.svg" : "assets/LiveChart.svg"
                    width: parent.iconSz
                    height: parent.iconSz
                    anchors.centerIn: parent
                    fillMode: Image.PreserveAspectFit
                    sourceSize: Qt.size(64, 64)
                    smooth: true
                    
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

            Connections {
                target: popout.parentPopout || null
                function onShouldBeVisibleChanged() {
                    if (popout.parentPopout && !popout.parentPopout.shouldBeVisible) {
                        root.activeStatusMenuAnimeId = "";
                        // Only close conflict modal if not transitioning to modal view
                        if (!root.reopenPopoutOnModalClose) {
                            root.showConflictModal = false;
                        }
                    }
                }
            }

            Component.onDestruction: {
                root.activeStatusMenuAnimeId = "";
                if (!root.reopenPopoutOnModalClose) {
                    root.showConflictModal = false;
                }
            }

            Item {
                id: popoutContainerWrapper
                width: popout.width
                implicitHeight: mainCol.implicitHeight

                Column {
                    id: mainCol
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
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                scale: iconMA.containsMouse ? 1.1 : 1.0
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                            }

                            DankRipple {
                                id: iconRipple
                                cornerRadius: 22
                                rippleColor: Theme.primary
                                anchors.fill: parent
                            }

                            Image {
                                source: "assets/LiveChart_Color"
                                width: 24
                                height: 24
                                sourceSize: Qt.size(24, 24)
                                anchors.centerIn: parent
                                fillMode: Image.PreserveAspectFit
                                scale: iconMA.containsMouse ? 1.1 : 1.0
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
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

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS

                        // Conflict Indicator Button (shown only when changes were reverted / outside update detected)
                        Rectangle {
                            id: conflictBtnContainer
                            visible: root.conflictItems.length > 0
                            width: visible ? 42 : 0
                            height: 40

                            color: conflictArea.containsMouse ? Theme.withAlpha(Theme.error, 0.25) : Theme.withAlpha(Theme.error, 0.15)
                            border.width: 1
                            border.color: conflictArea.containsMouse ? Theme.withAlpha(Theme.error, 0.8) : Theme.withAlpha(Theme.error, 0.5)

                            topLeftRadius: Theme.cornerRadius
                            bottomLeftRadius: Theme.cornerRadius
                            topRightRadius: Math.min(4, Theme.cornerRadius)
                            bottomRightRadius: Math.min(4, Theme.cornerRadius)

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                            Behavior on topLeftRadius { enabled: true; NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                            Behavior on bottomLeftRadius { enabled: true; NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                            Behavior on topRightRadius { enabled: true; NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                            Behavior on bottomRightRadius { enabled: true; NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }

                            DankRipple {
                                id: conflictRipple
                                cornerRadius: Theme.cornerRadius
                                rippleColor: Theme.error
                            }

                            DankIcon {
                                name: "warning"
                                size: 20
                                color: Theme.error
                                anchors.centerIn: parent
                            }

                            Rectangle {
                                width: 16
                                height: 16
                                radius: 8
                                color: Theme.error
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: -4
                                StyledText {
                                    text: String(root.conflictItems.length)
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: "white"
                                    anchors.centerIn: parent
                                }
                            }

                            MouseArea {
                                id: conflictArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onPressed: mouse => conflictRipple.trigger(mouse.x, mouse.y)
                                onClicked: {
                                    if (root.showConflictModal) {
                                        root.dismissConflictModal();
                                    } else {
                                        root.openConflictModal();
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: refreshContainer
                            width: 42
                            height: 40
                            property bool hasConflict: root.conflictItems.length > 0

                            topLeftRadius: root.isLoading ? (height / 2) : (hasConflict ? Math.min(4, Theme.cornerRadius) : Theme.cornerRadius)
                            bottomLeftRadius: root.isLoading ? (height / 2) : (hasConflict ? Math.min(4, Theme.cornerRadius) : Theme.cornerRadius)
                            topRightRadius: root.isLoading ? (height / 2) : Theme.cornerRadius
                            bottomRightRadius: root.isLoading ? (height / 2) : Theme.cornerRadius

                            color: refreshArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.15) : Theme.withAlpha(Theme.secondary, 0.04)
                            border.width: 1
                            border.color: refreshArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.40) : Theme.withAlpha(Theme.secondary, 0.15)

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                            Behavior on topLeftRadius { enabled: true; NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                            Behavior on bottomLeftRadius { enabled: true; NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                            Behavior on topRightRadius { enabled: true; NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                            Behavior on bottomRightRadius { enabled: true; NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }

                            DankRipple {
                                id: refreshRipple
                                cornerRadius: refreshContainer.topLeftRadius
                                rippleColor: Theme.primary
                            }

                            MouseArea {
                                id: refreshArea
                                anchors.fill: parent
                                hoverEnabled: !root.isLoading
                                enabled: !root.isLoading
                                cursorShape: root.isLoading ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onPressed: mouse => refreshRipple.trigger(mouse.x, mouse.y)
                                onClicked: {
                                    if (root.isLoading) return;
                                    root.activeStatusMenuAnimeId = "";
                                    root.isLoading = true;
                                    root.fullScheduleData = [];
                                    root.updateScheduleData();
                                    root.triggerFetch("Fetching schedule...");
                                }
                            }

                            DankIcon {
                                id: refreshIcon
                                name: "refresh"
                                size: 22
                                color: Theme.primary
                                anchors.centerIn: parent
                                visible: !root.isLoading

                                SequentialAnimation {
                                    id: hoverSpinAnim
                                    running: refreshArea.containsMouse && !root.isLoading
                                    onStopped: refreshIcon.rotation = 0
                                    NumberAnimation { target: refreshIcon; property: "rotation"; from: 0; to: 45; duration: 150; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: refreshIcon; property: "rotation"; from: 45; to: -45; duration: 400; easing.type: Easing.InOutQuad }
                                    NumberAnimation { target: refreshIcon; property: "rotation"; from: -45; to: 0; duration: 150; easing.type: Easing.InQuad }
                                }
                            }

                            DLoadingIndicator {
                                anchors.centerIn: parent
                                size: 24
                                color: Theme.primary
                                visible: root.isLoading
                                running: root.isLoading
                            }
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
                    clip: true
                    
                    Repeater {
                        model: root.daysToShow
                        
                        Column {
                            width: Math.max(0, (skeletonLoader.width - (skeletonLoader.spacing * Math.max(0, root.daysToShow - 1))) / root.daysToShow)
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
                                    
                                    // True dimension dummy card with DLoadingIndicator
                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.topMargin: 16
                                        width: Math.max(0, parent.width - 16) // Accurately reserves 16px scrollbar gutter
                                        height: 190
                                        radius: 20
                                        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.4)
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.surfaceVariantText, 0.1)

                                        DLoadingIndicator {
                                            anchors.centerIn: parent
                                            size: 44
                                            color: Theme.primary
                                            running: root.isLoading
                                        }
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

                    // Material 3 Expressive Background Shapes (rotating in place across different positions)
                    Item {
                        anchors.fill: parent
                        z: -1
                        opacity: 0.25

                        DMaterialShape {
                            shape: "cookie4"
                            color: Theme.primary
                            implicitWidth: 160
                            implicitHeight: 160
                            x: 40
                            y: 30

                            RotationAnimation on rotation {
                                from: 0
                                to: 360
                                duration: 24000
                                loops: Animation.Infinite
                                running: errorView.visible
                            }
                        }

                        DMaterialShape {
                            shape: "sunny"
                            color: Theme.secondary
                            implicitWidth: 140
                            implicitHeight: 140
                            x: parent.width - 180
                            y: 40

                            RotationAnimation on rotation {
                                from: 360
                                to: 0
                                duration: 28000
                                loops: Animation.Infinite
                                running: errorView.visible
                            }
                        }

                        DMaterialShape {
                            shape: "clover4"
                            color: Theme.primary
                            implicitWidth: 150
                            implicitHeight: 150
                            x: 60
                            y: parent.height - 180

                            RotationAnimation on rotation {
                                from: 0
                                to: 360
                                duration: 20000
                                loops: Animation.Infinite
                                running: errorView.visible
                            }
                        }

                        DMaterialShape {
                            shape: "cookie7"
                            color: Theme.secondary
                            implicitWidth: 170
                            implicitHeight: 170
                            x: parent.width - 200
                            y: parent.height - 200

                            RotationAnimation on rotation {
                                from: 360
                                to: 0
                                duration: 32000
                                loops: Animation.Infinite
                                running: errorView.visible
                            }
                        }

                        DMaterialShape {
                            shape: "arch"
                            color: Theme.primary
                            implicitWidth: 130
                            implicitHeight: 130
                            x: (parent.width - 130) / 2
                            y: parent.height - 150

                            RotationAnimation on rotation {
                                from: 0
                                to: 360
                                duration: 26000
                                loops: Animation.Infinite
                                running: errorView.visible
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
                                width: Math.max(0, (parent.width - (12 * Math.max(0, root.daysToShow - 1))) / root.daysToShow)
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
                                                font.family: Theme.monoFontFamily || "Monospace"
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
                                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Theme.standardEasing } }

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
                                                        font.pixelSize: Theme.fontSizeSmall
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
                                
                                DButton {
                                    id: retryBtn
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Retry Now"
                                    iconName: "refresh"
                                    buttonHeight: Theme.buttonHeightM || 44
                                    backgroundColor: Theme.primary
                                    textColor: Theme.buttonText
                                    onClicked: {
                                        root.isLoading = true;
                                        root.triggerFetch("Retrying...");
                                    }
                                }
                            }
                        }
                    }
                }

                // Schedule List Weekly Horizontal Grid
                DankListView {
                    id: mainListView
                    visible: !root.isLoading && root.scheduleData.length > 0
                    width: parent.width
                    height: 540 // Increased to accommodate headers
                    orientation: ListView.Horizontal
                    model: root.scheduleData
                    spacing: 12 // Reduced gap
                    clip: true
                    fadeEdges: false

                    property real targetContentX: contentX
                    NumberAnimation {
                        id: smoothHorizontalWheelAnim
                        target: mainListView
                        property: "contentX"
                        duration: 240
                        easing.type: Easing.OutCubic
                    }

                    WheelHandler {
                        id: smoothHorizontalWheelHandler
                        acceptedDevices: PointerDevice.Mouse
                        onWheel: (event) => {
                            // Support horizontal mousewheel or Shift+Wheel for horizontal grid
                            let delta = event.angleDelta.x !== 0 ? event.angleDelta.x : (event.modifiers & Qt.ShiftModifier ? event.angleDelta.y : 0);
                            if (delta === 0) return;

                            let step = (delta > 0 ? -1 : 1) * 160;
                            let current = smoothHorizontalWheelAnim.running ? mainListView.targetContentX : mainListView.contentX;
                            let maxX = Math.max(0, mainListView.contentWidth - mainListView.width);
                            let newX = Math.max(0, Math.min(maxX, current + step));

                            mainListView.targetContentX = newX;
                            smoothHorizontalWheelAnim.stop();
                            smoothHorizontalWheelAnim.from = mainListView.contentX;
                            smoothHorizontalWheelAnim.to = newX;
                            smoothHorizontalWheelAnim.start();

                            event.accepted = true;
                        }
                    }
                    
                    delegate: Item {
                        id: dayDelegate
                        width: Math.max(0, (ListView.view.width - (ListView.view.spacing * Math.max(0, root.daysToShow - 1))) / root.daysToShow)
                        height: ListView.view.height
                        z: (root.activeStatusMenuAnimeId !== "" && modelData.shows && modelData.shows.some(function(s) { return String(s.animeId) === root.activeStatusMenuAnimeId; })) ? 999 : 1
                        
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
                                Behavior on color { ColorAnimation { duration: 150; easing.type: Theme.standardEasing } }
                                
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
                                        text: root.formatScheduleDate(modelData.day, modelData.date)
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
                                color: dayDelegate.isToday ? Theme.primary : Theme.withAlpha(Theme.surfaceVariantText, 0.2)
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
                                 fadeEdges: false
                                 topMargin: 4
                                 bottomMargin: 4

                                readonly property Item outerDelegate: dayDelegate
                                readonly property int timelineX: dayColumn.timelineX

                                property real targetContentY: contentY
                                NumberAnimation {
                                    id: smoothWheelAnim
                                    target: innerListView
                                    property: "contentY"
                                    duration: 220
                                    easing.type: Easing.OutCubic
                                }

                                WheelHandler {
                                    id: smoothWheelHandler
                                    acceptedDevices: PointerDevice.Mouse
                                    onWheel: (event) => {
                                        // Ignore touchpad pixel scrolls (already handled smoothly by native momentum)
                                        if (event.pixelDelta && event.pixelDelta.y !== 0) return;

                                        let deltaY = event.angleDelta.y;
                                        if (deltaY === 0) return;

                                        let step = (deltaY > 0 ? -1 : 1) * 130;
                                        let current = smoothWheelAnim.running ? innerListView.targetContentY : innerListView.contentY;
                                        let maxY = Math.max(0, innerListView.contentHeight - innerListView.height);
                                        let newY = Math.max(0, Math.min(maxY, current + step));

                                        innerListView.targetContentY = newY;
                                        smoothWheelAnim.stop();
                                        smoothWheelAnim.from = innerListView.contentY;
                                        smoothWheelAnim.to = newY;
                                        smoothWheelAnim.start();

                                        event.accepted = true;
                                    }
                                }

                                NumberAnimation {
                                    id: innerScrollAnim
                                    target: innerListView
                                    property: "contentY"
                                    duration: 500
                                    easing.type: Easing.OutCubic
                                }

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
                                            // Calculate target Y position for nowIdx
                                            let targetY = 0;
                                            for (let j = 0; j < nowIdx; j++) {
                                                let item = innerListView.itemAtIndex(j);
                                                if (item) {
                                                    targetY += item.height;
                                                } else {
                                                    // Fallback average card height (190 + gap 15)
                                                    targetY += 205;
                                                }
                                            }
                                            let maxY = Math.max(0, innerListView.contentHeight - innerListView.height);
                                            targetY = Math.max(0, Math.min(maxY, targetY));
                                            
                                            innerScrollAnim.stop();
                                            innerScrollAnim.from = innerListView.contentY;
                                            innerScrollAnim.to = targetY;
                                            innerScrollAnim.start();
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
                                             color: Theme.primary
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
                                                 font.pixelSize: Theme.fontSizeSmall
                                             }
                                         }
                                     }
                                 }

                                 delegate: Item {
                                     id: innerDelegate
                                     readonly property var showItem: modelData
                                     readonly property bool isActiveCard: String(showItem.animeId || "") !== "" && root.activeStatusMenuAnimeId === String(showItem.animeId || "")
                                     width: innerListView.width
                                     height: (nowMarker.visible ? nowMarker.height : 0) + (gapLine.visible ? gapLine.height : 0) + cardRect.height - 1 // -1 matches Column spacing to avoid gaps
                                     z: isActiveCard ? 9999 : ((root.activeStatusMenuAnimeId === "" && cardMouseArea.containsMouse) ? 10 : 1)

                                      Column {
                                          anchors.fill: parent
                                          z: innerDelegate.isActiveCard ? 9999 : ((root.activeStatusMenuAnimeId === "" && cardMouseArea.containsMouse) ? 10 : 1)
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
                                                 color: Theme.primary
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
                                             color: dayDelegate.isToday ? Theme.primary : Theme.withAlpha(Theme.surfaceVariantText, 0.2)
                                             visible: !nowMarker.visible
                                             z: -1
                                         }

                                        Item {
                                            id: cardWrapper
                                            width: Math.max(0, parent.width - 16) // Room for scrollbar
                                            anchors.horizontalCenter: parent.horizontalCenter // Center to prevent clipping on edges
                                            height: 190
                                            z: (String(modelData.animeId || "") === root.activeStatusMenuAnimeId) ? 999 : 1

                                            StyledRect {
                                                id: cardRect
                                                anchors.fill: parent
                                                height: 190
                                                z: innerDelegate.isActiveCard ? 9999 : 1
                                                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                                                radius: 20
                                                
                                                property bool hasStatus: modelData.libraryStatus !== "none" && modelData.libraryStatus !== "" && modelData.libraryStatus !== undefined
                                                
                                                property color statusColor: {
                                                    if (modelData.isInfoNote) return Theme.warning || "#FFC107";
                                                    if (!hasStatus) return Theme.primary;
                                                    switch(modelData.libraryStatus) {
                                                        case "watching": return Theme.success || "#4CAF50";
                                                        case "rewatching": return Theme.success || "#4CAF50";
                                                        case "completed": return Theme.primary;
                                                        case "planning": return Theme.secondary || Theme.accent;
                                                        case "considering": return Theme.warning || "#FFC107";
                                                        case "paused": return Theme.warning || "#FE8E14";
                                                        case "dropped": return Theme.error || "#AC675D";
                                                        case "skipping": return Theme.error || "#F44336";
                                                        case "in-list": return Theme.primary;
                                                        default: return Theme.primary;
                                                    }
                                                }

                                                readonly property bool isCardHovered: (root.activeStatusMenuAnimeId === "" || innerDelegate.isActiveCard) && cardMouseArea.containsMouse

                                                border.width: 2
                                                border.color: isCardHovered 
                                                    ? Theme.withAlpha(statusColor, 0.7)
                                                    : Theme.withAlpha(Theme.surfaceVariantText, 0.15)
                                                Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutQuad } }
                                                
                                                scale: isCardHovered ? 1.02 : 1.0
                                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                                                DankRipple {
                                                    id: cardRipple
                                                    cornerRadius: parent.radius
                                                    rippleColor: Theme.primary
                                                    anchors.fill: parent
                                                }

                                                MouseArea {
                                                    id: cardMouseArea
                                                    anchors.fill: parent
                                                    hoverEnabled: root.activeStatusMenuAnimeId === "" || innerDelegate.isActiveCard
                                                    cursorShape: root.cardClickAction === "none" ? Qt.ArrowCursor : Qt.PointingHandCursor
                                                    // No z-index explicitly, just defined before the layouts 
                                                    // so buttons inside layouts can take precedence.
                                                    onPressed: (mouse) => {
                                                        if (root.cardClickAction !== "none") cardRipple.trigger(mouse.x, mouse.y);
                                                    }
                                                    onClicked: {
                                                        if (modelData.isInfoNote) {
                                                            if (modelData.scheduleLink) root.openUrl(modelData.scheduleLink);
                                                            else if (modelData.animeLink) root.openUrl(modelData.animeLink);
                                                            return;
                                                        }
                                                        if (root.cardClickAction === "anime_entry" && modelData.animeLink) {
                                                            root.openUrl(modelData.animeLink)
                                                        } else if (root.cardClickAction === "watch_page" && modelData.watchLink) {
                                                            root.openUrl(modelData.watchLink)
                                                        }
                                                    }
                                                }

                                            ColumnLayout {
                                                id: cardMainCol
                                                anchors.fill: parent
                                                anchors.margins: 12
                                                spacing: 8
                                                z: (String(modelData.animeId || "") === root.activeStatusMenuAnimeId) ? 500 : 1

                                                // Top Bar: Time, Countdown, and Bookmark
                                                RowLayout {
                                                    id: cardTopBar
                                                    Layout.fillWidth: true
                                                    spacing: 4
                                                    z: (String(modelData.animeId || "") === root.activeStatusMenuAnimeId) ? 500 : 1

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
                                                      z: (String(modelData.animeId || "") === root.activeStatusMenuAnimeId) ? 500 : 1

                                                      // Bookmark Button
                                                      Item {
                                                          id: bookmarkItem
                                                          width: 24
                                                          height: 24
                                                          z: (String(modelData.animeId || "") === root.activeStatusMenuAnimeId) ? 999 : 1
                                                          Layout.alignment: Qt.AlignVCenter

                                                          property color statusColor: cardRect.statusColor === "transparent" ? Theme.surfaceVariantText : cardRect.statusColor

                                                          property string iconName: modelData.libraryStatus === "none" ? "unmarked" : modelData.libraryStatus

                                                          DankIcon {
                                                              id: statusIcon
                                                              name: {
                                                                  if (modelData.isInfoNote) return "info";
                                                                  switch (modelData.libraryStatus) {
                                                                      case "watching": return "visibility";
                                                                      case "rewatching": return "replay";
                                                                      case "completed": return "check_circle";
                                                                      case "planning": return "schedule";
                                                                      case "considering": return "help_outline";
                                                                      case "paused": return "pause_circle";
                                                                      case "dropped": return "cancel";
                                                                      case "skipping": return "fast_forward";
                                                                      case "in-list": return "bookmark";
                                                                      default: return "bookmark_outline";
                                                                  }
                                                              }
                                                              size: 20
                                                              color: bookmarkItem.statusColor
                                                              width: 20
                                                              height: 20
                                                              anchors.centerIn: parent
                                                              anchors.verticalCenterOffset: -1 // Shift up for visual balance in bookmark
                                                              visible: modelData.isInfoNote || modelData.libraryStatus !== "none" || bookmarkMA.containsMouse
                                                              
                                                              
                                                              opacity: bookmarkMA.containsMouse ? 1.0 : 0.8
                                                          }

                                                          // Default bookmark icon for "none" status if hovered (optional, fallback)
                                                          DankIcon {
                                                              visible: !modelData.isInfoNote && modelData.libraryStatus === "none" && !bookmarkMA.containsMouse
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
                                                                  if (modelData.isInfoNote) {
                                                                      if (modelData.animeLink) root.openUrl(modelData.animeLink);
                                                                      return;
                                                                  }
                                                                  var currentAid = String(modelData.animeId || "");
                                                                  if (root.activeStatusMenuAnimeId === currentAid) {
                                                                      root.activeStatusMenuAnimeId = "";
                                                                  } else {
                                                                      root.activeStatusMenuAnimeId = currentAid;
                                                                  }
                                                              }
                                                          }
                                                          // Status Dropdown / Popover Menu
                                                          Item {
                                                              id: statusPopup
                                                              readonly property bool isOpen: String(modelData.animeId || "") !== "" && root.activeStatusMenuAnimeId === String(modelData.animeId || "")
                                                              visible: opacity > 0
                                                              opacity: isOpen ? 1.0 : 0.0
                                                              scale: isOpen ? 1.0 : 0.88
                                                              z: 1000
                                                              width: 176
                                                              height: statusCol.implicitHeight + 14
                                                              anchors.top: parent.bottom
                                                              anchors.right: parent.right
                                                              anchors.topMargin: 6

                                                              Behavior on opacity {
                                                                  NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                                                              }
                                                              Behavior on scale {
                                                                  NumberAnimation { duration: 240; easing.type: Easing.OutBack }
                                                              }

                                                              // Shield MouseArea covering statusPopup area to block hover & clicks from reaching cards below
                                                              MouseArea {
                                                                  anchors.fill: parent
                                                                  hoverEnabled: true
                                                                  acceptedButtons: Qt.AllButtons
                                                                  onWheel: (wheel) => { wheel.accepted = true; }
                                                                  onPressed: (mouse) => { mouse.accepted = true; }
                                                                  onReleased: (mouse) => { mouse.accepted = true; }
                                                                  onClicked: (mouse) => { mouse.accepted = true; }
                                                              }

                                                              // Opaque frosted background with primary accent outline
                                                              Rectangle {
                                                                  anchors.fill: parent
                                                                  radius: 14
                                                                  color: Theme.surfaceContainerHighest || "#282828"
                                                                  border.width: 1
                                                                  border.color: Theme.withAlpha(Theme.primary, 0.45)
                                                              }

                                                              Column {
                                                                  id: statusCol
                                                                  anchors.fill: parent
                                                                  anchors.margins: 7
                                                                  spacing: 4

                                                                  // Header: Title with Marquee / ScrollingText
                                                                  Rectangle {
                                                                      width: parent.width
                                                                      height: 24
                                                                      radius: 6
                                                                      color: Theme.withAlpha(Theme.primary, 0.12)
                                                                      border.width: 1
                                                                      border.color: Theme.withAlpha(Theme.primary, 0.25)
                                                                      clip: true

                                                                      Row {
                                                                          anchors.fill: parent
                                                                          anchors.leftMargin: 6
                                                                          anchors.rightMargin: 6
                                                                          spacing: 5

                                                                          DankIcon {
                                                                              name: "edit_note"
                                                                              size: 13
                                                                              color: Theme.primary
                                                                              anchors.verticalCenter: parent.verticalCenter
                                                                          }

                                                                          ScrollingText {
                                                                              width: parent.width - 20
                                                                              height: parent.height
                                                                              text: modelData.title || "Anime Status"
                                                                              font.pixelSize: 10
                                                                              font.bold: true
                                                                              color: Theme.primary
                                                                          }
                                                                      }
                                                                  }

                                                                  // Options List (Grouped with First, Mid, Last visual borders & fills)
                                                                  Column {
                                                                      width: parent.width
                                                                      spacing: 1

                                                                      Repeater {
                                                                          id: statusRepeater
                                                                          model: [
                                                                              { label: "Watching", status: "watching", icon: "visibility", color: Theme.success || "#4CAF50" },
                                                                              { label: "Planning", status: "planning", icon: "schedule", color: Theme.secondary || "#80CBC4" },
                                                                              { label: "Completed", status: "completed", icon: "check_circle", color: Theme.primary },
                                                                              { label: "Paused", status: "paused", icon: "pause_circle", color: Theme.warning || "#FE8E14" },
                                                                              { label: "Dropped", status: "dropped", icon: "cancel", color: Theme.error || "#AC675D" },
                                                                              { label: "Unmark", status: "none", icon: "cancel", color: Theme.surfaceVariantText }
                                                                          ]

                                                                          Rectangle {
                                                                              id: optItem
                                                                              readonly property bool isFirst: index === 0
                                                                              readonly property bool isLast: index === statusRepeater.count - 1

                                                                              width: parent.width
                                                                              height: 27

                                                                              // Segmented Radii clearly visible even at rest
                                                                              topLeftRadius: isFirst ? 8 : 2
                                                                              topRightRadius: isFirst ? 8 : 2
                                                                              bottomLeftRadius: isLast ? 8 : 2
                                                                              bottomRightRadius: isLast ? 8 : 2

                                                                              border.width: 1
                                                                              border.color: sOptMA.containsMouse 
                                                                                  ? Theme.withAlpha(modelData.color, 0.6) 
                                                                                  : Theme.withAlpha(Theme.surfaceVariantText, 0.12)

                                                                              // Rest state has subtle background; hover state lights up with distinct status color
                                                                              color: sOptMA.containsMouse 
                                                                                  ? Theme.withAlpha(modelData.color, 0.25) 
                                                                                  : Theme.withAlpha(Theme.surfaceContainerHigh || "#222222", 0.7)

                                                                              Behavior on color {
                                                                                  ColorAnimation { duration: 150 }
                                                                              }
                                                                              Behavior on border.color {
                                                                                  ColorAnimation { duration: 150 }
                                                                              }

                                                                              Row {
                                                                                  anchors.fill: parent
                                                                                  anchors.leftMargin: 8
                                                                                  anchors.rightMargin: 8
                                                                                  spacing: 8
                                                                                  DankIcon {
                                                                                      name: modelData.icon
                                                                                      size: 14
                                                                                      color: modelData.color
                                                                                      anchors.verticalCenter: parent.verticalCenter
                                                                                  }
                                                                                  StyledText {
                                                                                      text: modelData.label
                                                                                      font.pixelSize: 11
                                                                                      font.weight: sOptMA.containsMouse ? Font.DemiBold : Font.Normal
                                                                                      color: sOptMA.containsMouse ? Theme.surfaceText : Theme.withAlpha(Theme.surfaceText, 0.85)
                                                                                      anchors.verticalCenter: parent.verticalCenter
                                                                                  }
                                                                              }

                                                                              MouseArea {
                                                                                  id: sOptMA
                                                                                  anchors.fill: parent
                                                                                  hoverEnabled: true
                                                                                  cursorShape: Qt.PointingHandCursor
                                                                                  onClicked: {
                                                                                      root.activeStatusMenuAnimeId = "";
                                                                                      var targetStatus = modelData.status.toUpperCase();
                                                                                      var curEp = innerDelegate.showItem.currentProgress || 0;
                                                                                      var aid = innerDelegate.showItem.animeId || "";
                                                                                      var aTitle = innerDelegate.showItem.title || "";
                                                                                      if (aid) {
                                                                                          root.updateAnimeProgress(aid, curEp, targetStatus, aTitle, innerDelegate.showItem.totalEpisodes, innerDelegate.showItem.libraryStatus, innerDelegate.showItem.image || "");
                                                                                      }
                                                                                  }
                                                                              }
                                                                          }
                                                                      }
                                                                  }
                                                              }
                                                          }

                                                      }
                                                  }
                                            }

                                            // Edge-to-Edge Separator
                                            Item {
                                                Layout.fillWidth: true
                                                Layout.leftMargin: -12
                                                Layout.rightMargin: -12
                                                Layout.preferredHeight: 1

                                                Rectangle {
                                                    id: sepLine
                                                    anchors.fill: parent
                                                    color: Theme.withAlpha(Theme.surfaceVariantText, 0.15)
                                                }
                                            }

                                            // Main Content
                                            // Main Content Container (Prevents layout interference between MouseArea and Layout children)
                                            Item {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                z: 1

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
                                                                visible: source.toString() !== ""
                                                            }
                                                            Rectangle {
                                                                anchors.fill: parent
                                                                color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.5)
                                                                visible: !modelData.image || modelData.image === ""
                                                                DankIcon {
                                                                    anchors.centerIn: parent
                                                                    name: modelData.isInfoNote ? "event_busy" : "image"
                                                                    size: 28
                                                                    color: modelData.isInfoNote ? (Theme.warning || "#FFC107") : Theme.surfaceVariantText
                                                                    opacity: 0.7
                                                                }
                                                            }
                                                        }

                                                        MultiEffect {
                                                            anchors.fill: parent
                                                            source: coverImgSrc
                                                            maskEnabled: true
                                                            maskSource: coverMask
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

                                                        // Watch Button (3D tactile elevated button with authentic colorful brand icon)
                                                        Rectangle {
                                                            id: watchBtn
                                                            anchors.horizontalCenter: parent.horizontalCenter
                                                            anchors.bottom: parent.bottom
                                                            anchors.bottomMargin: -10
                                                            width: 28
                                                            height: 28
                                                            radius: 14
                                                            color: root.isDarkTheme ? "#222225" : "#FFFFFF"
                                                            border.width: 1.5
                                                            border.color: root.isDarkTheme ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.12)
                                                            visible: modelData.watchLink !== ""
                                                            z: 10 // Ensure it's above cover click handler

                                                            // 3D tactile elevation: soft drop shadow
                                                            layer.enabled: true
                                                            layer.effect: MultiEffect {
                                                                shadowEnabled: true
                                                                shadowColor: Qt.rgba(0, 0, 0, 0.4)
                                                                shadowBlur: 0.35
                                                                shadowHorizontalOffset: 0
                                                                shadowVerticalOffset: 1.5
                                                            }

                                                            DankRipple {
                                                                id: watchRipple
                                                                cornerRadius: parent.radius
                                                                rippleColor: Theme.primary
                                                            }

                                                            Item {
                                                                id: watchIconSrc
                                                                anchors.centerIn: parent
                                                                width: 18
                                                                height: 18

                                                                Image {
                                                                    id: watchIcon
                                                                    anchors.fill: parent
                                                                    source: root.getServiceIcon(modelData)
                                                                    visible: source.toString() !== ""
                                                                    fillMode: Image.PreserveAspectFit
                                                                    smooth: true
                                                                    mipmap: true
                                                                }
                                                            }

                                                            DankIcon {
                                                                anchors.centerIn: parent
                                                                name: modelData.isInfoNote ? "info" : "link"
                                                                size: 14
                                                                color: modelData.isInfoNote ? (Theme.warning || "#FFC107") : Theme.primary
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

                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: modelData.noteText || ""
                                                            font.pixelSize: Theme.fontSizeSmall
                                                            color: Theme.surfaceVariantText
                                                            wrapMode: Text.Wrap
                                                            maximumLineCount: 3
                                                            elide: Text.ElideRight
                                                            visible: Boolean(modelData.isInfoNote && modelData.noteText)
                                                        }
                                                    } // ColumnLayout (Info)
                                                } // RowLayout (Main Content)


                                            } // Item (Main Content Container)
                                        } // ColumnLayout (Card)

                                        // Progress / Watched Indicator & Action Buttons
                                        Item {
                                            id: markWatchedBtn
                                            readonly property int cardEp: modelData.cardEpisode || 0
                                            readonly property int currEp: modelData.currentProgress || 0
                                            readonly property int airTimestamp: parseInt(modelData.timestamp || "0", 10)
                                            readonly property bool isAired: airTimestamp === 0 || airTimestamp <= root.currentTime
                                            readonly property int targetProgressEp: isAired ? cardEp : Math.max(currEp, cardEp - 1)
                                            readonly property int epDifference: Math.max(0, targetProgressEp - currEp)
                                            readonly property bool hasPendingEpisodes: !modelData.isWatched && !modelData.isInfoNote && (targetProgressEp > currEp)
                                            readonly property bool hasMultipleUnwatched: hasPendingEpisodes && (epDifference > 1)

                                            property bool isExpanded: countMA.containsMouse || tickMA.containsMouse || mainProgressHover.containsMouse

                                            // When hovered, expand horizontally into 2 segmented buttons (width 62);
                                            // When not hovered, compact into a single button (width 28) with number tucked above
                                            width: hasMultipleUnwatched ? (isExpanded ? 62 : 28) : 28
                                            height: 28
                                            visible: hasPendingEpisodes
                                            z: (String(modelData.animeId || "") === root.activeStatusMenuAnimeId) ? 1 : 30

                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.rightMargin: 12
                                            anchors.bottomMargin: 12

                                            Behavior on width {
                                                NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                                            }

                                            MouseArea {
                                                id: mainProgressHover
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                z: 1
                                            }

                                            // First Button: Number badge (Progress 1 episode)
                                            // Matching header navigation button style (Theme.cornerRadius / 4px inner, subtle tint & border)
                                            Rectangle {
                                                id: countBox
                                                visible: markWatchedBtn.hasMultipleUnwatched
                                                z: 20
                                                width: markWatchedBtn.isExpanded ? 30 : 18
                                                height: markWatchedBtn.isExpanded ? 28 : 18

                                                // Segmented corner radii identical to header buttons
                                                topLeftRadius: markWatchedBtn.isExpanded ? Theme.cornerRadius : 9
                                                bottomLeftRadius: markWatchedBtn.isExpanded ? Theme.cornerRadius : 9
                                                topRightRadius: markWatchedBtn.isExpanded ? 3 : 9
                                                bottomRightRadius: markWatchedBtn.isExpanded ? 3 : 9

                                                color: countMA.containsMouse 
                                                    ? Theme.withAlpha(Theme.error, 0.35) 
                                                    : (markWatchedBtn.isExpanded ? Theme.withAlpha(Theme.error, 0.18) : Theme.error)
                                                border.width: 1
                                                border.color: markWatchedBtn.isExpanded 
                                                    ? (countMA.containsMouse ? Theme.withAlpha(Theme.error, 0.8) : Theme.withAlpha(Theme.error, 0.45)) 
                                                    : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 1)

                                                // Position transitions:
                                                // Unhovered: tucked above the tick mark (x=12, y=-10)
                                                // Hovered: left button (x=0, y=0)
                                                x: markWatchedBtn.isExpanded ? 0 : 12
                                                y: markWatchedBtn.isExpanded ? 0 : -9

                                                Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                                                Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                                                Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                                                Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                                                Behavior on topLeftRadius { NumberAnimation { duration: 300 } }
                                                Behavior on topRightRadius { NumberAnimation { duration: 300 } }
                                                Behavior on bottomLeftRadius { NumberAnimation { duration: 300 } }
                                                Behavior on bottomRightRadius { NumberAnimation { duration: 300 } }
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                                StyledText {
                                                    id: countText
                                                    anchors.centerIn: parent
                                                    text: String(markWatchedBtn.epDifference)
                                                    font.pixelSize: markWatchedBtn.isExpanded ? 11 : 10
                                                    font.bold: true
                                                    color: markWatchedBtn.isExpanded ? (countMA.containsMouse ? Theme.error : Theme.surfaceText) : "white"
                                                }

                                                MouseArea {
                                                    id: countMA
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        var nextEp = markWatchedBtn.currEp + 1;
                                                        if (modelData.animeId) {
                                                            root.updateAnimeProgress(modelData.animeId, nextEp, "WATCHING", modelData.title, modelData.totalEpisodes, modelData.libraryStatus, modelData.image || "");
                                                        }
                                                    }
                                                }
                                            }

                                            // Last Button: Tick / Checkmark Button
                                            // Matching header navigation button style (Theme.cornerRadius / 4px inner, subtle tint & border)
                                            Rectangle {
                                                id: tickBox
                                                z: 10
                                                width: markWatchedBtn.hasMultipleUnwatched && markWatchedBtn.isExpanded ? 31 : 28
                                                height: 28
                                                x: markWatchedBtn.hasMultipleUnwatched && markWatchedBtn.isExpanded ? 31 : 0
                                                y: 0

                                                topLeftRadius: (markWatchedBtn.hasMultipleUnwatched && markWatchedBtn.isExpanded) ? 3 : Theme.cornerRadius
                                                bottomLeftRadius: (markWatchedBtn.hasMultipleUnwatched && markWatchedBtn.isExpanded) ? 3 : Theme.cornerRadius
                                                topRightRadius: Theme.cornerRadius
                                                bottomRightRadius: Theme.cornerRadius

                                                color: tickMA.containsMouse 
                                                    ? Theme.withAlpha(Theme.primary, 0.25) 
                                                    : (markWatchedBtn.hasMultipleUnwatched && markWatchedBtn.isExpanded ? Theme.withAlpha(Theme.primary, 0.12) : "white")
                                                border.width: 1
                                                border.color: tickMA.containsMouse 
                                                    ? Theme.withAlpha(Theme.primary, 0.8) 
                                                    : (markWatchedBtn.hasMultipleUnwatched && markWatchedBtn.isExpanded ? Theme.withAlpha(Theme.primary, 0.35) : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 1))

                                                Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                                                Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                                                Behavior on topLeftRadius { NumberAnimation { duration: 300 } }
                                                Behavior on bottomLeftRadius { NumberAnimation { duration: 300 } }
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                                DankIcon {
                                                    anchors.centerIn: parent
                                                    name: markWatchedBtn.hasMultipleUnwatched ? "done_all" : "check"
                                                    size: markWatchedBtn.hasMultipleUnwatched ? 16 : 14
                                                    color: (markWatchedBtn.hasMultipleUnwatched && markWatchedBtn.isExpanded) 
                                                        ? Theme.primary 
                                                        : (root.isDarkTheme ? Theme.primary : "black")
                                                }

                                                DankRipple {
                                                    id: markRipple
                                                    cornerRadius: parent.radius
                                                    rippleColor: Theme.primary
                                                }

                                                MouseArea {
                                                    id: tickMA
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onPressed: (mouse) => {
                                                        markRipple.trigger(mouse.x, mouse.y);
                                                    }
                                                    onClicked: {
                                                        markWatchedBtn.visible = false;
                                                        var targetEp = markWatchedBtn.targetProgressEp > 0 ? markWatchedBtn.targetProgressEp : (modelData.progressTarget || ((modelData.currentProgress || 0) + 1));
                                                        if (modelData.animeId) {
                                                            root.updateAnimeProgress(modelData.animeId, targetEp, "WATCHING", modelData.title, modelData.totalEpisodes, modelData.libraryStatus, modelData.image || "");
                                                        } else if (modelData.animeLink) {
                                                            root.openUrl(modelData.animeLink);
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    } // StyledRect (cardRect)
                                } // Item (cardWrapper)
                                } // Column (Show Column)
                            } // Item (Inner delegate)
                        } // DankListView (Inner)
                    } // Column (Weekly column)
                } // Item (Weekly delegate)
            } // DankListView (Weekly)
        } // Column (Popout Main Column)

        } // Item (popoutContainerWrapper)
    } // PopoutComponent
} // Component (popoutContent)

    // =========================================================================
    // CONFLICT / ERROR POPUP LAYER (Separate PanelWindow Layer Shell with Blur)
    // Inherits native compositor blur (WlrLayershell & BackgroundEffect.blurRegion)
    // identical to DMS-ScreenCapture_Toolbar, with spacious layout, 1.5x covers (60x82.5),
    // distinct error category indicators, and styled action button matching error indicator.
    // =========================================================================

    // Consolidated Interactive Dialog Window with focused blur region and backdrop scrim
    PanelWindow {
        id: conflictModalWindow
        visible: root.showConflictModal && root.conflictItems.length > 0
        color: "transparent"

        WlrLayershell.namespace: "dms:plugins:liveChartSchedule:modal"
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible) {
                conflictKeyHandler.forceActiveFocus();
            }
        }

        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }

        BackgroundEffect.blurRegion: visible ? conflictBlurRegion : null

        Region {
            id: conflictBlurRegion
            x: conflictDialogCard.x
            y: conflictDialogCard.y
            width: conflictDialogCard.width
            height: conflictDialogCard.height
            radius: conflictDialogCard.radius
        }

        // 1. Full-screen backdrop dim scrim directly in the same window (underneath dialog card)
        Rectangle {
            id: conflictDimScrim
            anchors.fill: parent
            z: -1
            color: "black"
            opacity: conflictModalWindow.visible ? 0.35 : 0
            Behavior on opacity {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.dismissConflictModal();
                }
            }
        }

        Item {
            id: conflictKeyHandler
            anchors.fill: parent
            focus: conflictModalWindow.visible

            Keys.onEscapePressed: {
                root.dismissConflictModal();
            }

            // Centered Modal Dialog Card
            Rectangle {
                id: conflictDialogCard
                anchors.centerIn: parent
                width: Math.min(620, parent.width - 32)
                implicitHeight: conflictCol.implicitHeight + 48
                radius: 24
                color: Theme.withAlpha(Theme.surfaceContainerHigh || Theme.surfaceContainer || "#1E1E1E", Theme.popupTransparency || 0.88)
                border.width: 1
                border.color: Theme.withAlpha(Theme.error, 0.40)

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0, 0, 0, 0.55)
                    shadowBlur: 0.6
                    shadowVerticalOffset: 6
                }

                // Consume background clicks on the card so they don't fall through to the dim scrim
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onPressed: mouse => mouse.accepted = true
                }

                ColumnLayout {
                    id: conflictCol
                    anchors.fill: parent
                    anchors.margins: 26
                    spacing: 20

                    // Header Warning Icon
                    DankIcon {
                        name: "warning"
                        size: 46
                        color: Theme.error
                        Layout.alignment: Qt.AlignHCenter
                    }

                    StyledText {
                        text: "Sync Discrepancy Detected"
                        font.pixelSize: Theme.fontSizeLarge + 1
                        font.bold: true
                        color: Theme.surfaceText
                        Layout.alignment: Qt.AlignHCenter
                    }

                    StyledText {
                        text: "The following entries differ from your locally recorded updates (progress reverted or changed outside):"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }

                    // Filter Chips (Segmented First, Mid, Last Button Row with Morphing Radii matching DMS-AMD_GPU_Monitor_Revive)
                    Row {
                        id: conflictFilterRow
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Theme.groupedListGap || 2

                        readonly property var filterDefs: [
                            { key: "all", label: "All", icon: "select_all", count: root.conflictItems.length },
                            { key: "progress", label: "Episode Desync", icon: "sync_problem", count: root.conflictItems.filter(i => i.hasEpDiff === true || i.conflictType === "progress" || i.conflictType === "both").length },
                            { key: "status", label: "Status Changed", icon: "bookmark_border", count: root.conflictItems.filter(i => i.hasStatusDiff === true || i.conflictType === "status" || i.conflictType === "both").length }
                        ]

                        Repeater {
                            model: conflictFilterRow.filterDefs

                            Item {
                                id: filterChipItem
                                width: filterChipRow.implicitWidth + 24
                                height: Theme.buttonHeightS || 36

                                readonly property bool isSelected: root.conflictFilter === modelData.key
                                readonly property bool hovered: filterChipMA.containsMouse
                                readonly property bool isFirst: index === 0
                                readonly property bool isLast: index === (conflictFilterRow.filterDefs.length - 1)

                                readonly property real outerRad: Theme.groupedListOuterRadius || Theme.cornerRadiusL || 12
                                readonly property real innerRad: Theme.groupedListInnerRadius || Theme.cornerRadiusXS || 4
                                readonly property real activeRad: Theme.cornerRadiusFull || (height / 2)

                                Rectangle {
                                    id: filterChipBg
                                    anchors.fill: parent
                                    radius: filterChipItem.innerRad
                                    topLeftRadius: filterChipItem.isSelected ? filterChipItem.activeRad : (filterChipItem.isFirst ? filterChipItem.outerRad : filterChipItem.innerRad)
                                    bottomLeftRadius: filterChipItem.isSelected ? filterChipItem.activeRad : (filterChipItem.isFirst ? filterChipItem.outerRad : filterChipItem.innerRad)
                                    topRightRadius: filterChipItem.isSelected ? filterChipItem.activeRad : (filterChipItem.isLast ? filterChipItem.outerRad : filterChipItem.innerRad)
                                    bottomRightRadius: filterChipItem.isSelected ? filterChipItem.activeRad : (filterChipItem.isLast ? filterChipItem.outerRad : filterChipItem.innerRad)

                                    Behavior on topLeftRadius { NumberAnimation { duration: 150 } }
                                    Behavior on bottomLeftRadius { NumberAnimation { duration: 150 } }
                                    Behavior on topRightRadius { NumberAnimation { duration: 150 } }
                                    Behavior on bottomRightRadius { NumberAnimation { duration: 150 } }

                                    color: filterChipItem.isSelected
                                        ? (Theme.secondaryContainer || Theme.buttonBg || Theme.withAlpha(Theme.primary, 0.22))
                                        : (filterChipItem.hovered
                                            ? Theme.withAlpha(Theme.surfaceVariant, 0.15)
                                            : (Theme.foregroundColor ? Theme.foregroundColor(Theme.chipSurface) : Theme.withAlpha(Theme.surfaceVariant, 0.20)))

                                    border.width: 1
                                    border.color: filterChipItem.isSelected
                                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.50)
                                        : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on border.color { ColorAnimation { duration: 150 } }

                                    DankRipple {
                                        id: filterChipRip
                                        anchors.fill: parent
                                        cornerRadius: filterChipBg.topLeftRadius
                                        rippleColor: Theme.primary
                                    }

                                    Row {
                                        id: filterChipRow
                                        anchors.centerIn: parent
                                        spacing: Theme.spacingXS || 6

                                        DankIcon {
                                            name: modelData.icon
                                            size: Theme.iconSizeSmall || 16
                                            color: filterChipItem.isSelected
                                                ? (Theme.onSecondaryContainer || Theme.buttonText || Theme.primary)
                                                : (filterChipItem.hovered ? Theme.surfaceText : (Theme.onSurfaceVariant || Theme.surfaceVariantText))
                                            anchors.verticalCenter: parent.verticalCenter
                                            Behavior on color { ColorAnimation { duration: Theme.shortDuration || 150 } }
                                        }

                                        StyledText {
                                            text: modelData.label + (modelData.count > 0 ? " (" + modelData.count + ")" : "")
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: filterChipItem.isSelected ? Font.Bold : Font.Medium
                                            color: filterChipItem.isSelected
                                                ? (Theme.onSecondaryContainer || Theme.buttonText || Theme.primary)
                                                : (filterChipItem.hovered ? Theme.surfaceText : (Theme.onSurfaceVariant || Theme.surfaceVariantText))
                                            anchors.verticalCenter: parent.verticalCenter
                                            Behavior on color { ColorAnimation { duration: Theme.shortDuration || 150 } }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: filterChipMA
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: mouse => filterChipRip.trigger(mouse.x, mouse.y)
                                    onClicked: {
                                        root.conflictFilter = modelData.key;
                                    }
                                }
                            }
                        }
                    }

                    // Parent Container enclosing the Conflict Items List (matching DMS-AMD_GPU_Monitor_Revive Process Section)
                    Rectangle {
                        id: conflictListContainer
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        Layout.bottomMargin: 6
                        
                        // Dimensions
                        readonly property real itemHeight: 94
                        readonly property real itemGap: Theme.groupedListGap || 2
                        readonly property real listMargins: (Theme.spacingS || 8) * 2

                        // Base height is anchored to total conflict count (all entries), up to 5 items max before scrolling
                        readonly property int baseItemCount: Math.min(5, Math.max(1, root.conflictItems.length))
                        readonly property real targetListHeight: (baseItemCount * itemHeight) + (Math.max(0, baseItemCount - 1) * itemGap) + listMargins

                        // Maximum allowed container height based on available screen space (capping modal safely on smaller displays)
                        readonly property real maxScreenListHeight: Math.max(220, (conflictModalWindow.height || 800) * 0.62)

                        // Constant height across filter tabs; only scrolls when entries exceed 5 items or screen budget
                        implicitHeight: Math.min(maxScreenListHeight, targetListHeight)

                        radius: Theme.cornerRadiusL || 16
                        clip: true
                        color: Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency || 0.75)
                        border.width: Theme.layerOutlineWidth || 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)

                        Behavior on implicitHeight {
                            NumberAnimation { duration: Theme.shortDuration || 150; easing.type: Theme.standardEasing || Easing.OutCubic }
                        }

                        // Empty State if current filter has no items
                        StyledText {
                            anchors.centerIn: parent
                            visible: stableConflictModel.count === 0
                            text: "No discrepancies matching this filter"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        // Gliding Conflict Items List View with DMS shortDuration animations
                        DankListView {
                            id: conflictListView
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            clip: true
                            fadeEdges: false
                            model: stableConflictModel
                            spacing: Theme.groupedListGap || 2
                            boundsBehavior: Flickable.StopAtBounds

                            add: Transition {
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.shortDuration || 150; easing.type: Theme.standardEasing || Easing.OutQuad }
                                NumberAnimation { property: "y"; from: (conflictListView.y + 10); duration: Theme.shortDuration || 150; easing.type: Theme.standardEasing || Easing.OutQuad }
                            }
                            remove: Transition {
                                NumberAnimation { property: "opacity"; to: 0; duration: Theme.shortDuration || 150; easing.type: Theme.standardEasing || Easing.OutQuad }
                            }
                            displaced: Transition {
                                NumberAnimation { properties: "y"; duration: Theme.shortDuration || 150; easing.type: Theme.standardEasing || Easing.OutCubic }
                            }

                            WheelHandler {
                                id: conflictWheelHandler
                                acceptedDevices: PointerDevice.Mouse
                                enabled: conflictListView.contentHeight > conflictListView.height
                                onWheel: (event) => {
                                    if (event.pixelDelta && event.pixelDelta.y !== 0) return;
                                    let deltaY = event.angleDelta.y;
                                    if (deltaY === 0) return;
                                    let step = (deltaY > 0 ? -1 : 1) * 94;
                                    conflictListView.contentY = Math.max(0, Math.min(conflictListView.contentHeight - conflictListView.height, conflictListView.contentY + step));
                                    event.accepted = true;
                                }
                            }

                            delegate: Item {
                                id: conflictItemDelegate
                                width: ListView.view.width
                                height: 94
                                clip: true

                                readonly property bool isFirst: index === 0
                                readonly property bool isLast: index === conflictListView.count - 1
                                readonly property real outerRad: Theme.groupedListOuterRadius || Theme.cornerRadiusL || 14
                                readonly property real innerRad: Theme.groupedListInnerRadius || Theme.cornerRadiusXS || 4
                                property bool hovered: itemDelegateMA.containsMouse

                                // Category differentiation (supports ListModel properties directly as well as modelData)
                                readonly property var itemData: (typeof modelData !== "undefined" && modelData) ? modelData : model
                                readonly property bool hasEpConflict: itemData.hasEpDiff === true || itemData.conflictType === "progress" || itemData.conflictType === "both"
                                readonly property bool hasStatusConflict: itemData.hasStatusDiff === true || itemData.conflictType === "status" || itemData.conflictType === "both"
                                readonly property bool isBothDiff: hasEpConflict && hasStatusConflict
                                readonly property bool isProgressDiff: hasEpConflict && !hasStatusConflict
                                readonly property bool isStatusDiff: hasStatusConflict && !hasEpConflict
                                
                                readonly property color accentColor: isBothDiff ? (Theme.warning || "#FFB300") : (isProgressDiff ? Theme.primary : (Theme.secondary || "#E040FB"))
                                readonly property string badgeIcon: isBothDiff ? "warning" : (isProgressDiff ? "sync_problem" : "bookmark_border")
                                readonly property string badgeLabel: isBothDiff ? "EP & STATUS DESYNC" : (isProgressDiff ? "EPISODE DESYNC" : "STATUS CHANGED")

                                Rectangle {
                                    id: conflictItemRowBg
                                    anchors.fill: parent
                                    clip: true
                                    radius: innerRad
                                    topLeftRadius: isFirst ? outerRad : innerRad
                                    topRightRadius: isFirst ? outerRad : innerRad
                                    bottomLeftRadius: isLast ? outerRad : innerRad
                                    bottomRightRadius: isLast ? outerRad : innerRad

                                    Behavior on topLeftRadius { NumberAnimation { duration: 150 } }
                                    Behavior on topRightRadius { NumberAnimation { duration: 150 } }
                                    Behavior on bottomLeftRadius { NumberAnimation { duration: 150 } }
                                    Behavior on bottomRightRadius { NumberAnimation { duration: 150 } }

                                    color: conflictItemDelegate.hovered
                                        ? Theme.withAlpha(Theme.surfaceVariant, 0.14)
                                        : (Theme.foregroundColor ? Theme.foregroundColor(Theme.chipSurface) : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.05))

                                    border.width: 1
                                    border.color: conflictItemDelegate.hovered
                                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.40)
                                        : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on border.color { ColorAnimation { duration: 150 } }

                                    DankRipple {
                                        id: rowRipple
                                        anchors.fill: parent
                                        cornerRadius: isFirst || isLast ? outerRad : innerRad
                                        rippleColor: Theme.primary
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    anchors.topMargin: 7
                                    anchors.bottomMargin: 7
                                    spacing: 14

                                    // Anime Cover Thumbnail with 1.5x scale (60x82.5, matching 80x110 schedule aspect ratio 1:1.375)
                                    ClippingRectangle {
                                        id: coverThumbBox
                                        width: 60
                                        height: 80
                                        radius: 10
                                        antialiasing: true
                                        color: Theme.withAlpha(Theme.surfaceContainer, 0.5)

                                        Image {
                                            anchors.fill: parent
                                            source: conflictItemDelegate.itemData.image || ""
                                            fillMode: Image.PreserveAspectCrop
                                            visible: source.toString() !== ""
                                        }

                                        DankIcon {
                                            anchors.centerIn: parent
                                            name: "image"
                                            size: 28
                                            color: Theme.surfaceVariantText
                                            visible: !conflictItemDelegate.itemData.image || conflictItemDelegate.itemData.image === ""
                                            opacity: 0.6
                                        }
                                    }

                                    // Information details with clear category differentiation badge
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 4

                                        // Category Pill Badge
                                        Rectangle {
                                            implicitWidth: catRow.implicitWidth + 12
                                            implicitHeight: 20
                                            radius: 10
                                            color: Theme.withAlpha(conflictItemDelegate.accentColor, 0.18)
                                            border.width: 1
                                            border.color: Theme.withAlpha(conflictItemDelegate.accentColor, 0.45)

                                            Row {
                                                id: catRow
                                                anchors.centerIn: parent
                                                spacing: 4

                                                DankIcon {
                                                    name: conflictItemDelegate.badgeIcon
                                                    size: 13
                                                    color: conflictItemDelegate.accentColor
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }

                                                StyledText {
                                                    text: conflictItemDelegate.badgeLabel
                                                    font.pixelSize: 10
                                                    font.bold: true
                                                    color: conflictItemDelegate.accentColor
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }
                                        }

                                        Item {
                                            Layout.fillWidth: true
                                            height: 20
                                            clip: true

                                            ScrollingText {
                                                anchors.fill: parent
                                                text: conflictItemDelegate.itemData.title || ""
                                                font.pixelSize: Theme.fontSizeMedium
                                                font.bold: true
                                                color: Theme.surfaceText
                                            }
                                        }

                                        StyledText {
                                            text: conflictItemDelegate.itemData.reason || ""
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Medium
                                            color: conflictItemDelegate.accentColor
                                            elide: Text.ElideRight
                                            maximumLineCount: 2
                                            wrapMode: Text.Wrap
                                            Layout.fillWidth: true
                                        }
                                    }

                                    // Custom Ignore Button (Segmented pill style with icon & morphing hover radii)
                                    Rectangle {
                                        id: itemIgnoreBtn
                                        implicitWidth: ignoreBtnRow.implicitWidth + 24
                                        implicitHeight: 36
                                        Layout.alignment: Qt.AlignVCenter
                                        scale: itemIgnoreMA.pressed ? 0.94 : (itemIgnoreMA.containsMouse ? 1.03 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                        topLeftRadius: itemIgnoreMA.containsMouse ? (height / 2) : 6
                                        bottomLeftRadius: itemIgnoreMA.containsMouse ? (height / 2) : 6
                                        topRightRadius: itemIgnoreMA.containsMouse ? (height / 2) : 14
                                        bottomRightRadius: itemIgnoreMA.containsMouse ? (height / 2) : 14

                                        Behavior on topLeftRadius { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                        Behavior on bottomLeftRadius { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                        Behavior on topRightRadius { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                        Behavior on bottomRightRadius { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }

                                        color: itemIgnoreMA.containsMouse
                                            ? Theme.withAlpha(Theme.primary, 0.22)
                                            : Theme.withAlpha(Theme.surfaceVariantText, 0.16)
                                        border.width: 1
                                        border.color: itemIgnoreMA.containsMouse
                                            ? Theme.withAlpha(Theme.primary, 0.50)
                                            : Theme.withAlpha(Theme.surfaceVariantText, 0.25)

                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Behavior on border.color { ColorAnimation { duration: 150 } }

                                        DankRipple {
                                            id: itemIgnoreRip
                                            anchors.fill: parent
                                            cornerRadius: itemIgnoreBtn.topLeftRadius
                                            rippleColor: Theme.primary
                                        }

                                        Row {
                                            id: ignoreBtnRow
                                            anchors.centerIn: parent
                                            spacing: 6

                                            DankIcon {
                                                name: "visibility_off"
                                                size: 15
                                                color: itemIgnoreMA.containsMouse ? Theme.primary : Theme.surfaceText
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            StyledText {
                                                id: ignoreBtnText
                                                text: "Ignore Once"
                                                font.pixelSize: 12
                                                font.weight: Font.Medium
                                                color: itemIgnoreMA.containsMouse ? Theme.primary : Theme.surfaceText
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        MouseArea {
                                            id: itemIgnoreMA
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onPressed: mouse => itemIgnoreRip.trigger(mouse.x, mouse.y)
                                            onClicked: {
                                                root.ignoreConflict(conflictItemDelegate.itemData.animeId);
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: itemDelegateMA
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    z: -1
                                    onPressed: mouse => rowRipple.trigger(mouse.x, mouse.y)
                                }
                            }
                        }
                    }

                    // Bottom Action Button: Styled identical to the header error indicator button
                    // (Theme.error tint, theme corner radius, warning icon, smooth hover & ripple)
                    Rectangle {
                        id: ignoreAllBtn
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 4
                        implicitWidth: Math.max(170, ignoreAllRow.implicitWidth + 36)
                        implicitHeight: 40

                        color: ignoreAllMA.containsMouse ? Theme.withAlpha(Theme.error, 0.25) : Theme.withAlpha(Theme.error, 0.15)
                        border.width: 1
                        border.color: ignoreAllMA.containsMouse ? Theme.withAlpha(Theme.error, 0.85) : Theme.withAlpha(Theme.error, 0.50)
                        radius: Theme.cornerRadius

                        scale: ignoreAllMA.pressed ? 0.95 : (ignoreAllMA.containsMouse ? 1.03 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        DankRipple {
                            id: ignoreAllRip
                            anchors.fill: parent
                            cornerRadius: parent.radius
                            rippleColor: Theme.error
                        }

                        Row {
                            id: ignoreAllRow
                            anchors.centerIn: parent
                            spacing: 8

                            DankIcon {
                                name: "warning"
                                size: 18
                                color: Theme.error
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: "Ignore All Once"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.error
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: ignoreAllMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: mouse => ignoreAllRip.trigger(mouse.x, mouse.y)
                            onClicked: {
                                root.ignoreAllConflicts();
                            }
                        }
                    }
                }
            }
        }
    }
} // PluginComponent
