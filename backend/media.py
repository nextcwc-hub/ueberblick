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


# ------------------------------------------------------------------ Börse (nur frei weitergebbare Daten)
# EZB-Daten: frei nutzbar mit Quellenangabe. Krypto: CoinGecko (Hinweis „Powered by CoinGecko“ in der App).

ECB = "https://data-api.ecb.europa.eu/service/data/"
# Symbol, Name, Art, EZB-Reihe, Nachkommastellen, Einheit, Suchbegriffe
ECB_SERIES = [
    ("USD", "Euro / US-Dollar", "fx", "EXR/D.USD.EUR.SP00.A", 4, "", ["Dollar", "Wechselkurs", "Eurokurs", "Euro-Kurs", "Devisen"]),
    ("GBP", "Euro / Pfund", "fx", "EXR/D.GBP.EUR.SP00.A", 4, "", ["Pfund", "Sterling"]),
    ("CHF", "Euro / Franken", "fx", "EXR/D.CHF.EUR.SP00.A", 4, "", ["Franken"]),
    ("JPY", "Euro / Yen", "fx", "EXR/D.JPY.EUR.SP00.A", 2, "", ["Yen"]),
    ("CNY", "Euro / Yuan", "fx", "EXR/D.CNY.EUR.SP00.A", 4, "", ["Yuan", "Renminbi"]),
    ("PLN", "Euro / Złoty", "fx", "EXR/D.PLN.EUR.SP00.A", 4, "", ["Zloty", "Złoty"]),
    ("TRY", "Euro / Lira", "fx", "EXR/D.TRY.EUR.SP00.A", 4, "", ["Lira"]),
    ("DFR", "EZB-Einlagenzins", "rate", "FM/D.U2.EUR.4F.KR.DFR.LEV", 2, " %", ["Leitzins", "EZB", "Zinsentscheid", "Zinssenkung", "Zinserhöhung"]),
    ("ESTR", "€STR (Tagesgeld)", "rate", "EST/B.EU000A2X2A25.WT", 3, " %", ["€STR", "Tagesgeld"]),
    ("YC10", "Rendite 10 J. (Euroraum, AAA)", "rate", "YC/B.U2.EUR.4F.G_N_A.SV_C_YM.SR_10Y", 2, " %", ["Anleihe", "Rendite", "Staatsanleihe"]),
    ("DE10Y", "Rendite Bundesanleihe 10 J.", "rate", "IRS/M.DE.L.L40.CI.0000.EUR.N.Z", 2, " %", ["Bundesanleihe", "Bund-Rendite"]),
    ("HICP_DE", "Inflation Deutschland", "inflation", "eurostat:DE", 1, " %", ["Inflation", "Teuerung", "Verbraucherpreise"]),
    ("HICP_EA", "Inflation Euroraum", "inflation", "eurostat:EA20", 1, " %", ["Inflation", "Teuerung"]),
]
CRYPTO = [("BTC", "bitcoin", "Bitcoin", ["Bitcoin", "Krypto"]), ("ETH", "ethereum", "Ethereum", ["Ethereum", "Ether", "Krypto"])]

H = {"User-Agent": "UeberblickNews/1.0 (https://github.com/nextcwc-hub/ueberblick)"}
HIST_EVERY = 3 * 3600


def safe(sym: str) -> str:
    return re.sub(r"[^A-Za-z0-9-]", "_", sym)


def _thin(pts, n):
    if len(pts) <= n:
        return pts
    step = len(pts) / n
    out = [pts[int(i * step)] for i in range(n)]
    out[-1] = pts[-1]
    return out


def _ecb(series: str, n: int):
    r = httpx.get(ECB + series, params={"format": "jsondata", "lastNObservations": n}, headers=H, timeout=30)
    j = r.json()
    obs = list(j["dataSets"][0]["series"].values())[0]["observations"]
    dims = j["structure"]["dimensions"]["observation"][0]["values"]
    out = []
    for i, o in sorted(obs.items(), key=lambda kv: int(kv[0])):
        if o[0] is None:
            continue
        d = dims[int(i)]["id"]  # 2026-10-16 oder 2026-09
        fmt = "%Y-%m-%d" if len(d) == 10 else "%Y-%m"
        t = int(datetime.strptime(d, fmt).replace(hour=16 if len(d) == 10 else 0, tzinfo=ZoneInfo("Europe/Berlin")).timestamp())
        out.append([t, round(float(o[0]), 5)])
    return out


def _eurostat(geo: str):
    """HICP-Jahresrate (Eurostat, frei nutzbar mit Quellenangabe)."""
    r = httpx.get("https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/prc_hicp_minr", headers=H,
                  timeout=40, params={"geo": geo, "coicop18": "TOTAL", "unit": "RCH_A", "lastTimePeriod": 130})
    j = r.json()
    out = []
    for d, i in sorted(j["dimension"]["time"]["category"]["index"].items(), key=lambda kv: kv[1]):
        v = j["value"].get(str(i))
        if v is not None:
            t = int(datetime.strptime(d, "%Y-%m").replace(tzinfo=ZoneInfo("Europe/Berlin")).timestamp())
            out.append([t, float(v)])
    return out


def _cg(path: str, params: dict):
    for attempt in range(3):
        r = httpx.get("https://api.coingecko.com/api/v3/" + path, headers=H, timeout=20, params=params)
        if r.status_code == 429:
            time.sleep(15)
            continue
        return r.json()
    return {}


def _item(sym, name, kind, digits, unit, alias, hist, intraday=None, week=None, pct=None, pp=False, freq="D"):
    price = hist[-1][1] if not intraday else intraday[-1][1]
    prev = hist[-2][1] if len(hist) > 1 else price
    last_year = [p[1] for p in hist if p[0] >= hist[-1][0] - 366 * 86400]
    return {
        "sym": sym, "name": name, "kind": kind, "digits": digits, "unit": unit, "alias": alias, "freq": freq,
        "price": price, "prev": prev,
        "pct": pct if pct is not None else (round(price - prev, 3) if pp else round((price - prev) / prev * 100, 2)),
        "pp": pp,
        "yhigh": max(last_year) if last_year else None, "ylow": min(last_year) if last_year else None,
        "time": (intraday or hist)[-1][0],
        "spark": [p[1] for p in _thin(intraday or hist[-60:], 48)],
    }


def markets(out_dir, prev: dict) -> dict:
    """Schreibt Detaildateien nach out_dir/<sym>.json und gibt die Übersicht zurück."""
    now = time.time()
    items, details = [], {}
    hist_fresh = False

    def ecb_one(e):
        sym, name, kind, series, digits, unit, alias = e
        try:
            monthly = series.startswith(("eurostat", "IRS"))
            hist = _eurostat(series.split(":")[1]) if series.startswith("eurostat") else _ecb(series, 130 if monthly else 400)
            if len(hist) < 2:
                return None
            it = _item(sym, name, kind, digits, unit, alias, hist, pp=kind != "fx", freq="M" if monthly else "D")
            return it, {"intraday": [], "week": [], "history": hist}
        except Exception as ex:
            print(f"  EZB fail {sym}: {ex}")
            return None

    with ThreadPoolExecutor(6) as ex:
        for res in ex.map(ecb_one, ECB_SERIES):
            if res:
                items.append(res[0])
                details[res[0]["sym"]] = res[1]

    try:
        cg = _cg("coins/markets", {"vs_currency": "eur", "ids": ",".join(c[1] for c in CRYPTO), "sparkline": "true"})
        cg = {x["id"]: x for x in cg} if isinstance(cg, list) else {}
        for sym, cid, name, alias in CRYPTO:
            x = cg.get(cid)
            if not x:
                continue
            hp = out_dir / f"{safe(sym)}.json"
            history = []
            if now - prev.get("hist_at", 0) < HIST_EVERY and hp.exists():  # Jahresverlauf nur alle 3 Std. neu laden
                history = json.loads(hp.read_text(encoding="utf-8")).get("history", [])
            if len(history) < 2:
                hist = _cg(f"coins/{cid}/market_chart", {"vs_currency": "eur", "days": "365", "interval": "daily"})
                history = [[int(t / 1000), round(v, 2)] for t, v in hist.get("prices", [])]
                hist_fresh = True
            spark7 = x.get("sparkline_in_7d", {}).get("price") or []
            week = [[int(now - (len(spark7) - i) * 3600), round(v, 2)] for i, v in enumerate(spark7)]
            intraday = week[-25:]
            if len(history) < 2 or not intraday:
                continue
            it = _item(sym, name, "crypto", 0 if x["current_price"] > 1000 else 2, " €", alias, history,
                       intraday=intraday, pct=round(x.get("price_change_percentage_24h") or 0, 2))
            it["price"] = x["current_price"]
            it["prev"] = round(x["current_price"] / (1 + (x.get("price_change_percentage_24h") or 0) / 100), 2)
            it["high"], it["low"] = x.get("high_24h"), x.get("low_24h")
            items.append(it)
            details[sym] = {"intraday": intraday, "week": week, "history": history}
    except Exception as ex:
        print(f"  CoinGecko fail: {ex}")

    all_syms = [e[0] for e in ECB_SERIES] + [c[0] for c in CRYPTO]
    for sym, d in details.items():
        p = out_dir / f"{safe(sym)}.json"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps({"sym": sym, **d}, separators=(",", ":")), encoding="utf-8")
    if out_dir.exists():
        for p in out_dir.glob("*.json"):
            if p.stem not in {safe(s) for s in all_syms}:
                p.unlink()
    hist_at = int(now) if hist_fresh or now - prev.get("hist_at", 0) >= HIST_EVERY else prev.get("hist_at", 0)
    return {"updated": int(now), "hist_at": hist_at, "items": items}


def markets_brief(m: dict) -> str:
    return "Aktuelle Daten (EZB/Eurostat): " + "; ".join(
        f"{x['name']} {x['price']}{x['unit']}" for x in m.get("items", []) if x["kind"] in ("rate", "inflation"))


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
