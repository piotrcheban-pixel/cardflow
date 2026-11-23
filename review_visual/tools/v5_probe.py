import json
import os
import sqlite3
import sys

db = os.path.join(os.environ["APPDATA"], "ru.example", "cardflow", "cardflow", "cardflow.sqlite")
con = sqlite3.connect("file:" + db + "?mode=ro", uri=True)
print("DB:", db)
for name, sql in con.execute("select name, sql from sqlite_master where type='table'"):
    print("TABLE", name, sql)
print()
for row in con.execute("select * from app_settings"):
    print("SETTING", row)
print()
for row in con.execute("select * from decks limit 10"):
    print("DECK", row)
print()
n = con.execute("select count(*) from cards").fetchone()[0]
print("CARDS", n)
for row in con.execute(
    "select id, deck_id, front, back, substr(coalesce(media_json,''),1,120), substr(coalesce(occlusion_json,''),1,80) from cards limit 8"
):
    print("CARD", row)
print()
for row in con.execute("select id, status, mode, provider, cards_count from generation_jobs order by id desc limit 5"):
    print("JOB", row)
