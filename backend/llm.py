"""KI-Aufrufe: Meldungen bündeln und neutrale Artikel schreiben.

Anbieter: Google Gemini (kostenloses Kontingent, Standard wenn GEMINI_API_KEY gesetzt)
oder Anthropic Claude (ANTHROPIC_API_KEY).
"""
import json
import os
import re
import threading
import time

CATS = ["inland", "ausland", "wirtschaft", "boerse", "wissen", "digital", "investigativ", "sport", "wetter"]

PROVIDER = os.environ.get("LLM_PROVIDER") or ("gemini" if os.environ.get("GEMINI_API_KEY") else "anthropic")
_DEFAULTS = {
    "gemini": ("gemini-3.5-flash-lite", "gemini-3.8-flash", "gemini-3.5-flash-lite"),
    "anthropic": ("claude-opus-5-5", "claude-opus-5-5", None),
}[PROVIDER]
CLUSTER_MODEL = os.environ.get("CLUSTER_MODEL") or _DEFAULTS[0]
WRITER_MODEL = os.environ.get("WRITER_MODEL") or _DEFAULTS[1]
WRITER_FALLBACK = os.environ.get("WRITER_FALLBACK_MODEL") or _DEFAULTS[2]
FALLBACK_MODELS = {"claude-opus-5-5", "claude-sonnet-5-5", "claude-opus-5", "claude-fable-5-1"}

_client = None
_lock = threading.Lock()
exhausted: set[str] = set()  # Modelle, deren Tageskontingent in diesem Lauf aufgebraucht ist


def has_key() -> bool:
    return bool(os.environ.get("GEMINI_API_KEY" if PROVIDER == "gemini" else "ANTHROPIC_API_KEY"))


def client():
    global _client
    with _lock:
        if _client is None:
            if PROVIDER == "gemini":
                from google import genai
                _client = genai.Client()
            else:
                import anthropic
                _client = anthropic.Anthropic(max_retries=3, timeout=300)
    return _client


def ask_json(model: str, system: str, user: str, schema: dict, effort: str, max_tokens: int,
             fallback: str | None = None):
    for m in [model, fallback]:
        if not m or m in exhausted:
            continue
        try:
            text = _gemini(m, system, user, schema, max_tokens) if PROVIDER == "gemini"                 else _anthropic(m, system, user, schema, effort, max_tokens)
        except QuotaError:
            print(f"  Kontingent erschöpft: {m}")
            exhausted.add(m)
            continue
        except Exception as e:
            print(f"  Fehler {m}: {e}")
            return None
        if text is None:
            return None
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            print("  ungültiges JSON")
            return None
    return None


class QuotaError(Exception):
    pass


def _gemini(model, system, user, schema, max_tokens):
    from google.genai import errors, types
    for attempt in range(3):
        try:
            resp = client().models.generate_content(
                model=model, contents=user,
                config=types.GenerateContentConfig(
                    system_instruction=system, response_mime_type="application/json",
                    response_json_schema=schema, max_output_tokens=max_tokens, temperature=0.4))
            return resp.text
        except errors.ClientError as e:
            if e.code != 429:
                raise
            msg = str(e)
            if "PerDay" in msg or attempt == 2:
                raise QuotaError() from e
            # Minutenlimit: kurz warten und erneut versuchen
            m = re.search(r"retry in ([\d.]+)s|retryDelay['\"]?: ?['\"](\d+)s", msg)
            wait = float(next(g for g in m.groups() if g)) if m else 30
            print(f"  Minutenlimit {model}, warte {wait:.0f}s")
            time.sleep(min(wait + 1, 65))


def _anthropic(model, system, user, schema, effort, max_tokens):
    import anthropic
    kw = dict(
        model=model, max_tokens=max_tokens, system=system,
        messages=[{"role": "user", "content": user}],
        output_config={"effort": effort, "format": {"type": "json_schema", "schema": schema}},
    )
    try:
        if model in FALLBACK_MODELS:
            resp = client().beta.messages.create(
                betas=["server-side-fallback-2026-07-01"], fallbacks="default", **kw)
        else:
            resp = client().messages.create(**kw)
    except anthropic.BadRequestError as e:
        print(f"  bad request ({e.message}) – retry ohne Fallback")
        resp = client().messages.create(**kw)
    except anthropic.RateLimitError as e:
        raise QuotaError() from e
    if resp.stop_reason in ("refusal", "max_tokens"):
        print(f"  abgebrochen: {resp.stop_reason}")
        return None
    return next((b.text for b in resp.content if b.type == "text"), "")


# ---------------------------------------------------------------- Clustering

CLUSTER_SYSTEM = """Du bist Chef vom Dienst einer neutralen deutschen Nachrichtenredaktion.
Du bekommst neue Meldungen verschiedener Medien (Schlagzeile + Anreißer) und die Liste der Ereignisse, die die Redaktion bereits verfolgt.

Aufgabe für jede neue Meldung:
1. Ordne sie einem bestehenden Ereignis zu (dessen ID), wenn sie über dasselbe konkrete Ereignis bzw. dieselbe konkrete Entwicklung berichtet.
2. Sonst lege ein neues Ereignis an (Schlüssel "n1", "n2", ...). Mehrere neue Meldungen zum selben neuen Ereignis bekommen denselben Schlüssel.
3. Markiere als drop: Werbung, Produkttests, Kaufberatung, Ratgeber/Service ohne Nachrichtenwert, Gewinnspiele, Horoskope, Rätsel, Rezepte, Kommentare/Meinungsstücke/Kolumnen, Podcast- und Newsletter-Hinweise, Programmhinweise, reine Bildergalerien, Klatsch ohne gesellschaftliche Relevanz.

Ein Ereignis ist EINE konkrete Nachricht (z. B. "Bundestag beschließt Rentenpaket"), kein Dauerthema (nicht "Ukraine-Krieg" als Sammelbecken). Eine neue, eigenständige Entwicklung eines laufenden Themas ist ein neues Ereignis. Liveblogs/Liveticker ordnest du dem passendsten aktuellen Ereignis zu.

Für neue Ereignisse:
- cat: inland (Deutschland-Politik/Gesellschaft), ausland, wirtschaft, boerse (Märkte, Kurse, Unternehmenszahlen, Geldanlage, Zinsen), wissen (Wissenschaft, Gesundheit, Umwelt, Klima), digital (Technik, Internet, KI, Datenschutz), investigativ (NUR exklusive Recherchen/Enthüllungen von Medien), sport, wetter.
- imp (Bedeutung 1-10): 10 historisch; 8-9 Top-Nachricht des Tages; 6-7 wichtig, breites Interesse; 4-5 berichtenswert, eher speziell oder regional; 1-3 Randnotiz.
- label: kurze, neutrale deutsche Arbeitsüberschrift.
- tone: "positiv" (gute Nachricht: Fortschritt, Erfolg, Rettung, Einigung, Durchbruch), "negativ" (belastend: Krieg, Gewalt, Tod, Katastrophe, Krise) oder "neutral".
- image_query: englische Suchbegriffe für ein passendes, NICHT irreführendes Foto auf Wikimedia Commons: ein Ort, Gebäude, eine Institution, ein Symbolmotiv oder ein Porträt einer zentral beteiligten Person (z. B. "Reichstag building Berlin", "Federal Constitutional Court Karlsruhe", "Friedrich Merz", "Frankfurt Stock Exchange"). Keine Begriffe, die ein konkretes Unglück oder Opfer zeigen würden.

Bei bestehenden Ereignissen darfst du unter "reassess" die Bedeutung anpassen, wenn neue Meldungen eine deutliche Eskalation oder Entspannung zeigen."""

CLUSTER_SCHEMA = {
    "type": "object",
    "properties": {
        "items": {"type": "array", "items": {
            "type": "object",
            "properties": {
                "i": {"type": "integer"},
                "event": {"type": "string", "description": "bestehende ID oder neuer Schlüssel n1, n2 ..."},
                "drop": {"type": "boolean"},
            },
            "required": ["i", "event", "drop"], "additionalProperties": False}},
        "new_events": {"type": "array", "items": {
            "type": "object",
            "properties": {
                "key": {"type": "string"},
                "cat": {"type": "string", "enum": CATS},
                "imp": {"type": "integer"},
                "label": {"type": "string"},
                "tone": {"type": "string", "enum": ["positiv", "neutral", "negativ"]},
                "image_query": {"type": "string"},
            },
            "required": ["key", "cat", "imp", "label", "tone", "image_query"], "additionalProperties": False}},
        "reassess": {"type": "array", "items": {
            "type": "object",
            "properties": {"id": {"type": "string"}, "imp": {"type": "integer"}},
            "required": ["id", "imp"], "additionalProperties": False}},
    },
    "required": ["items", "new_events", "reassess"], "additionalProperties": False,
}


def cluster(existing: list[dict], items: list[dict], now_str: str):
    ex = "\n".join(f"{c['id']} | {c['cat']} | {c['label']}" for c in existing) or "(noch keine)"
    it = "\n".join(
        f"{i} | {x['s']} | {x['t']} | {x['d'][:180]}" for i, x in enumerate(items))
    user = f"Aktuelle Zeit: {now_str}\n\nBESTEHENDE EREIGNISSE (ID | Kategorie | Titel):\n{ex}\n\nNEUE MELDUNGEN (Nr | Medium | Schlagzeile | Anreißer):\n{it}"
    return ask_json(CLUSTER_MODEL, CLUSTER_SYSTEM, user, CLUSTER_SCHEMA, "low", 16000)


# ---------------------------------------------------------------- Schreiben

WRITER_SYSTEM = """Du bist Redakteur einer streng neutralen, faktenorientierten deutschen Nachrichten-App. Du schreibst zu einem Ereignis einen eigenständigen Nachrichtenartikel auf Grundlage mehrerer Medienberichte, die dir als Faktengrundlage dienen.

Grundsätze:
- Schreibe vollständig in eigenen Worten. Übernimm keine Sätze, Formulierungen oder Strukturen aus den Quellen. Wörtliche Zitate nur, wenn es kurze Aussagen beteiligter Personen sind, mit Nennung der Person.
- Nur belegte Fakten. Nichts erfinden, keine Zahlen schätzen, nicht spekulieren. Allgemeines Hintergrundwissen nur, wenn es sicher und zeitlos ist (z. B. was eine Institution macht). Dein eigenes Wissen kann veraltet sein – die Quellen haben Vorrang.
- Behauptungen, die nur von einer Seite stammen, klar zuordnen ("nach Angaben von ...", "laut ..."). Unbestätigtes als unbestätigt kennzeichnen. Widersprechen sich Quellen, benenne den Widerspruch.
- Neutral: keine wertenden Adjektive, keine Dramatisierung, keine eigene Meinung, keine Empfehlungen. Bei umstrittenen Themen die wichtigsten Positionen fair und gleich gewichtet darstellen.
- Exklusive Recherchen anderer Medien immer dem Medium zuschreiben ("Recherchen von NDR, WDR und SZ zufolge ...").
- Klar, verständlich, ohne Fachjargon; Fachbegriffe kurz erklären. Sachlicher Nachrichtenstil, aktive Sprache, Präsens/Perfekt.
- Medien nicht im Fließtext als "die Quellen" bezeichnen – berichte die Fakten direkt.

Presseethische Regeln (angelehnt an den Pressekodex des Deutschen Presserats):
- Unschuldsvermutung: Tatverdächtige und Beschuldigte nicht vorverurteilen ("mutmaßlich", "laut Anklage", "nach Angaben der Polizei"); Freisprüche und Einstellungen erwähnen, wenn bekannt.
- Privatsphäre: Keine Namen, Fotos-Beschreibungen, Adressen oder identifizierenden Details von Privatpersonen, Opfern, Angehörigen, Zeugen oder Tatverdächtigen. Personen des öffentlichen Lebens nur in ihrer öffentlichen Rolle.
- Herkunft, Religion, Nationalität oder sexuelle Orientierung von Tatverdächtigen nur nennen, wenn ein begründetes öffentliches Interesse besteht.
- Suizid: keine Methoden oder Orte beschreiben; am Ende den Satz "Hilfe in Krisen: Telefonseelsorge 0800 111 0 111 (kostenlos, rund um die Uhr)." anfügen.
- Gesundheit: keine Heilversprechen, keine unbelegten Behandlungsempfehlungen.
- Gewalt und Unglücke: sachlich, ohne reißerische Details.
- Schwere Vorwürfe gegen benannte Personen oder Unternehmen nur wiedergeben, wenn sie aus den Berichten klar belegt und zugeordnet sind; Stellungnahmen der Betroffenen erwähnen, wenn vorhanden.

Ausgabe:
- title: sachliche Überschrift, max. 80 Zeichen, kein Clickbait, keine Frage.
- teaser: ein Satz, max. 200 Zeichen – das Wichtigste auf einen Blick.
- summary: 3-5 Stichpunkte (je max. 25 Wörter), die zusammen die Kurzfassung bilden und ohne den Rest verständlich sind.
- sections: die ausführliche Fassung in 3-6 Abschnitten mit kurzer Zwischenüberschrift (h) und Text (text; Absätze mit Leerzeile trennen). Beginne mit dem Kern (Was ist passiert?), dann Details, Hintergrund/Einordnung, Reaktionen. Ziel: 400-900 Wörter. Nutze alle belastbaren Details aus den Berichten (Zahlen, Hintergründe, Zusammenhänge, Reaktionen, Vorgeschichte). Nur wenn die Faktenlage wirklich dünn ist, kürzer – niemals mit Floskeln auffüllen.
- facts: 0-6 Kerndaten (k: Bezeichnung, v: Wert), nur wörtlich aus den Quellen belegte Zahlen/Daten.
- positions: 0-4 Positionen beteiligter Seiten (who, view) – nur bei Kontroversen.
- outlook: wie es weitergeht (Termine, nächste Schritte), falls bekannt, sonst leer.
- cat, imp (1-10): Kategorie und Bedeutung (siehe Vorgabe; bei Bedarf korrigieren).
- image: Index des passendsten Bildkandidaten oder -1, wenn keiner wirklich passt. Ein Bild passt nur, wenn es das Thema zeigt, ohne in die Irre zu führen (kein Foto eines anderen Ereignisses, das wie das aktuelle wirkt; Porträts nur von zentral beteiligten Personen). Im Zweifel -1.
- location: Hauptort (Stadt/Land) oder leer.
- tone: Wirkung der Nachricht auf Leser. "positiv" = überwiegend gute Nachricht (Fortschritt, Erfolg, Rettung, Einigung, Durchbruch, Verbesserung, sportlicher Erfolg, erfreuliche Entdeckung). "negativ" = überwiegend belastend (Krieg, Gewalt, Tod, Katastrophe, Unglück, Verbrechen, schwere Krise, Verschlechterung). Sonst "neutral" (sachliche Politik, Zahlen ohne klare Richtung, gemischte Lage).
- assets: Kürzel der Marktwerte aus der mitgelieferten Liste, die direkt Gegenstand der Meldung sind (betroffenes Unternehmen, Index, Rohstoff, Währung). Leer, wenn keiner direkt betroffen ist oder keine Liste mitgeliefert wurde.
- sensitive: true, wenn die Meldung im Kern schwere Vorwürfe (Straftaten, Fehlverhalten, Skandale) gegen benannte oder erkennbare Personen oder Unternehmen enthält, die noch nicht gerichtlich festgestellt sind; sonst false."""

WRITER_SCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string"},
        "teaser": {"type": "string"},
        "summary": {"type": "array", "items": {"type": "string"}},
        "sections": {"type": "array", "items": {
            "type": "object",
            "properties": {"h": {"type": "string"}, "text": {"type": "string"}},
            "required": ["h", "text"], "additionalProperties": False}},
        "facts": {"type": "array", "items": {
            "type": "object",
            "properties": {"k": {"type": "string"}, "v": {"type": "string"}},
            "required": ["k", "v"], "additionalProperties": False}},
        "positions": {"type": "array", "items": {
            "type": "object",
            "properties": {"who": {"type": "string"}, "view": {"type": "string"}},
            "required": ["who", "view"], "additionalProperties": False}},
        "outlook": {"type": "string"},
        "cat": {"type": "string", "enum": CATS},
        "imp": {"type": "integer"},
        "image": {"type": "integer"},
        "location": {"type": "string"},
        "tone": {"type": "string", "enum": ["positiv", "neutral", "negativ"]},
        "assets": {"type": "array", "items": {"type": "string"}},
        "sensitive": {"type": "boolean"},
    },
    "required": ["title", "teaser", "summary", "sections", "facts", "positions",
                 "outlook", "cat", "imp", "image", "location", "tone", "assets", "sensitive"],
    "additionalProperties": False,
}


def write(event: dict, reports: list[dict], previous: dict | None, images: list[dict],
          extra: str, now_str: str):
    parts = [f"Aktuelle Zeit: {now_str}",
             f"Vorläufige Einordnung: Kategorie {event['cat']}, Bedeutung {event['imp']}/10, Arbeitstitel: {event['label']}"]
    if previous:
        parts.append(
            "Dieses Ereignis wurde bereits veröffentlicht. Schreibe eine aktualisierte, vollständige Fassung, "
            "die die neuen Entwicklungen einarbeitet (das Neueste zuerst).\nBisherige Fassung:\n"
            f"Titel: {previous['title']}\n" + "\n".join("- " + s for s in previous.get("summary", [])))
    if extra:
        parts.append(extra)
    rep = []
    for n, r in enumerate(reports, 1):
        block = f"[Bericht {n} – {r['s']}]\nSchlagzeile: {r['t']}\nAnreißer: {r.get('d', '')}"
        if r.get("full"):
            block += f"\nText:\n{r['full']}"
        rep.append(block)
    parts.append("MEDIENBERICHTE (nur Faktengrundlage, nicht übernehmen):\n\n" + "\n\n".join(rep))
    if images:
        parts.append("BILDKANDIDATEN (Wikimedia Commons):\n" + "\n".join(
            f"{i}: {im['title']} – {im['desc']}" for i, im in enumerate(images)))
    else:
        parts.append("BILDKANDIDATEN: keine (image = -1)")
    return ask_json(WRITER_MODEL, WRITER_SYSTEM, "\n\n".join(parts), WRITER_SCHEMA, "medium", 16000,
                    fallback=WRITER_FALLBACK)


TONE_SCHEMA = {
    "type": "object",
    "properties": {"items": {"type": "array", "items": {
        "type": "object",
        "properties": {"id": {"type": "string"}, "tone": {"type": "string", "enum": ["positiv", "neutral", "negativ"]}},
        "required": ["id", "tone"], "additionalProperties": False}}},
    "required": ["items"], "additionalProperties": False,
}


def tones(items: list[dict]) -> dict | None:
    """Ordnet Meldungen nachträglich als positiv, neutral oder negativ ein."""
    system = ("Ordne jede Nachricht nach ihrer Wirkung auf Leser ein: positiv (Fortschritt, Erfolg, Rettung, Einigung, "
              "Durchbruch), negativ (Krieg, Gewalt, Tod, Katastrophe, Verbrechen, schwere Krise) oder neutral.")
    user = "\n".join(f"{x['id']} | {x['title']} | {x['teaser']}" for x in items)
    res = ask_json(CLUSTER_MODEL, system, user, TONE_SCHEMA, "low", 4000)
    return {x["id"]: x["tone"] for x in res["items"]} if res else None
