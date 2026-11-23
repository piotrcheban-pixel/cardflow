import json
import os
import sqlite3

db = os.path.join(os.environ["APPDATA"], "ru.example", "cardflow", "cardflow", "cardflow.sqlite")
con = sqlite3.connect("file:" + db + "?mode=ro", uri=True)
value = con.execute("select value_json from app_settings where key='app.settings'").fetchone()[0]
data = json.loads(value)
print("text_scale =", data.get("text_scale"))
