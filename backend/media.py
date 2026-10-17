"""Bilder (Wikimedia Commons, nur kommerziell nutzbare Lizenzen), Börsen- und Wetterdaten."""
import json
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


_GENERIC = {"building", "buildings", "city", "photo", "view", "germany", "german", "street", "people", "the",
            "and", "with", "from", "image", "picture", "symbol", "logo", "general", "exterior", "interior"}


def _matches(query: str, text: str) -> bool:
    toks = [t for t in re.findall(r"[a-zäöüß0-9]+", query.lower()) if len(t) >= 4 and t not in _GENERIC]
    text = text.lower()
    # bei mehreren Suchbegriffen müssen mindestens zwei im Bildtitel/der Beschreibung vorkommen
    return not toks or sum(t[:6] in text for t in toks) >= min(2, len(toks))


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
        desc = clean(em.get("ImageDescription", {}).get("value", ""))
        if not _matches(query, p["title"] + " " + desc):
            continue  # Bild hat erkennbar nichts mit dem Suchbegriff zu tun
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

# Symbol, Name, Art, Suchbegriffe für passende Nachrichten
INSTRUMENTS = [
    ("^GDAXI", "DAX", "index", ["DAX"]),
    ("^MDAXI", "MDAX", "index", ["MDAX"]),
    ("^TECDAX", "TecDAX", "index", ["TecDAX"]),
    ("^SDAXI", "SDAX", "index", ["SDAX"]),
    ("^STOXX50E", "Euro Stoxx 50", "index", ["Euro Stoxx", "EuroStoxx"]),
    ("^FTSE", "FTSE 100", "index", ["FTSE", "Londoner Börse"]),
    ("^FCHI", "CAC 40", "index", ["CAC"]),
    ("^DJI", "Dow Jones", "index", ["Dow Jones", "Dow"]),
    ("^GSPC", "S&P 500", "index", ["S&P 500", "S&P"]),
    ("^NDX", "Nasdaq 100", "index", ["Nasdaq"]),
    ("^N225", "Nikkei 225", "index", ["Nikkei"]),
    ("^HSI", "Hang Seng", "index", ["Hang Seng", "Hongkonger Börse"]),
    ("EURUSD=X", "Euro / Dollar", "fx", ["Wechselkurs", "Eurokurs", "Euro-Kurs", "Dollarkurs", "Dollar-Kurs", "Devisen"]),
    ("EURGBP=X", "Euro / Pfund", "fx", ["Pfund", "Sterling"]),
    ("EURCHF=X", "Euro / Franken", "fx", ["Franken"]),
    ("EURJPY=X", "Euro / Yen", "fx", ["Yen"]),
    ("GC=F", "Gold", "commodity", ["Gold", "Goldpreis"]),
    ("SI=F", "Silber", "commodity", ["Silber"]),
    ("BZ=F", "Öl (Brent)", "commodity", ["Öl", "Ölpreis", "Brent", "Opec", "Rohöl"]),
    ("NG=F", "Erdgas (US)", "commodity", ["Erdgas", "Gaspreis", "LNG"]),
    ("^TNX", "US-Anleihen 10 J.", "bond", ["Anleihe", "Rendite", "Treasur", "Fed", "Zins"]),
    ("BTC-EUR", "Bitcoin", "crypto", ["Bitcoin", "Krypto"]),
    ("ETH-EUR", "Ethereum", "crypto", ["Ethereum", "Ether", "Krypto"]),
]

STOCKS = [
    ("ADS.DE", "Adidas"), ("AIR.DE", "Airbus"), ("ALV.DE", "Allianz"), ("BAS.DE", "BASF"),
    ("BAYN.DE", "Bayer"), ("BEI.DE", "Beiersdorf"), ("BMW.DE", "BMW"), ("BNR.DE", "Brenntag"),
    ("CBK.DE", "Commerzbank"), ("CON.DE", "Continental"), ("DTG.DE", "Daimler Truck"),
    ("DBK.DE", "Deutsche Bank"), ("DB1.DE", "Deutsche Börse"), ("DHL.DE", "DHL Group"),
    ("DTE.DE", "Deutsche Telekom"), ("EOAN.DE", "E.ON"), ("FRE.DE", "Fresenius"),
    ("FME.DE", "Fresenius Medical Care"), ("G1A.DE", "GEA"), ("HNR1.DE", "Hannover Rück"),
    ("HEI.DE", "Heidelberg Materials"), ("HEN3.DE", "Henkel"), ("IFX.DE", "Infineon"),
    ("MBG.DE", "Mercedes-Benz"), ("MRK.DE", "Merck"), ("MTX.DE", "MTU Aero Engines"),
    ("MUV2.DE", "Munich Re"), ("P911.DE", "Porsche"), ("PAH3.DE", "Porsche SE"),
    ("QIA.DE", "Qiagen"), ("RHM.DE", "Rheinmetall"), ("RWE.DE", "RWE"), ("SAP.DE", "SAP"),
    ("SRT3.DE", "Sartorius"), ("SIE.DE", "Siemens"), ("ENR.DE", "Siemens Energy"),
    ("SHL.DE", "Siemens Healthineers"), ("SY1.DE", "Symrise"), ("VOW3.DE", "Volkswagen"),
    ("VNA.DE", "Vonovia"), ("ZAL.DE", "Zalando"),
]
_ALIAS_EXTRA = {"VOW3.DE": ["VW"], "MBG.DE": ["Mercedes"], "DTE.DE": ["Telekom"],
                "MUV2.DE": ["Münchener Rück"], "DHL.DE": ["DHL"]}

H = {"User-Agent": "Mozilla/5.0"}
HIST_EVERY = 3 * 3600


def safe(sym: str) -> str:
    return re.sub(r"[^A-Za-z0-9-]", "_", sym)  # ohne Punkte – "CON.DE" wäre unter Windows ein reservierter Name


def _pts(res):
    ts = res.get("timestamp") or []
    cl = (res.get("indicators", {}).get("quote") or [{}])[0].get("close") or []
    pts = [[t, round(c, 4)] for t, c in zip(ts, cl) if c is not None]
    # einzelne Fehlticks (Ausreißer gegenüber beiden Nachbarn) entfernen
    return [p for i, p in enumerate(pts)
            if not (0 < i < len(pts) - 1 and _spike(pts[i - 1][1], p[1], pts[i + 1][1]))]


def _spike(a, b, c):
    if not a or not c:
        return False
    return abs(b - a) / a > 0.008 and abs(b - c) / c > 0.008 and abs(a - c) / c < 0.003


def _chart(sym: str, rng: str, interval: str):
    r = httpx.get(f"https://query1.finance.yahoo.com/v8/finance/chart/{sym}",
                  params={"range": rng, "interval": interval}, headers=H, timeout=15)
    res = r.json()["chart"]["result"][0]
    return res["meta"], _pts(res)


def _spark(syms: list[str], rng: str, interval: str) -> dict:
    out = {}
    for i in range(0, len(syms), 20):
        try:
            r = httpx.get("https://query1.finance.yahoo.com/v7/finance/spark", headers=H, timeout=20,
                          params={"symbols": ",".join(syms[i:i + 20]), "range": rng, "interval": interval})
            for x in r.json()["spark"]["result"]:
                resp = (x.get("response") or [None])[0]
                if resp:
                    out[x["symbol"]] = (resp.get("meta", {}), _pts(resp))
        except Exception as ex:
            print(f"  spark fail: {ex}")
    return out


def _thin(pts, n):
    if len(pts) <= n:
        return pts
    step = len(pts) / n
    out = [pts[int(i * step)] for i in range(n)]
    out[-1] = pts[-1]
    return out


def _summary(sym, name, kind, alias, meta, intraday):
    price = meta.get("regularMarketPrice") or (intraday[-1][1] if intraday else None)
    prev = meta.get("chartPreviousClose") or meta.get("previousClose")
    if price is None or not prev:
        return None
    vals = [p[1] for p in intraday]
    return {
        "sym": sym, "name": name, "kind": kind, "cur": meta.get("currency", ""), "alias": alias,
        "price": price, "prev": prev, "pct": round((price - prev) / prev * 100, 2),
        "open": vals[0] if vals else None,
        "high": meta.get("regularMarketDayHigh") or (max(vals) if vals else None),
        "low": meta.get("regularMarketDayLow") or (min(vals) if vals else None),
        "yhigh": meta.get("fiftyTwoWeekHigh"), "ylow": meta.get("fiftyTwoWeekLow"),
        "time": meta.get("regularMarketTime"),
        "spark": [p[1] for p in _thin(intraday, 48)],
    }


def markets(out_dir, prev: dict) -> dict:
    """Schreibt Detaildateien nach out_dir/<sym>.json und gibt die Übersicht zurück."""
    now = time.time()
    all_syms = [i[0] for i in INSTRUMENTS] + [s for s, _ in STOCKS]
    need_hist = (now - prev.get("hist_at", 0) > HIST_EVERY
                 or any(not (out_dir / f"{safe(s)}.json").exists() for s in all_syms))
    items, details = [], {}

    def main_inst(entry):
        sym, name, kind, alias = entry
        try:
            meta, intraday = _chart(sym, "1d", "5m")
            d = {"intraday": intraday}
            if need_hist:
                d["week"] = _chart(sym, "5d", "30m")[1]
                d["history"] = _chart(sym, "1y", "1d")[1]
            return _summary(sym, name, kind, alias, meta, intraday), d
        except Exception as ex:
            print(f"  market fail {sym}: {ex}")
            return None, None

    with ThreadPoolExecutor(6) as ex:
        for entry, (s, d) in zip(INSTRUMENTS, ex.map(main_inst, INSTRUMENTS)):
            if s:
                items.append(s)
                details[entry[0]] = d

    syms = [s for s, _ in STOCKS]
    intr = _spark(syms, "1d", "5m")
    week = _spark(syms, "5d", "30m") if need_hist else {}
    hist = _spark(syms, "1y", "1d") if need_hist else {}
    for sym, name in STOCKS:
        if sym not in intr:
            continue
        meta, intraday = intr[sym]
        s = _summary(sym, name, "stock", [name] + _ALIAS_EXTRA.get(sym, []), meta, intraday)
        if s:
            items.append(s)
            d = {"intraday": intraday}
            if need_hist:
                d["week"] = week.get(sym, (None, []))[1]
                d["history"] = hist.get(sym, (None, []))[1]
            details[sym] = d

    for sym, d in details.items():
        p = out_dir / f"{safe(sym)}.json"
        if not need_hist:  # Wochen- und Jahresdaten aus dem letzten Abruf übernehmen
            try:
                old = json.loads(p.read_text(encoding="utf-8"))
                d["week"], d["history"] = old.get("week", []), old.get("history", [])
            except Exception:
                d["week"], d["history"] = [], []
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps({"sym": sym, **d}, separators=(",", ":")), encoding="utf-8")
    keep = {f"{safe(s)}.json" for s in details}
    for p in out_dir.glob("*.json"):
        if p.name not in keep and not any(p.name == f"{safe(s)}.json" for s in all_syms):
            p.unlink()
    return {"updated": int(now), "hist_at": int(now) if need_hist else prev.get("hist_at", 0), "items": items}


def markets_brief(m: dict) -> str:
    return "Aktuelle Marktdaten: " + "; ".join(
        f"{x['name']} {x['price']:.2f} ({x['pct']:+.2f} %)" for x in m.get("items", []) if x["kind"] != "stock")


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
