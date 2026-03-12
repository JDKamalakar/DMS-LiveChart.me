#!/usr/bin/env python3
import sys
import json
import sqlite3
import shutil
import os
import urllib.request
from bs4 import BeautifulSoup

def get_cookies_firefox():
    cookie_db = os.path.expanduser('~/.mozilla/firefox/0mcpenfr.default-release/cookies.sqlite')
    tmp_db = '/tmp/livechart_cookies.sqlite'
    
    if os.path.exists(cookie_db):
        shutil.copy2(cookie_db, tmp_db)
        conn = sqlite3.connect(tmp_db)
        cursor = conn.cursor()
        cursor.execute("SELECT name, value FROM moz_cookies WHERE host LIKE '%livechart.me%'")
        cookies = cursor.fetchall()
        conn.close()
        return "; ".join([f"{name}={value}" for name, value in cookies])
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

def extract_cookie_header(browser_type):
    if browser_type == "firefox":
        return get_cookies_firefox()
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
    # Critical fix: Close OS-level inherited pipes so hanging children don't keep QML IPC streams open indefinitely
    try:
        os.close(1)
        os.close(2)
    except OSError:
        pass
    
    try:
        cookie_str = extract_cookie_header(browser_type)
        with open(result_file, 'w') as f:
            json.dump({"success": True, "cookie": cookie_str}, f)
    except Exception as e:
        with open(result_file, 'w') as f:
            json.dump({"success": False, "error": str(e)}, f)

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
                title_elem = slot.find('a', class_='lc-tt-anime-title')
                title = title_elem.text.strip() if title_elem else 'Unknown Title'
                
                ep_span = slot.find('span')
                ep_label = ep_span.text.strip() if ep_span else ""
                
                release_elem = slot.find('a', class_='lc-tt-release-label')
                release_label = release_elem.text.strip() if release_elem else ""
                
                if (ep_label or release_label) and ("TBA" not in ep_label and "TBA" not in release_label):
                    time_str = f"{ep_label} {release_label}".strip()
                else:
                    time_str = "TBA"
    
                img_elem = slot.find('img')
                img_src = ""
                if img_elem:
                    img_src = img_elem.get('src') or img_elem.get('data-src') or ''
                    
                # Try to get source icon and domain
                action_btn = slot.find('a', class_='lc-tt-action-button')
                watch_link = action_btn.get('href') if action_btn else ''
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
                
                countdown_elem = slot.find('span', class_='lc-tt-countdown') or slot.find('time', class_='lc-tt-countdown')
                countdown = countdown_elem.text.strip() if countdown_elem else ''

                # Try to get raw timestamp for QML formatting
                timestamp = slot.get('data-timestamp') or ""
                
                time_val = ep_label.strip() if ep_label else "TBA"

                anime_link = ""
                if title_elem and title_elem.get('href'):
                    anime_link = "https://www.livechart.me" + title_elem.get('href')

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
                        "animeLink": anime_link
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
        print(json.dumps({
            "success": False,
            "error": str(e)
        }))
        sys.stdout.flush()
        os._exit(1)

if __name__ == "__main__":
    date = sys.argv[1] if len(sys.argv) > 1 else "2026-03-01"
    browser = sys.argv[2] if len(sys.argv) > 2 else "firefox"
    get_livechart_data(date, browser)
