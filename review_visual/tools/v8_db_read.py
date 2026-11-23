"""Read-only inspection of the owner's CardFlow DB (audit v8).

Never writes: the connection is opened with mode=ro.
"""
import json
import os
import sqlite3

PATH = os.path.expandvars(r"%APPDATA%\ru.example\cardflow\cardflow\cardflow.sqlite")
print("db:", PATH, "exists:", os.path.exists(PATH))
con = sqlite3.connect("file:" + PATH + "?mode=ro", uri=True)
cur = con.cursor()
for key, value in cur.execute("select key, value_json from app_settings").fetchall():
    if "settings" in key:
        try:
            data = json.loads(value)
            print(key, "text_scale =", data.get("text_scale"), "theme =", data.get("theme"))
        except Exception:
            print(key, "unparsed")
print("decks:", cur.execute("select count(*) from decks").fetchone()[0])
print("cards:", cur.execute("select count(*) from cards").fetchone()[0])
print("media:", cur.execute("select count(*) from media").fetchone()[0])
print(
    "review_logs last 24h:",
    cur.execute(
        "select count(*) from review_logs where reviewed_at > datetime('now','-1 day')"
    ).fetchone()[0],
)
print("last 6 review_logs:")
for row in cur.execute(
    "select id, card_id, rating, mode, reviewed_at from review_logs order by id desc limit 6"
).fetchall():
    print("  ", row)
con.close()
