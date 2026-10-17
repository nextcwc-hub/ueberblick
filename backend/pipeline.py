"""Ein Durchlauf: Quellen holen → bündeln → neue/aktualisierte Artikel schreiben → JSON veröffentlichen.

Aufruf: python pipeline.py <ausgabe-ordner>
"""
import hashlib
import json
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import llm
import media
import sources

TZ = ZoneInfo("Europe/Berlin")
FREE = llm.PROVIDER == "gemini"
MAX_PER_RUN = int(os.environ.get("MAX_WRITES_PER_RUN") or (5 if FREE else 8))
MAX_FIRST_RUN = 12 if FREE else 24
MAX_PER_DAY = int(os.environ.get("MAX_WRITES_PER_DAY") or (200 if FREE else 150))
WEATHER_EVERY_H = 3
KEEP_H = 72
ARCHIVE_DAYS = 30
WEEKDAYS = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]


def load(p: Path, default):
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return default


def save(p: Path, data):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")


def now_str() -> str:
    d = datetime.now(TZ)
    return f"{WEEKDAYS[d.weekday()]}, {d:%d.%m.%Y, %H:%M} Uhr ({d.tzname()})"


def distinct_sources(ev) -> list[str]:
    return list(dict.fromkeys(i["s"] for i in ev["items"]))


def main(out: Path):
    v1 = out / "v1"
    state = load(out / "state.json", {"seen": {}, "events": {}, "writes": {}, "weather_at": 0})
    index = load(v1 / "index.json", {"stories": []})
    stories = {s["id"]: s for s in index["stories"]}
    events = state["events"]
    now = time.time()
    today = datetime.now(TZ).strftime("%Y-%m-%d")
    has_key = llm.has_key()

    # ---- Börse (jeder Lauf, ohne KI)
    m = media.markets(v1 / "m", load(v1 / "markets.json", {}))
    if m["items"]:
        save(v1 / "markets.json", m)
    print(f"Märkte: {len(m['items'])}")

    if not has_key:
        print("Kein API-Key – nur Marktdaten aktualisiert.")
        finish(out, v1, state, stories, now)
        return

    # ---- Meldungen holen
    first_run = not events
    items = sources.fetch_all(10 if first_run else 24)
    fresh = {x["h"]: x for x in items if x["h"] not in state["seen"]}
    new = list(fresh.values())[:400]
    print(f"Meldungen: {len(items)} gesamt, {len(new)} neu")

    # ---- Bündeln
    def label(e):
        return stories[e["id"]]["title"] if e["id"] in stories else e["label"]

    active = sorted((e for e in events.values() if now - e["last_item"] < 36 * 3600),
                    key=lambda e: -e["last_item"])[:300]
    existing = [{"id": e["id"], "cat": e["cat"], "label": label(e)} for e in active]

    for start in range(0, len(new), 200):
        chunk = new[start:start + 200]
        res = llm.cluster(existing, chunk, now_str())
        if not res:
            continue  # Meldungen bleiben ungesehen → nächster Lauf
        keymap = {}
        for ne in res["new_events"]:
            eid = "e" + hashlib.sha1(f"{ne['key']}{ne['label']}{now}".encode()).hexdigest()[:10]
            ev = {"id": eid, "cat": ne["cat"], "imp": max(1, min(10, ne["imp"])), "label": ne["label"],
                  "iq": ne["image_query"], "tone": ne.get("tone", "neutral"), "items": [], "created": now, "last_item": now,
                  "written": False, "written_n": 0, "last_write": 0}
            keymap[ne["key"]] = ev
        for a in res["items"]:
            if not 0 <= a["i"] < len(chunk):
                continue
            it = chunk[a["i"]]
            state["seen"][it["h"]] = now
            if a["drop"]:
                continue
            ev = events.get(a["event"]) or keymap.get(a["event"])
            if not ev:
                continue
            if not any(x["h"] == it["h"] for x in ev["items"]):
                ev["items"].append({k: it[k] for k in ("h", "u", "s", "t", "p")})
                ev["last_item"] = max(ev["last_item"], now)
        for ev in keymap.values():
            if ev["items"]:
                events[ev["id"]] = ev
                existing.insert(0, {"id": ev["id"], "cat": ev["cat"], "label": ev["label"]})
        for r in res["reassess"]:
            if r["id"] in events:
                events[r["id"]]["imp"] = max(1, min(10, r["imp"]))
        print(f"  Block {start // 200 + 1}: {len(keymap)} neue Ereignisse")

    # ---- Auswahl: was wird (neu) geschrieben?
    cands = []
    for ev in events.values():
        n_src = len(distinct_sources(ev))
        if not ev["written"]:
            ok = ev["imp"] >= 6 or (ev["imp"] >= 4 and (n_src >= 2 or ev.get("tone") == "positiv")) or n_src >= 3
            if ok and now - ev["last_item"] < 12 * 3600:
                cands.append((ev["imp"] * 10 + 5 * min(n_src, 6) + 15, ev))
        else:
            added = len(ev["items"]) - ev["written_n"]
            if added > 0 and now - ev["last_write"] > 40 * 60 and (added >= 2 or ev["imp"] >= 7):
                cands.append((ev["imp"] * 10 + 5 * min(added, 6), ev))
    cands.sort(key=lambda c: -c[0])
    budget = min(MAX_FIRST_RUN if first_run else MAX_PER_RUN, MAX_PER_DAY - state["writes"].get(today, 0))
    todo = [ev for _, ev in cands[:max(0, budget)]]
    print(f"Schreibe {len(todo)} Artikel ({len(cands)} Kandidaten)")

    mbrief = media.markets_brief(m) if m["items"] else ""
    codes = {x["sym"] for x in m["items"]}
    alist = "MARKTWERTE für assets (Kürzel = Name): " + ", ".join(f"{x['sym']} = {x['name']}" for x in m["items"])

    def job(ev):
        its = sorted(ev["items"], key=lambda i: (i["s"] not in sources.OPEN_SOURCES, -i["p"]))[:8]
        reports, fetched = [], 0
        for i in its:
            r = {"s": i["s"], "t": i["t"], "d": fresh.get(i["h"], {}).get("d", "")}
            if fetched < 3:
                r["full"] = sources.fetch_text(i["u"])
                fetched += 1 if r["full"] else 0
            reports.append(r)
        prev = stories.get(ev["id"])
        imgs = [] if prev and prev.get("img") else media.commons_candidates(ev.get("iq", ""))
        extra = mbrief if ev["cat"] in ("boerse", "wirtschaft") else ""
        if m["items"] and ev["cat"] in ("boerse", "wirtschaft", "digital", "ausland", "inland"):
            extra += "\n\n" + alist
        return ev, llm.write(ev, reports, prev, imgs, extra, now_str()), imgs

    with ThreadPoolExecutor(1 if FREE else 4) as ex:
        results = list(ex.map(job, todo))

    for ev, res, imgs in results:
        if not res:
            continue
        res["assets"] = [a for a in res.get("assets", []) if a in codes][:6]
        publish(v1, stories, ev, res, imgs, now)
        ev.update(written=True, written_n=len(ev["items"]), last_write=now,
                  cat=res["cat"], imp=max(1, min(10, res["imp"])))
        state["writes"][today] = state["writes"].get(today, 0) + 1

    # ---- Wetterbericht Deutschland
    if now - state.get("weather_at", 0) > WEATHER_EVERY_H * 3600:
        brief = media.weather_brief()
        ev = {"id": "wetter", "cat": "wetter", "imp": 5, "label": "Das Wetter in Deutschland",
              "items": [{"h": "dwd", "u": "https://www.dwd.de", "s": "Deutscher Wetterdienst", "t": "", "p": now}]}
        extra = ("Schreibe den Wetterbericht für Deutschland für heute und morgen: Gesamtlage, dann Regionen "
                 "(Norden, Westen, Osten, Süden), amtliche Warnungen, Aussichten. Die Überschrift beschreibt die "
                 "Wetterlage konkret. Kategorie wetter, keine positions.")
        res = llm.write(ev, [{"s": "Deutscher Wetterdienst", "t": "Vorhersage", "full": brief}],
                        None, [], extra, now_str())
        if res:
            res["cat"] = "wetter"
            publish(v1, stories, ev, res, [], now)
            state["weather_at"] = now

    finish(out, v1, state, stories, now)


def publish(v1: Path, stories: dict, ev: dict, res: dict, imgs: list, now: float):
    prev = stories.get(ev["id"], {})
    img = prev.get("img")
    if 0 <= res["image"] < len(imgs):
        img = imgs[res["image"]]["img"]
    srcs, seen = [], set()
    for i in sorted(ev["items"], key=lambda i: -i["p"]):
        if i["s"] not in seen:
            seen.add(i["s"])
            srcs.append({"n": i["s"], "u": i["u"]})
    stories[ev["id"]] = {
        "id": ev["id"], "cat": res["cat"], "title": res["title"].strip(), "teaser": res["teaser"].strip(),
        "summary": [s.strip() for s in res["summary"] if s.strip()][:5], "img": img,
        "created": prev.get("created", int(now)), "updated": int(now),
        "imp": max(1, min(10, res["imp"])), "srcn": len(srcs), "sources": srcs[:12],
        "loc": res["location"].strip(), "ver": prev.get("ver", 0) + 1,
        "tone": res.get("tone", "neutral"),
        "assets": res.get("assets", []),
    }
    save(v1 / "a" / f"{ev['id']}.json", {
        "id": ev["id"], "sections": res["sections"], "facts": res["facts"],
        "positions": res["positions"], "outlook": res["outlook"].strip(),
    })


def archive(v1: Path, stories: dict, now: float):
    """Tagesarchiv für den Zeitstrahl: v1/days/<datum>.json + v1/days.json"""
    days = v1 / "days"
    by_day = {}
    for s in stories.values():
        d = datetime.fromtimestamp(s["created"], TZ).strftime("%Y-%m-%d")
        by_day.setdefault(d, []).append(s)
    for d, lst in by_day.items():
        p = days / f"{d}.json"
        old = {s["id"]: s for s in load(p, {"stories": []})["stories"]}
        old.update({s["id"]: s for s in lst})
        save(p, {"date": d, "stories": sorted(old.values(), key=lambda s: -s["created"])})
    cutoff = datetime.fromtimestamp(now - ARCHIVE_DAYS * 86400, TZ).strftime("%Y-%m-%d")
    listing = []
    for p in sorted(days.glob("*.json")):
        if p.stem < cutoff:
            p.unlink()
            continue
        listing.append({"date": p.stem, "n": len(load(p, {"stories": []})["stories"])})
    save(v1 / "days.json", {"days": listing[::-1]})
    keep = {s["id"] for p in days.glob("*.json") for s in load(p, {"stories": []})["stories"]}
    for p in (v1 / "a").glob("*.json"):
        if p.stem not in keep and p.stem not in stories:
            p.unlink()


def finish(out: Path, v1: Path, state: dict, stories: dict, now: float):
    archive(v1, stories, now)
    for sid, s in list(stories.items()):
        if now - s["updated"] > KEEP_H * 3600:
            del stories[sid]
    state["events"] = {k: e for k, e in state["events"].items() if now - e["last_item"] < KEEP_H * 3600}
    state["seen"] = {k: t for k, t in state["seen"].items() if now - t < 48 * 3600}
    state["writes"] = dict(sorted(state["writes"].items())[-7:])
    ordered = sorted(stories.values(), key=lambda s: -s["updated"])[:500]
    save(v1 / "index.json", {"generated": int(now), "stories": ordered})
    save(out / "state.json", state)
    (out / ".nojekyll").touch()
    print(f"Veröffentlicht: {len(ordered)} Artikel")


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "out"))
