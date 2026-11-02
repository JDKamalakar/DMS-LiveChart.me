import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

// Required for MultiEffect rounding and shadow
import QtQuick.Effects

PluginComponent {
    id: root
    
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
        if (newShowNotes !== root.showInfoNotes) {
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
        for (let i = 0; i < root.fullScheduleData.length; i++) {
            if (root.fullScheduleData[i].day === root.currentDayName) {
                let sList = root.fullScheduleData[i].shows || [];
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

        for (let i = 0; i < root.fullScheduleData.length; i++) {
            let day = root.fullScheduleData[i];
            for (let j = 0; j < day.shows.length; j++) {
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

    function getServiceIcon(modelData) {
        if (!modelData) return "";
        let domain = (modelData.siteDomain || "").toLowerCase();
        let name = (modelData.siteName || "").toLowerCase();
        let link = (modelData.watchLink || "").toLowerCase();

        // 1. Check local assets/services/*.png
        if (domain.includes("crunchyroll") || name.includes("crunchyroll") || link.includes("crunchyroll"))
            return "assets/services/crunchyroll.png";
        if (domain.includes("netflix") || name.includes("netflix") || link.includes("netflix"))
            return "assets/services/netflix.png";
        if (domain.includes("hidive") || name.includes("hidive") || link.includes("hidive"))
            return "assets/services/hidive.png";
        if (domain.includes("disney") || name.includes("disney") || link.includes("disney"))
            return "assets/services/disneyplus.png";
        if (domain.includes("hulu") || name.includes("hulu") || link.includes("hulu"))
            return "assets/services/hulu.png";
        if (domain.includes("amazon") || domain.includes("primevideo") || name.includes("prime") || link.includes("amazon") || link.includes("primevideo"))
            return "assets/services/primevideo.png";
        if (domain.includes("youtube") || name.includes("youtube") || link.includes("youtube") || domain.includes("youtu.be"))
            return "assets/services/youtube.png";

        // 2. Direct scraped icon if provided (e.g. LiveChart mask or custom host)
        if (modelData.sourceIcon && modelData.sourceIcon !== "")
            return modelData.sourceIcon;

        // 3. Fallback to Google Favicon service if domain exists
        if (modelData.siteDomain && modelData.siteDomain !== "")
            return "https://www.google.com/s2/favicons?domain=" + modelData.siteDomain + "&sz=64";

        return "";
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
            root.browserName
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
    property bool showConflictModal: false
    property string activeStatusMenuAnimeId: ""

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

    function recordUserChange(animeId, title, episodesWatched, status) {
        if (!animeId) return;
        var map = Object.assign({}, root.backupRecords);
        var prev = map[String(animeId)] || {};
        map[String(animeId)] = {
            animeId: String(animeId),
            title: title || prev.title || "Anime #" + animeId,
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

                var reason = "";
                // Check episode regression
                if (b.episodesWatched !== undefined && b.episodesWatched !== null) {
                    var currentEp = show.currentProgress || 0;
                    if (currentEp < b.episodesWatched) {
                        reason = "Progress dropped to EP" + currentEp + " (expected EP" + b.episodesWatched + ")";
                    }
                }
                // Check status mismatch
                if (!reason && b.status && show.libraryStatus) {
                    var sCurrent = String(show.libraryStatus).toLowerCase().replace('-', '_');
                    var sExpected = String(b.status).toLowerCase().replace('-', '_');
                    if (sCurrent !== sExpected) {
                        reason = "Status is '" + show.libraryStatus + "' (expected '" + b.status + "')";
                    }
                }

                if (reason) {
                    // Check if already in found list
                    var exists = false;
                    for (var k = 0; k < found.length; k++) {
                        if (found[k].animeId === aid) { exists = true; break; }
                    }
                    if (!exists) {
                        found.push({
                            animeId: aid,
                            title: show.title || b.title,
                            reason: reason,
                            expectedEp: b.episodesWatched,
                            expectedStatus: b.status
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
            root.showConflictModal = false;
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
        root.showConflictModal = false;
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

    function updateAnimeProgress(animeId, episodesWatched, status, animeTitle, totalEpisodes, currentStatus) {
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

        // Record backup change
        root.recordUserChange(animeId, animeTitle, targetEp, targetStatus);

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
                    }
                }
            }

            Component.onDestruction: {
                root.activeStatusMenuAnimeId = "";
            }
            
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
                        spacing: 8

                        // Conflict Indicator Button (shown only when changes were reverted / outside update detected)
                        Item {
                            id: conflictBtnContainer
                            visible: root.conflictItems.length > 0
                            width: 42
                            height: 42
                            scale: conflictArea.pressed ? 0.9 : (conflictArea.containsMouse ? 1.1 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.cornerRadius
                                color: conflictArea.containsMouse ? Theme.withAlpha(Theme.error, 0.25) : Theme.withAlpha(Theme.error, 0.15)
                                border.width: 1
                                border.color: Theme.withAlpha(Theme.error, 0.5)
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
                                onClicked: root.showConflictModal = true
                            }
                        }

                        Item {
                            id: refreshContainer
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
                                id: refreshBg
                                anchors.fill: parent
                                radius: root.isLoading ? (height / 2) : Theme.cornerRadius
                                color: refreshArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.4)
                                border.width: 1
                                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, refreshArea.containsMouse ? 0.3 : 0.15)
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                Behavior on radius { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
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

                            DankRipple {
                                id: refreshRipple
                                rippleColor: Theme.surfaceText
                                cornerRadius: refreshBg.radius
                                anchors.fill: parent
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
                    visible: root.scheduleData.length > 0
                    width: parent.width
                    height: 540 // Increased to accommodate headers
                    orientation: ListView.Horizontal
                    model: root.scheduleData
                    spacing: 12 // Reduced gap
                    clip: root.activeStatusMenuAnimeId === ""
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
                                 clip: root.activeStatusMenuAnimeId === ""
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
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 8

                                            // Top Bar: Time, Countdown, and Bookmark
                                            RowLayout {
                                                id: cardTopBar
                                                Layout.fillWidth: true
                                                spacing: 4
                                                z: (String(modelData.animeId || "") === root.activeStatusMenuAnimeId) ? 100 : 1

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
                                                                                          root.updateAnimeProgress(aid, curEp, targetStatus, aTitle, innerDelegate.showItem.totalEpisodes, innerDelegate.showItem.libraryStatus);
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
                                                                    source: root.getServiceIcon(modelData)
                                                                    visible: source.toString() !== ""
                                                                    smooth: true
                                                                    mipmap: true
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
                                                                name: modelData.isInfoNote ? "info" : "link"
                                                                size: 16
                                                                color: modelData.isInfoNote ? (Theme.warning || "#FFC107") : Theme.withAlpha(Theme.buttonBg, 0.7)
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
                                            readonly property int epDifference: Math.max(0, cardEp - currEp)
                                            readonly property bool hasMultipleUnwatched: !modelData.isWatched && !modelData.isInfoNote && epDifference > 1

                                            property bool isExpanded: countMA.containsMouse || tickMA.containsMouse || mainProgressHover.containsMouse

                                            // When hovered, expand horizontally into 2 segmented buttons (width 62);
                                            // When not hovered, compact into a single button (width 28) with number tucked above
                                            width: hasMultipleUnwatched ? (isExpanded ? 62 : 28) : 28
                                            height: 28
                                            visible: !modelData.isWatched && !modelData.isInfoNote
                                            z: 30

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
                                                            root.updateAnimeProgress(modelData.animeId, nextEp, "WATCHING", modelData.title, modelData.totalEpisodes, modelData.libraryStatus);
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
                                                        var targetEp = markWatchedBtn.cardEp > 0 ? markWatchedBtn.cardEp : (modelData.progressTarget || ((modelData.currentProgress || 0) + 1));
                                                        if (modelData.animeId) {
                                                            root.updateAnimeProgress(modelData.animeId, targetEp, "WATCHING", modelData.title, modelData.totalEpisodes, modelData.libraryStatus);
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




        // Conflict Popup Dialog (shows when progress/status was reverted or changed outside plugin)
        Rectangle {
            id: conflictModal
            visible: root.showConflictModal && root.conflictItems.length > 0
            anchors.fill: parent
            color: Theme.withAlpha("#000000", 0.6)
            z: 999

            // Material 3 Expressive Background Shapes (rotating in place across different positions)
            Item {
                anchors.fill: parent
                z: -1
                opacity: 0.25

                DMaterialShape {
                    shape: "cookie4"
                    color: Theme.error
                    implicitWidth: 160
                    implicitHeight: 160
                    x: 40
                    y: 30

                    RotationAnimation on rotation {
                        from: 0
                        to: 360
                        duration: 24000
                        loops: Animation.Infinite
                        running: conflictModal.visible
                    }
                }

                DMaterialShape {
                    shape: "sunny"
                    color: Theme.warning || "#FF9800"
                    implicitWidth: 140
                    implicitHeight: 140
                    x: parent.width - 180
                    y: 40

                    RotationAnimation on rotation {
                        from: 360
                        to: 0
                        duration: 28000
                        loops: Animation.Infinite
                        running: conflictModal.visible
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                // absorb clicks outside
            }

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(560, parent.width * 0.9)
                height: Math.min(480, conflictCol.implicitHeight + 48)
                radius: 24
                color: Theme.withAlpha(Theme.surfaceContainer || "#1E1E1E", 0.95)
                border.width: 1
                border.color: Theme.withAlpha(Theme.error, 0.4)

                ColumnLayout {
                    id: conflictCol
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 16

                    DankIcon {
                        name: "warning"
                        size: 48
                        color: Theme.error
                        Layout.alignment: Qt.AlignHCenter
                    }

                    StyledText {
                        text: "Sync Discrepancy Detected"
                        font.pixelSize: Theme.fontSizeLarge
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

                    // Conflict Items List
                    DankListView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(180, root.conflictItems.length * 56)
                        clip: true
                        model: root.conflictItems
                        spacing: 8

                        delegate: Rectangle {
                            width: ListView.view.width
                            height: 48
                            radius: 10
                            color: Theme.withAlpha(Theme.surfaceContainerHigh || "#2A2A2A", 0.7)
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.surfaceVariantText, 0.15)

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 8

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    StyledText {
                                        text: modelData.title
                                        font.bold: true
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceText
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    StyledText {
                                        text: modelData.reason
                                        font.pixelSize: 11
                                        color: Theme.error
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                DButton {
                                    text: "Ignore Once"
                                    buttonHeight: 30
                                    backgroundColor: Theme.withAlpha(Theme.surfaceVariantText, 0.2)
                                    textColor: Theme.surfaceText
                                    onClicked: {
                                        root.ignoreConflict(modelData.animeId);
                                    }
                                }
                            }
                        }
                    }

                    // Action Buttons (Ignore All & Close)
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 12

                        DButton {
                            text: "Ignore All Once"
                            iconName: "check"
                            buttonHeight: 38
                            backgroundColor: Theme.error
                            textColor: "white"
                            onClicked: {
                                root.ignoreAllConflicts();
                            }
                        }

                        DButton {
                            text: "Dismiss"
                            buttonHeight: 38
                            backgroundColor: Theme.withAlpha(Theme.surfaceVariantText, 0.2)
                            textColor: Theme.surfaceText
                            onClicked: {
                                root.showConflictModal = false;
                            }
                        }
                    }
                }
            }
        }
    } // PopoutComponent
} // Component (popoutContent)
} // PluginComponent
