"""Чтение данных профиля владельца ТОЛЬКО НА ЧТЕНИЕ (mode=ro) для визуального аудита.

Команды:
  card <substring>       — найти карточки, чей front/back содержит подстроку
  counts                 — счётчики таблиц
  decks                  — список колод со счётчиками
"""
import os
import sqlite3
import sys

DB = os.path.expandvars(r'%APPDATA%\ru.example\cardflow\cardflow\cardflow.sqlite')


def connect():
    con = sqlite3.connect('file:' + DB + '?mode=ro', uri=True)
    con.text_factory = str
    return con


def main():
    cmd = sys.argv[1]
    out = []
    con = connect()
    cur = con.cursor()
    if cmd == 'card':
        needle = sys.argv[2]
        rows = cur.execute(
            'select id, card_type, front, back, tags_json from cards '
            'where front like ? or back like ? limit 5',
            ('%' + needle + '%', '%' + needle + '%'),
        ).fetchall()
        for r in rows:
            out.append(f'ID: {r[0]}  TYPE: {r[1]}')
            out.append(f'FRONT: {r[2]}')
            out.append(f'BACK : {r[3]}')
            out.append(f'TAGS : {r[4]}')
            out.append('---')
    elif cmd == 'counts':
        for t in ('decks', 'cards', 'review_logs', 'media', 'session_presets', 'app_settings', 'generation_jobs'):
            try:
                n = cur.execute(f'select count(*) from {t}').fetchone()[0]
                out.append(f'{t}: {n}')
            except sqlite3.Error as e:
                out.append(f'{t}: ERR {e}')
    elif cmd == 'decks':
        rows = cur.execute('select id, name, updated_at from decks order by updated_at desc').fetchall()
        for r in rows:
            out.append(f'DECK: {r[1]} (updated {r[2]})')
    con.close()
    text = '\n'.join(out) if out else '(пусто)'
    with open(os.path.join('review_visual', 'raw', 'db_read.txt'), 'w', encoding='utf-8') as f:
        f.write(text)
    print('written review_visual/raw/db_read.txt', len(text), 'chars')


if __name__ == '__main__':
    main()
