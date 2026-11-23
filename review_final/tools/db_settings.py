"""Схема app_settings и значение app.settings (read-only)."""
import json
import sqlite3

PATH = r'C:\Users\piotr\AppData\Roaming\ru.example\cardflow\cardflow\cardflow.sqlite'
con = sqlite3.connect('file:' + PATH + '?mode=ro', uri=True)
for row in con.execute("select sql from sqlite_master where name='app_settings'"):
    print(row[0])
print('--- columns ---')
for row in con.execute('pragma table_info(app_settings)'):
    print(row)
print('--- rows ---')
for row in con.execute('select * from app_settings'):
    print(row)
