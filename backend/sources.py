"""Nachrichtenquellen (nur als Faktengrundlage – Texte werden nie übernommen)."""
import calendar
import hashlib
import html
import re
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from email.utils import parsedate_to_datetime
from urllib.parse import urlparse
from urllib.robotparser import RobotFileParser

import feedparser
import httpx

UA = "UeberblickNews/1.0 (https://github.com/nextcwc-hub/ueberblick)"

# name, url, Kategorie-Hinweis, frei lesbar (für Volltext-Abruf bevorzugt)
FEEDS = [
    ("tagesschau", "https://www.tagesschau.de/index~rss2.xml", None, True),
    ("tagesschau", "https://www.tagesschau.de/inland/index~rss2.xml", "inland", True),
    ("tagesschau", "https://www.tagesschau.de/ausland/index~rss2.xml", "ausland", True),
    ("tagesschau", "https://www.tagesschau.de/wirtschaft/index~rss2.xml", "wirtschaft", True),
    ("tagesschau", "https://www.tagesschau.de/wirtschaft/finanzen/index~rss2.xml", "boerse", True),
    ("tagesschau", "https://www.tagesschau.de/wissen/index~rss2.xml", "wissen", True),
    ("tagesschau", "https://www.tagesschau.de/investigativ/index~rss2.xml", "investigativ", True),
    ("ZDFheute", "https://www.zdfheute.de/rss/zdf/nachrichten", None, True),
    ("Deutschlandfunk", "https://www.deutschlandfunk.de/nachrichten-100.rss", None, True),
    ("DW", "https://rss.dw.com/xml/rss-de-all", None, True),
    ("MDR", "https://www.mdr.de/nachrichten/index-rss.xml", "inland", True),
    ("Bundesregierung", "https://www.bundesregierung.de/service/rss/breg-de/1151242/feed.xml", "inland", True),
    ("Spiegel", "https://www.spiegel.de/schlagzeilen/index.rss", None, False),
    ("Zeit", "https://newsfeed.zeit.de/index", None, False),
    ("FAZ", "https://www.faz.net/rss/aktuell/", None, False),
    ("SZ", "https://rss.sueddeutsche.de/rss/Topthemen", None, False),
    ("n-tv", "https://www.n-tv.de/rss", None, True),
    ("n-tv", "https://www.n-tv.de/wirtschaft/rss", "wirtschaft", True),
    ("Welt", "https://www.welt.de/feeds/latest.rss", None, False),
    ("Tagesspiegel", "https://www.tagesspiegel.de/contentexport/feed/home", None, False),
    ("Handelsblatt", "https://www.handelsblatt.com/contentexport/feed/schlagzeilen", "wirtschaft", False),
    ("Handelsblatt", "https://www.handelsblatt.com/contentexport/feed/finanzen", "boerse", False),
    ("WirtschaftsWoche", "https://www.wiwo.de/contentexport/feed/rss/schlagzeilen", "wirtschaft", False),
    ("Sportschau", "https://www.sportschau.de/index~rss2.xml", "sport", True),
    ("kicker", "https://newsfeed.kicker.de/news/aktuell", "sport", True),
    ("Spektrum", "https://www.spektrum.de/alias/rss/spektrum-de-rss-feed/996406", "wissen", True),
    ("scinexx", "https://www.scinexx.de/feed/", "wissen", True),
    ("heise", "https://www.heise.de/rss/heise-atom.xml", "digital", True),
    ("netzpolitik.org", "https://netzpolitik.org/feed/", "digital", True),
    ("Correctiv", "https://correctiv.org/feed/", "investigativ", True),
    ("Deutschlandfunk", "https://www.deutschlandfunk.de/wirtschaft-106.rss", "wirtschaft", True),
    ("ZDFheute", "https://www.zdfheute.de/rss/zdf/politik", None, True),
    ("ZDF", "https://www.zdf.de/rss/zdf/sport", "sport", True),
    ("ZDF", "https://www.zdfheute.de/rss/zdf/wissen", "wissen", True),
    ("Bundestag", "https://www.bundestag.de/static/appdata/includes/rss/hib.rss", "inland", True),
    ("Destatis", "https://www.destatis.de/SiteGlobals/Functions/RSSFeed/DE/RSSNewsfeed/Aktuell.xml", "wirtschaft", True),
    ("Bundesbank", "https://www.bundesbank.de/service/rss/de/633286/feed.rss", "wirtschaft", True),
    ("EZB", "https://www.ecb.europa.eu/rss/press.html", "wirtschaft", True),
    ("EU-Kommission", "https://ec.europa.eu/commission/presscorner/api/rss?language=de", "ausland", True),
    ("UN News", "https://news.un.org/feed/subscribe/en/news/all/rss.xml", "ausland", True),
    ("BBC", "https://feeds.bbci.co.uk/news/world/rss.xml", "ausland", True),
    ("The Guardian", "https://www.theguardian.com/world/rss", "ausland", True),
    ("Al Jazeera", "https://www.aljazeera.com/xml/rss/all.xml", "ausland", True),
    ("New York Times", "https://rss.nytimes.com/services/xml/rss/nyt/World.xml", "ausland", False),
    ("France 24", "https://www.france24.com/en/rss", "ausland", True),
    ("NPR", "https://feeds.npr.org/1004/rss.xml", "ausland", True),
]

OPEN_SOURCES = {name for name, _, _, free in FEEDS if free}

_tag = re.compile(r"<[^>]+>")
_ws = re.compile(r"\s+")


def clean(s: str) -> str:
    return _ws.sub(" ", html.unescape(_tag.sub(" ", s or ""))).strip()


def url_hash(u: str) -> str:
    u = u.split("?")[0].split("#")[0].rstrip("/")
    return hashlib.sha1(u.encode()).hexdigest()[:16]


def _ts(e) -> float:
    for key in ("published_parsed", "updated_parsed"):
        t = e.get(key)
        if t:
            return float(calendar.timegm(t))
    for key in ("published", "updated"):
        if e.get(key):
            try:
                return parsedate_to_datetime(e[key]).timestamp()
            except Exception:
                pass
    return time.time()


def _fetch(feed):
    name, url, hint, _ = feed
    try:
        r = httpx.get(url, timeout=20, follow_redirects=True, headers={"User-Agent": UA})
        d = feedparser.parse(r.content)
    except Exception as ex:
        print(f"  feed fail {name}: {ex}")
        return []
    out = []
    for e in d.entries:
        link = e.get("link")
        title = clean(e.get("title", ""))
        if not link or not title:
            continue
        out.append({
            "h": url_hash(link), "u": link, "s": name, "t": title[:220],
            "d": clean(e.get("summary", ""))[:400], "p": _ts(e), "hint": hint,
        })
    return out


def fetch_all(max_age_h: float) -> list[dict]:
    with ThreadPoolExecutor(16) as ex:
        results = list(ex.map(_fetch, FEEDS))
    now = time.time()
    items, seen = [], set()
    for lst in results:
        for it in lst:
            if it["h"] in seen or now - it["p"] > max_age_h * 3600:
                continue
            seen.add(it["h"])
            items.append(it)
    items.sort(key=lambda x: -x["p"])
    # Anreißer nur von Anbietern ohne Text-Mining-Vorbehalt verwenden, sonst nur die Schlagzeile
    hosts = {}
    for it in items:
        hosts.setdefault(urlparse(it["u"]).netloc, it["u"])
    with ThreadPoolExecutor(12) as ex:
        allowed = dict(zip(hosts, ex.map(tdm_allowed, hosts.values())))
    for it in items:
        it["ok"] = allowed.get(urlparse(it["u"]).netloc, False)
        if not it["ok"]:
            it["d"] = ""
    return items


# ---------------------------------------------------------------- Text-Mining-Vorbehalt (§ 44b UrhG)
# Volltexte werden nur gelesen, wenn der Anbieter Text- und Data-Mining nicht maschinenlesbar
# untersagt hat: robots.txt (für uns und gängige KI-Crawler), TDMRep (/.well-known/tdmrep.json),
# HTTP-Header bzw. Meta-Tag "tdm-reservation". Im Zweifel wird nur der RSS-Anreißer genutzt.

AI_AGENTS = ["UeberblickNews", "GPTBot", "ClaudeBot", "anthropic-ai", "CCBot", "Google-Extended",
             "PerplexityBot", "Bytespider", "cohere-ai", "Applebot-Extended", "meta-externalagent"]
_policy: dict[str, tuple] = {}
_policy_lock = threading.Lock()


def _host_policy(base: str):
    with _policy_lock:
        if base in _policy:
            return _policy[base]
    rp, tdm = None, []
    try:
        r = httpx.get(base + "/robots.txt", timeout=10, follow_redirects=True, headers={"User-Agent": UA})
        if r.status_code < 400:
            rp = RobotFileParser()
            rp.parse(r.text.splitlines())
        elif r.status_code >= 500:
            rp = False  # unklar -> nicht verwenden
    except Exception:
        rp = False
    try:
        r = httpx.get(base + "/.well-known/tdmrep.json", timeout=10, follow_redirects=True, headers={"User-Agent": UA})
        if r.status_code == 200:
            tdm = [x for x in r.json() if str(x.get("tdm-reservation")) == "1"]
    except Exception:
        pass
    with _policy_lock:
        _policy[base] = (rp, tdm)
    return rp, tdm


def tdm_allowed(url: str) -> bool:
    u = urlparse(url)
    rp, tdm = _host_policy(f"{u.scheme}://{u.netloc}")
    if rp is False:
        return False
    if rp is not None and not all(rp.can_fetch(a, url) for a in AI_AGENTS):
        return False
    for rule in tdm:
        loc = str(rule.get("location", "/")).rstrip("*")
        if u.path.startswith(loc or "/"):
            return False
    return True


_meta_tdm = re.compile(r"""<meta[^>]+name=["']tdm-reservation["'][^>]+content=["']1""", re.I)


def fetch_text(url: str, limit: int = 5000) -> str:
    """Volltext eines Artikels als Faktengrundlage (wird nicht veröffentlicht) – nur ohne TDM-Vorbehalt."""
    import trafilatura
    try:
        if not tdm_allowed(url):
            return ""
        r = httpx.get(url, timeout=15, follow_redirects=True, headers={"User-Agent": UA})
        if r.headers.get("tdm-reservation", "").strip() == "1" or _meta_tdm.search(r.text[:20000]):
            return ""
        txt = trafilatura.extract(r.text, include_comments=False, include_tables=False) or ""
        return txt[:limit]
    except Exception:
        return ""
