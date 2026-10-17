"""Bilder (Wikimedia Commons, nur kommerziell nutzbare Lizenzen), Börsen- und Wetterdaten."""
import re
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import httpx

from sources import clean

UA = {"User-Agent": "UeberblickNews/1.0 (https://github.com/nextcwc-hub/ueberblick)"}

# ------------------------------------------------------------------ Bilder

_OK_LICENSE = re.compile(r"^(cc0|public domain|pd|cc by(-sa)? \d(\.\d)?( [a-z]+)?)", re.I)


def commons_candidates(query: str, n: int = 6) -> list[dict]:
    if not query.strip():
        return []
    try:
        r = httpx.get("https://commons.wikimedia.org/w/api.php", headers=UA, timeout=15, params=dict(
            action="query", format="json", generator="search", gsrnamespace=6,
            gsrsearch=f"{query} filetype:bitmap", gsrlimit=20, prop="imageinfo",
            iiprop="url|size|mime|extmetadata", iiurlwidth=1280))
        pages = r.json().get("query", {}).get("pages", {})
    except Exception as ex:
        print(f"  commons fail: {ex}")
        return []
    out = []
    for p in sorted(pages.values(), key=lambda p: p.get("index", 99)):
        ii = (p.get("imageinfo") or [{}])[0]
        em = ii.get("extmetadata", {})
        lic = em.get("LicenseShortName", {}).get("value", "")
        w, h = ii.get("width", 0), ii.get("height", 0)
        if not _OK_LICENSE.match(lic.strip()) or "nc" in lic.lower() or "nd" in lic.lower():
            continue
        if ii.get("mime") != "image/jpeg" or w < 1200 or not h or not 1.2 <= w / h <= 2.1:
            continue
        artist = clean(em.get("Artist", {}).get("value", "")) or "Unbekannt"
        out.append({
            "title": p["title"].removeprefix("File:").rsplit(".", 1)[0][:120],
            "desc": clean(em.get("ImageDescription", {}).get("value", ""))[:200],
            "img": {
                "url": ii.get("thumburl") or ii["url"],
                "w": ii.get("thumbwidth", w), "h": ii.get("thumbheight", h),
                "credit": f"{artist[:80]} / Wikimedia Commons",
                "license": lic,
                "src": ii.get("descriptionurl", ""),
            },
        })
        if len(out) >= n:
            break
    return out


# ------------------------------------------------------------------ Börse

SYMBOLS = [
    ("^GDAXI", "DAX", "index"), ("^MDAXI", "MDAX", "index"), ("^TECDAX", "TecDAX", "index"),
    ("^STOXX50E", "Euro Stoxx 50", "index"), ("^DJI", "Dow Jones", "index"),
    ("^GSPC", "S&P 500", "index"), ("^NDX", "Nasdaq 100", "index"), ("^N225", "Nikkei 225", "index"),
    ("EURUSD=X", "Euro / Dollar", "fx"), ("GC=F", "Gold", "commodity"),
    ("BZ=F", "Öl (Brent)", "commodity"), ("BTC-EUR", "Bitcoin", "crypto"),
]


def _chart(sym: str, rng: str, interval: str):
    r = httpx.get(f"https://query1.finance.yahoo.com/v8/finance/chart/{sym}",
                  params={"range": rng, "interval": interval}, headers={"User-Agent": "Mozilla/5.0"}, timeout=15)
    res = r.json()["chart"]["result"][0]
    ts = res.get("timestamp") or []
    cl = res["indicators"]["quote"][0].get("close") or []
    pts = [[t, round(c, 4)] for t, c in zip(ts, cl) if c is not None]
    return res["meta"], pts


def _thin(pts, n):
    if len(pts) <= n:
        return pts
    step = len(pts) / n
    out = [pts[int(i * step)] for i in range(n)]
    out[-1] = pts[-1]
    return out


def _market(entry):
    sym, name, kind = entry
    try:
        meta, intraday = _chart(sym, "1d", "5m")
        _, hist = _chart(sym, "1y", "1d")
        price = meta.get("regularMarketPrice") or (intraday[-1][1] if intraday else None)
        prev = meta.get("chartPreviousClose") or meta.get("previousClose")
        if price is None or not prev:
            return None
        return {
            "sym": sym, "name": name, "kind": kind, "cur": meta.get("currency", ""),
            "price": price, "prev": prev, "pct": round((price - prev) / prev * 100, 2),
            "time": meta.get("regularMarketTime"),
            "intraday": _thin(intraday, 120), "history": _thin(hist, 260),
        }
    except Exception as ex:
        print(f"  market fail {sym}: {ex}")
        return None


def markets() -> dict:
    with ThreadPoolExecutor(8) as ex:
        items = [m for m in ex.map(_market, SYMBOLS) if m]
    return {"updated": int(time.time()), "items": items}


def markets_brief(m: dict) -> str:
    return "Aktuelle Marktdaten: " + "; ".join(
        f"{x['name']} {x['price']:.2f} ({x['pct']:+.2f} %)" for x in m.get("items", []))


# ------------------------------------------------------------------ Wetter (DWD via Bright Sky)

CITIES = [("Hamburg", 53.55, 9.99), ("Berlin", 52.52, 13.40), ("Köln", 50.94, 6.96),
          ("Frankfurt", 50.11, 8.68), ("Leipzig", 51.34, 12.37), ("Stuttgart", 48.78, 9.18),
          ("München", 48.14, 11.58), ("Rostock", 54.09, 12.10), ("Hannover", 52.37, 9.73),
          ("Nürnberg", 49.45, 11.08), ("Freiburg", 47.99, 7.85), ("Dresden", 51.05, 13.74)]


def _city_weather(c, day0, day2):
    name, lat, lon = c
    try:
        r = httpx.get("https://api.brightsky.dev/weather", timeout=15,
                      params={"lat": lat, "lon": lon, "date": day0, "last_date": day2, "tz": "Europe/Berlin"})
        w = r.json()["weather"]
    except Exception:
        return None
    days = {}
    for h in w:
        d = h["timestamp"][:10]
        x = days.setdefault(d, {"t": [], "rain": 0.0, "gust": 0, "cond": {}, "sun": 0})
        if h.get("temperature") is not None:
            x["t"].append(h["temperature"])
        x["rain"] += h.get("precipitation") or 0
        x["gust"] = max(x["gust"], h.get("wind_gust_speed") or 0)
        x["sun"] += (h.get("sunshine") or 0) / 60
        icon = h.get("icon")
        if icon:
            x["cond"][icon] = x["cond"].get(icon, 0) + 1
    lines = []
    for d, x in sorted(days.items())[:2]:
        if not x["t"]:
            continue
        cond = max(x["cond"], key=x["cond"].get) if x["cond"] else "?"
        lines.append(f"{d}: {min(x['t']):.0f} bis {max(x['t']):.0f} °C, Niederschlag {x['rain']:.1f} mm, "
                     f"Sonne {x['sun']:.1f} h, Böen bis {x['gust']:.0f} km/h, überwiegend {cond}")
    return f"{name}: " + " | ".join(lines)


def weather_brief() -> str:
    d = datetime.now(ZoneInfo("Europe/Berlin"))
    day0 = d.strftime("%Y-%m-%d")
    day2 = (d + timedelta(days=2)).strftime("%Y-%m-%d")
    with ThreadPoolExecutor(6) as ex:
        rows = [r for r in ex.map(lambda c: _city_weather(c, day0, day2), CITIES) if r]
    try:
        alerts = httpx.get("https://api.brightsky.dev/alerts", timeout=20).json().get("alerts", [])
    except Exception:
        alerts = []
    sev = {}
    for a in alerts:
        if a.get("severity") in ("moderate", "severe", "extreme"):
            key = f"{a.get('event_de') or a.get('headline_de')} ({a.get('severity')})"
            sev[key] = sev.get(key, 0) + 1
    warn = "; ".join(f"{k}: {v} Warnbereiche" for k, v in sorted(sev.items(), key=lambda kv: -kv[1])[:8])
    return ("DWD-Vorhersagedaten (Quelle: Deutscher Wetterdienst):\n" + "\n".join(rows) +
            f"\n\nAktive amtliche Warnungen: {warn or 'keine nennenswerten'}")
