import json
import os
import sqlite3
from datetime import datetime, timezone

db = os.path.join(os.environ["APPDATA"], "ru.example", "cardflow", "cardflow", "cardflow.sqlite")
con = sqlite3.connect("file:" + db + "?mode=ro", uri=True)
print("cards", con.execute("select count(*) from cards").fetchone()[0])
print("decks", con.execute("select count(*) from decks").fetchone()[0],
      "archived", con.execute("select count(*) from decks where archived_at is not null").fetchone()[0])
print("review_logs", con.execute("select count(*) from review_logs").fetchone()[0])
last = con.execute("select max(reviewed_at) from review_logs").fetchone()[0]
print("last review", last, datetime.fromtimestamp(last / 1000, tz=timezone.utc).isoformat() if last else None)
print("generation_jobs", con.execute("select count(*) from generation_jobs").fetchone()[0])
settings = json.loads(con.execute("select value_json from app_settings where key='app.settings'").fetchone()[0])
print("settings", {k: settings[k] for k in ("theme", "text_scale", "dynamic_color", "high_contrast", "dyslexia_font")})
print("now", datetime.now(tz=timezone.utc).isoformat())
