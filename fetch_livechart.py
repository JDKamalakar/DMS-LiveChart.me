#!/usr/bin/env python3
import sys
import json
import sqlite3
import shutil
import os
import re
import urllib.request
import hashlib
import configparser
import subprocess


def get_default_profile_path(profiles_ini_path):
    import configparser
    
    if not os.path.exists(profiles_ini_path):
        return None
        
    config = configparser.ConfigParser()
    try:
        config.read(profiles_ini_path)
    except Exception as e:
        print(f"DEBUG: Failed to read {profiles_ini_path}: {e}", file=sys.stderr)
        return None

    base_dir = os.path.dirname(profiles_ini_path)
    
    # Priority 1: Check [Install...] sections (Firefox 67+)
    for section in config.sections():
        if section.startswith("Install"):
            path = config.get(section, "Default", fallback=None)
            if path:
                full_path = os.path.join(base_dir, path)
                if os.path.exists(full_path):
                    print(f"DEBUG: Found profile from Install section: {full_path}", file=sys.stderr)
                    return full_path

    # Priority 2: Check [Profile...] sections for Default=1
    for section in config.sections():
        if section.startswith("Profile"):
            if config.get(section, "Default", fallback="0") == "1":
                path = config.get(section, "Path", fallback=None)
                if path:
                    is_relative = config.get(section, "IsRelative", fallback="1") == "1"
                    full_path = os.path.join(base_dir, path) if is_relative else path
                    if os.path.exists(full_path):
                        print(f"DEBUG: Found profile from Profile section (Default=1): {full_path}", file=sys.stderr)
                        return full_path
                        
    # Priority 3: Fallback to any profile
    for section in config.sections():
        if section.startswith("Profile"):
            path = config.get(section, "Path", fallback=None)
            if path:
                is_relative = config.get(section, "IsRelative", fallback="1") == "1"
                full_path = os.path.join(base_dir, path) if is_relative else path
                if os.path.exists(full_path):
                    print(f"DEBUG: Found fallback profile: {full_path}", file=sys.stderr)
                    return full_path

    return None


def find_brand_profile_dir(brand):
    import glob
    
    home = os.path.expanduser("~")
    search_paths = []
    
    if brand == "firefox":
        search_paths = [
            os.path.join(home, ".mozilla/firefox"), # Standard
            os.path.join(home, ".config/mozilla/firefox"), # Fedora / Silverblue Standard
            os.path.join(home, "snap/firefox/common/.mozilla/firefox"), # Snap
            os.path.join(home, "snap/firefox/current/.mozilla/firefox"), # Snap Alt
            os.path.join(home, ".var/app/org.mozilla.firefox/.mozilla/firefox"), # Flatpak
            os.path.join(home, "Library/Application Support/Firefox"), # macOS style / unusual Linux
            os.path.join(home, ".mozilla/firefox-trunk"), # Nightly
            os.path.join(home, ".mozilla/firefox-dev"), # Dev
        ]
    elif brand == "zen":
        search_paths = [
            os.path.join(home, ".zen"), # Standard
            os.path.join(home, ".config/zen"), # Legacy
            os.path.join(home, ".var/app/app.zen_browser.zen/zen"), # Flatpak
            os.path.join(home, ".var/app/io.github.zen_browser.zen/zen"), # Flatpak Alt
        ]
    elif brand == "librewolf":
        search_paths = [
            os.path.join(home, ".librewolf"),
            os.path.join(home, ".var/app/io.gitlab.librewolf-community/.librewolf"),
        ]
    elif brand == "waterfox":
        search_paths = [
            os.path.join(home, ".waterfox"),
        ]
        
    profile_candidates = []
    for base in search_paths:
        if not os.path.isdir(base):
            continue
            
        print(f"DEBUG: Checking browser base directory: {base}", file=sys.stderr)
        profiles_ini = os.path.join(base, "profiles.ini")
        profile_path = get_default_profile_path(profiles_ini)
        if profile_path and os.path.isdir(profile_path):
            if os.path.exists(os.path.join(profile_path, 'cookies.sqlite')):
                # Prioritize the default profile found via profiles.ini
                return profile_path
            
        # Aggressive recursive search as fallback
        for root, dirs, files in os.walk(base, followlinks=True):
            if 'cookies.sqlite' in files:
                db_path = os.path.join(root, 'cookies.sqlite')
                try:
                    mtime = os.path.getmtime(db_path)
                    profile_candidates.append((mtime, root))
                except OSError:
                    continue
            # Don't go too deep into cache or other folders
            if 'cache' in root.lower() or 'storage' in root.lower():
                dirs[:] = [] 
                
    if not profile_candidates:
        # Final Resort: Deep Search of Home Directory (avoiding obvious non-browser folders)
        print(f"DEBUG: No standard paths found. Initiating deep search in {home}", file=sys.stderr)
        exclude_dirs = {'.cache', 'Downloads', 'Pictures', 'Videos', 'Music', 'Desktop', '.local/share/Trash', '.git', 'node_modules', '.cargo', '.sdk'}
        for root, dirs, files in os.walk(home, followlinks=False):
            root_parts = root.split(os.sep)
            if any(part in exclude_dirs for part in root_parts):
                dirs[:] = [] # Skip excluded trees
                continue
                
            if 'cookies.sqlite' in files:
                db_path = os.path.join(root, 'cookies.sqlite')
                # Prioritize paths that look like they belong to a browser
                if any(x in root.lower() for x in ['firefox', 'mozilla', brand]):
                    try:
                        mtime = os.path.getmtime(db_path)
                        profile_candidates.append((mtime, root))
                    except OSError:
                        pass
            
            # Limit depth for general home walking to prevent infinite hangs
            if len(root_parts) - len(home.split(os.sep)) > 6:
                dirs[:] = []
                
    if profile_candidates:
        # Sort by most recently modified cookies database
        profile_candidates.sort(key=lambda x: x[0], reverse=True)
        latest_profile = profile_candidates[0][1]
        print(f"DEBUG: Found {len(profile_candidates)} candidate profiles. Picking most recent: {latest_profile}", file=sys.stderr)
        return latest_profile
                
    return None


def get_cookies_firefox(browser_type):
    # Step 1: Try browser_cookie3 primary discovery first (standard installations)
    try:
        import browser_cookie3
        print(f"DEBUG: Attempting browser_cookie3 discovery for {browser_type}", file=sys.stderr)
        
        cj = None
        if browser_type == 'firefox':
            cj = browser_cookie3.firefox(domain_name='livechart.me')
        elif browser_type in ['librewolf', 'waterfox']:
            # browser_cookie3 might support these via general firefox() if path is found
            cj = browser_cookie3.firefox(domain_name='livechart.me')
            
        if cj and len(cj) > 0:
            print(f"DEBUG: browser_cookie3 found {len(cj)} cookies", file=sys.stderr)
            import urllib.request
            req = urllib.request.Request("https://www.livechart.me/")
            cj.add_cookie_header(req)
            return req.get_header('Cookie', '')
    except Exception as e:
        print(f"DEBUG: Initial browser_cookie3 discovery failed: {e}", file=sys.stderr)

    # Step 2: Fallback to Manual Profile Discovery
    profile_dir = find_brand_profile_dir(browser_type)
    
    if not profile_dir:
        print(f"DEBUG: No profile directory found for {browser_type}", file=sys.stderr)
        return ""
        
    cookie_db = os.path.join(profile_dir, 'cookies.sqlite')
    tmp_db = '/tmp/livechart_cookies.sqlite'
    
    print(f"DEBUG: Using cookie database: {cookie_db}", file=sys.stderr)
    
    if os.path.exists(cookie_db):
        # Step 3: Try browser_cookie3 on the SPECIFIC file we found
        try:
            import browser_cookie3
            cj = browser_cookie3.firefox(cookie_file=cookie_db, domain_name='livechart.me')
            if len(cj) > 0:
                print(f"DEBUG: browser_cookie3 (file-mode) found {len(cj)} cookies", file=sys.stderr)
                import urllib.request
                req = urllib.request.Request("https://www.livechart.me/")
                cj.add_cookie_header(req)
                return req.get_header('Cookie', '')
        except Exception as e:
            print(f"DEBUG: browser_cookie3 file-mode failed: {e}", file=sys.stderr)

        # Step 4: Final Fallback - Direct SQLite Extraction (Safe as Firefox cookies aren't encrypted on Linux)
        try:
            shutil.copy2(cookie_db, tmp_db)
            conn = sqlite3.connect(tmp_db)
            cursor = conn.cursor()
            cursor.execute("SELECT name, value FROM moz_cookies WHERE host LIKE '%livechart.me%'")
            cookies = cursor.fetchall()
            conn.close()
            print(f"DEBUG: SQLite extraction found {len(cookies)} cookies", file=sys.stderr)
            try: os.unlink(tmp_db)
            except: pass
            
            if not cookies:
                return ""
            return "; ".join([f"{name}={value}" for name, value in cookies])
        except Exception as e:
            print(f"DEBUG: Direct SQLite extraction failed: {e}", file=sys.stderr)
            return ""
    
    return ""

def get_cookies_chrome(browser_type):
    try:
        import browser_cookie3
    except ImportError:
        raise ImportError("Please install browser_cookie3 to use Chrome cookies: pip3 install browser_cookie3")
        
    if browser_type == 'chrome_beta':
        cookie_file = os.path.expanduser('~/.config/google-chrome-beta/Default/Cookies')
        alt_cookie_file = os.path.expanduser('~/.config/google-chrome-beta/Default/Network/Cookies')
        
        if os.path.exists(cookie_file):
            cj = browser_cookie3.chrome(cookie_file=cookie_file, domain_name='livechart.me')
        elif os.path.exists(alt_cookie_file):
            cj = browser_cookie3.chrome(cookie_file=alt_cookie_file, domain_name='livechart.me')
        else:
            raise FileNotFoundError(f"Chrome Beta cookies not found at {cookie_file} or {alt_cookie_file}")
    else:
        cj = browser_cookie3.chrome(domain_name='livechart.me')
    return cj

def report_missing_dependency(module_name, package_name):
    """Run pip show for the package and report JSON error to stdout"""
    try:
        # Run pip show as requested by the user to get the official status message
        result = subprocess.run([sys.executable, "-m", "pip", "show", package_name], 
                               capture_output=True, text=True)
        
        detail = result.stderr if result.stderr else result.stdout
        if "not found" in detail.lower() or result.returncode != 0:
            error_msg = f"Package '{package_name}' not found. {detail.strip()}"
        else:
            error_msg = f"The '{module_name}' library is installed but could not be imported."

        print(json.dumps({
            "success": False,
            "error_type": "missing_dependency",
            "error": error_msg,
            "dependency": package_name,
            "install_cmd": f"pip3 install {package_name}"
        }))
    except Exception as e:
        # Fallback if pip show itself fails
        print(json.dumps({
            "success": False,
            "error_type": "missing_dependency",
            "error": f"The '{module_name}' library is not installed.",
            "dependency": package_name,
            "install_cmd": f"pip3 install {package_name}"
        }))
    
    sys.stdout.flush()
    sys.exit(1)

def check_dependencies():
    """Ensure all required libraries are present before proceeding"""
    try:
        from bs4 import BeautifulSoup
    except ImportError:
        report_missing_dependency("bs4", "beautifulsoup4")
        
    try:
        import browser_cookie3
    except ImportError:
        report_missing_dependency("browser_cookie3", "browser-cookie3")

def extract_cookie_header(browser_type):
    # Dependency check is now handled globally at startup, 
    # but we import here to use the module.
    import browser_cookie3

    if browser_type == "firefox" or browser_type == "zen":
        return get_cookies_firefox(browser_type)
    elif browser_type in ["chrome", "chrome_beta"]:
        cj = get_cookies_chrome(browser_type)
        if cj:
            import urllib.request
            req = urllib.request.Request("https://www.livechart.me/")
            cj.add_cookie_header(req)
            return req.get_header('Cookie', '')
    return ""

def _cookie_worker(browser_type, result_file):
    import sys
    import os
    
    try:
        cookie_str = extract_cookie_header(browser_type)
        with open(result_file, 'w') as f:
            json.dump({"success": True, "cookie": cookie_str}, f)
    except Exception as e:
        with open(result_file, 'w') as f:
            json.dump({"success": False, "error": str(e)}, f)
            
    # Critical fix: Close OS-level inherited pipes so hanging children don't keep QML IPC streams open indefinitely
    # Doing this AFTER extraction so debug prints don't hit "Bad file descriptor"
    try:
        os.close(1)
        os.close(2)
    except OSError:
        pass

CACHE_DIR = os.path.join("/tmp", "liveChartSchedule", "cache")

def download_image(url, opener):
    if not url:
        return ""
    
    if not os.path.exists(CACHE_DIR):
        os.makedirs(CACHE_DIR)
        
    # Generate a unique filename based on the URL
    ext = url.split('.')[-1]
    if len(ext) > 4: # Sanity check for long extensions or queries
        ext = "jpg"
    filename = hashlib.md5(url.encode()).hexdigest() + "." + ext
    filepath = os.path.join(CACHE_DIR, filename)
    
    if os.path.exists(filepath):
        return "file://" + filepath
        
    try:
        req = urllib.request.Request(url)
        req.add_header('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
        req.add_header('Referer', 'https://www.livechart.me/')
        
        with opener.open(req, timeout=10) as response:
            with open(filepath, 'wb') as f:
                f.write(response.read())
        return "file://" + filepath
    except Exception as e:
        # Fallback to original URL if download fails
        print(f"DEBUG: Failed to download {url}: {e}", file=sys.stderr)
        return url

def get_livechart_data(date_str, browser_type="firefox"):
    import datetime
    import multiprocessing
    import tempfile

    url = f"https://www.livechart.me/schedule?date={date_str}"
        
    opener = urllib.request.build_opener()
    user_agent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    
    try:
        tmp_file = tempfile.NamedTemporaryFile(delete=False, mode='w+')
        tmp_file.close()
        
        p = multiprocessing.Process(target=_cookie_worker, args=(browser_type, tmp_file.name))
        p.start()
        
        p.join(5) # 5 second hard OS timeout
        
        if p.is_alive():
            p.terminate()
            p.join(1)
            
        if os.path.exists(tmp_file.name):
            try:
                with open(tmp_file.name, 'r') as f:
                    content = f.read()
                    if content:
                        result = json.loads(content)
                        if result.get("success"):
                            cookie_str = result.get("cookie")
                            if cookie_str:
                                opener.addheaders = [('Cookie', cookie_str)]
                        else:
                            raise Exception(result.get("error"))
                    else:
                        raise TimeoutError("Cookie extraction timed out (Keyring locked or database busy)")
            finally:
                os.unlink(tmp_file.name)
        else:
            raise Exception("Failed to retrieve cookie extraction result")
                
    except Exception as e:
        print(json.dumps({"error": f"Cookie loading failed: {str(e)}"}))
        sys.stdout.flush()
        os._exit(1)
        return

    req = urllib.request.Request(url)
    req.add_header('User-Agent', user_agent)
    
    try:
        from bs4 import BeautifulSoup
        response = opener.open(req, timeout=15)
        html = response.read().decode('utf-8')
        soup = BeautifulSoup(html, 'html.parser')
        
        results = []
        days = soup.find_all('div', class_='lc-timetable-day')
        
        for daily_section in days:
            header_el = daily_section.find('h2')
            if not header_el: continue
            
            # e.g. "Sun\n        Mar 8"
            raw_text = header_el.text.strip().split('\n')
            day_name = raw_text[0].strip() if len(raw_text) > 0 else "Unknown"
            date_name = raw_text[-1].strip() if len(raw_text) > 1 else ""
            
            anime_list = []
            slots = daily_section.find_all('div', class_='lc-timetable-timeslot')
            
            for slot in slots:
                # Get shared slot-level data
                timestamp = slot.get('data-timestamp') or ""
                
                countdown_elem = slot.find('span', class_='lc-tt-countdown') or slot.find('time', class_='lc-tt-countdown')
                countdown = countdown_elem.text.strip() if countdown_elem else ''

                # Iterate over individual anime blocks within each timeslot
                # A single timeslot can contain multiple anime blocks
                anime_blocks = slot.find_all('div', class_='lc-timetable-anime-block')
                
                if not anime_blocks:
                    # Fallback: try to extract from slot directly (legacy timeslots)
                    title_elem = slot.find('a', class_='lc-tt-anime-title')
                    if not title_elem:
                        continue
                    anime_blocks = [slot]
                
                for block in anime_blocks:
                    title_elem = block.find('a', class_='lc-tt-anime-title')
                    title = title_elem.text.strip() if title_elem else 'Unknown Title'
                    
                    # Find episode label within this block
                    release_elem = block.find('a', class_='lc-tt-release-label')
                    release_label = release_elem.text.strip() if release_elem else ""
                    
                    # Get the EP span (first span with font-medium class inside release label)
                    ep_span = release_elem.find('span', class_='font-medium') if release_elem else None
                    if not ep_span:
                        ep_span = block.find('span')
                    ep_label = ep_span.text.strip() if ep_span else ""
                    
                    if (ep_label or release_label) and ("TBA" not in ep_label and "TBA" not in release_label):
                        time_str = f"{ep_label} {release_label}".strip()
                    else:
                        time_str = "TBA"
        
                    img_elem = block.find('img', class_='lc-tt-poster')
                    if not img_elem:
                        img_elem = block.find('img')
                    img_src = ""
                    if img_elem:
                        img_src = img_elem.get('src') or img_elem.get('data-src') or ''
                    
                    # Download image locally
                    if img_src:
                        img_src = download_image(img_src, opener)
                        
                    # Try to get source icon and domain
                    action_btn = block.find('a', class_='lc-tt-action-button')
                    watch_link = action_btn.get('href') if action_btn else ''
                    if watch_link and watch_link.startswith('/'):
                        watch_link = "https://www.livechart.me" + watch_link
                    
                    site_domain = ""
                    if watch_link:
                        from urllib.parse import urlparse
                        site_domain = urlparse(watch_link).netloc
                    
                    # Extract site name from release label (e.g., "EP10 · Sub - Crunchyroll")
                    site_name = ""
                    if release_label:
                        parts = release_label.split(' - ')
                        if len(parts) > 1:
                            site_name = parts[-1].strip()

                    source_icon = ""
                    if action_btn:
                        icon_img = action_btn.find('img')
                        if icon_img:
                            source_icon = icon_img.get('src') or icon_img.get('data-src') or ""
                    
                    time_val = ep_label.strip() if ep_label else "TBA"

                    anime_link = ""
                    if title_elem and title_elem.get('href'):
                        anime_link = "https://www.livechart.me" + title_elem.get('href')

                    # Library Status Extraction
                    # Priority 1: data-library-status attribute directly on the anime block div
                    library_status = block.get('data-library-status', '').strip()
                    
                    if not library_status or library_status == '':
                        library_status = "none"
                    
                    # Priority 2: data-mark-icon-viewer-status-value on the use element
                    if library_status == "none":
                        lib_btn = block.find('button', class_='lc-tt-library-button')
                        if lib_btn:
                            use_elem = lib_btn.find('use')
                            if use_elem:
                                # Check data-mark-icon-viewer-status-value attribute
                                viewer_status = use_elem.get('data-mark-icon-viewer-status-value', '')
                                if viewer_status and viewer_status != 'none':
                                    library_status = viewer_status
                                else:
                                    # Priority 3: parse href="#icon:mark:<status>"
                                    use_href = use_elem.get('href', '')
                                    match = re.search(r'#(?:icon:)?mark:([a-zA-Z]+)', use_href)
                                    if match:
                                        library_status = match.group(1)
                    
                    # Normalize status
                    library_status = library_status.replace('-', '_')
                    valid_statuses = {"planning", "watching", "rewatching", "considering", 
                                     "paused", "completed", "dropped", "skipping", "none"}
                    if library_status not in valid_statuses:
                        if library_status == "in_list":
                            library_status = "in-list"
                        elif library_status != "none":
                            print(f"DEBUG: Unknown library status '{library_status}' for {title}", file=sys.stderr)

                    # Episode Progress Extraction
                    card_ep_num = 0
                    if ep_label:
                        ep_match = re.search(r'EP\s*(\d+)', ep_label, re.IGNORECASE)
                        if ep_match:
                            card_ep_num = int(ep_match.group(1))
                    
                    if card_ep_num == 0:
                        ranges_str = block.get('data-schedule-anime-ranges', '')
                        if ranges_str:
                            range_match = re.search(r'\[(\d+),\s*(\d+)\]', ranges_str)
                            if range_match:
                                card_ep_num = int(range_match.group(2))
                    
                    user_target_ep = 0 # The episode the user needs to watch NEXT
                    progress_btn = block.find('button', title=lambda t: t and t.startswith('Progress to'))
                    if progress_btn:
                        prog_match = re.search(r'Progress to (\d+)', progress_btn.get('title', ''))
                        if prog_match:
                            user_target_ep = int(prog_match.group(1))

                    # Determine if the currently scheduled episode is considered "watched"
                    is_watched = False
                    
                    if library_status == "completed":
                        is_watched = True
                    else:
                        for btn in block.find_all('button', class_='lc-tt-progress-button'):
                            classes = " ".join(btn.get('class', [])).lower()
                            data_val = btn.get('data-mark-icon-viewer-status-value', '').lower()
                            use_tag = btn.find('use')
                            href_val = use_tag.get('href', '').lower() if use_tag else ''
                            
                            # LiveChart dynamically injects 'active' class or 'watched' explicitly when progressing
                            if 'active' in classes or data_val == 'watched' or 'watched' in href_val:
                                is_watched = True
                                break
                                
                        # Fallback for alternative SVGs explicitly marked watched
                        if not is_watched:
                            for use_tag in block.find_all('use'):
                                href = use_tag.get('href', '').lower()
                                if 'mark:watched' in href or 'mark-watched' in href:
                                    is_watched = True
                                    break

                    has_progress = user_target_ep > 0 or not is_watched
                    current_progress = user_target_ep - 1 if user_target_ep > 0 else 0
                    progress_target = user_target_ep

                    if title != 'Unknown Title' and time_str != 'TBA':
                        anime_list.append({
                            "title": title,
                            "time": time_val,
                            "episodeInfo": release_label.strip() if release_label else "",
                            "image": img_src,
                            "watchLink": watch_link,
                            "siteDomain": site_domain,
                            "siteName": site_name,
                            "sourceIcon": source_icon,
                            "countdown": countdown,
                            "timestamp": timestamp,
                            "animeLink": anime_link,
                            "libraryStatus": library_status,
                            "isWatched": is_watched,
                            "hasProgress": has_progress,
                            "currentProgress": current_progress,
                            "progressTarget": progress_target
                        })
            
            results.append({
                "day": day_name,
                "date": date_name,
                "shows": anime_list
            })
            
        print(json.dumps({
            "success": True,
            "date": date_str,
            "data": results
        }))
        sys.stdout.flush()
        # Force exit to prevent multiprocessing atexit handler from hanging on deadlocked DBus children
        os._exit(0)

    except Exception as e:
        import traceback
        err_msg = str(e)
        # Capture traceback for detail but keep error message clean
        print(f"DEBUG: Error in fetch_livechart: {traceback.format_exc()}", file=sys.stderr)
        
        print(json.dumps({
            "success": False,
            "error": err_msg,
            "error_type": "generic"
        }))
        sys.stdout.flush()
        sys.exit(1)

if __name__ == "__main__":
    try:
        # Check dependencies before doing anything else
        check_dependencies()
        
        date = sys.argv[1] if len(sys.argv) > 1 else "2026-03-01"
        browser = sys.argv[2] if len(sys.argv) > 2 else "firefox"
        get_livechart_data(date, browser)
    except Exception as e:
        import traceback
        err_msg = str(e)
        print(f"DEBUG: Critical Error in __main__: {traceback.format_exc()}", file=sys.stderr)
        print(json.dumps({
            "success": False,
            "error": err_msg,
            "error_type": "generic"
        }))
        sys.stdout.flush()
        sys.exit(1)
