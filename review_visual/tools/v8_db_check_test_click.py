"""Read-only check: did the accidental test-mode click change the card schedule?"""
import datetime
import os
import sqlite3

PATH = os.path.expandvars(r"%APPDATA%\ru.example\cardflow\cardflow\cardflow.sqlite")
con = sqlite3.connect("file:" + PATH + "?mode=ro", uri=True)
cur = con.cursor()
card_id = "9d9a644f"
row = cur.execute(
    "select id, state, due, updated_at, substr(fsrs_json,1,80) from cards where id like ?",
    (card_id + "%",),
).fetchone()
print("card:", row)
if row and row[3]:
    print("card updated_at:", datetime.datetime.fromtimestamp(row[3] / 1000))
print(
    "test logs:",
    cur.execute(
        "select id, card_id, rating, mode, scheduled_days, actual_days, reviewed_at "
        "from review_logs where mode='test' order by reviewed_at desc limit 3"
    ).fetchall(),
)
print(
    "logs count any mode for this card:",
    cur.execute(
        "select count(*) from review_logs where card_id like ?", (card_id + "%",)
    ).fetchone()[0],
)
con.close()
