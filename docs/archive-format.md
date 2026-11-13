# Формат `.zip`-экспорта CardFlow — версия 1 (публичный контракт)

**Статус:** заморожен для MVP (ADR-006, SPEC 0.4 п.4). Изменения — только с повышением `format_version` и новым ADR.

## Структура архива

```text
cardflow-deck.zip
├── meta.json          # метаданные формата и колоды
├── cards.json         # все карточки колоды
└── media/             # медиафайлы (может быть пустым каталогом)
    ├── <media_id_1>
    └── <media_id_2>
```

- Кодировки — UTF-8 (без BOM), JSON — компактный или pretty (импорт принимает любой валидный JSON).
- `media/<id>` — файл без расширения; MIME-тип и путь указываются в `cards.json`.
- Пустая directory-запись `media/` (0 байт, имя оканчивается на `/`) допускается и игнорируется — так могут вести себя сторонние архиваторы. Любые другие неизвестные записи верхнего уровня → ошибка «архив повреждён/неверный формат».
- Даты: `meta.json.deck.*` и `cards.json.cards[].*` — epoch milliseconds (int); `exported_at` — ISO-8601 UTC (`2026-11-12T10:15:30.000Z`).
- `null` — отсутствующее значение (не пустая строка).

## `meta.json`

```json
{
  "format_version": 1,
  "app": "CardFlow",
  "exported_at": "2026-11-12T10:15:30.000Z",
  "deck": {
    "id": "0f8c2a0e-3a4b-4c5d-9e6f-123456789abc",
    "name": "Испанский: базовые глаголы",
    "settings": {},
    "created_at": 1762942530000,
    "updated_at": 1762942530000,
    "archived_at": null
  },
  "cards_count": 2,
  "media_count": 1
}
```

| Поле | Тип | Обязательно | Описание |
|---|---|---|---|
| `format_version` | int | да | Версия формата; сейчас `1`. Иное значение → «версия не поддерживается». |
| `app` | string | да | Всегда `"CardFlow"`. |
| `exported_at` | string (ISO-8601 UTC) | да | Момент экспорта. |
| `deck.id` | string | да | Исходный id колоды (при импорте не используется как PK). |
| `deck.name` | string | да | Имя колоды. |
| `deck.settings` | object | да | `settings_json` SPEC A5 (может быть `{}`). |
| `deck.created_at` | int (epoch ms) | да | Создание. |
| `deck.updated_at` | int (epoch ms) | да | Последнее изменение. |
| `deck.archived_at` | int (epoch ms) \| null | да | Архивность (экспорт архивной колоды её сохраняет). |
| `cards_count` | int | да | Справочно; проверяется при импорте на соответствие `cards.json` (расхождение → `invalidMeta`). |
| `media_count` | int | да | Справочно; проверяется на соответствие `media/`. |

## `cards.json`

```json
{
  "cards": [
    {
      "id": "6a1e2b3c-1111-4222-8333-abcdefabcdef",
      "deck_id": "0f8c2a0e-3a4b-4c5d-9e6f-123456789abc",
      "front": "¿Cómo se dice «говорить»?",
      "back": "hablar",
      "hint": null,
      "card_type": "basic",
      "tags": ["глаголы"],
      "media": [],
      "latex": null,
      "occlusion": null,
      "source_doc_id": null,
      "source_excerpt": null,
      "state": "new",
      "fsrs": null,
      "due": null,
      "suspended": false,
      "buried_until": null,
      "flagged": false,
      "sibling_id": null,
      "content_hash": "9f2c…",
      "created_at": 1762942530000,
      "updated_at": 1762942530000
    },
    {
      "id": "7b2f3c4d-2222-4333-8444-fedcbafedcba",
      "deck_id": "0f8c2a0e-3a4b-4c5d-9e6f-123456789abc",
      "front": "Карточка с изображением",
      "back": "Ответ",
      "hint": "Подсказка",
      "card_type": "basic",
      "tags": ["#тег-без-решётки-в-норме"],
      "media": [
        {
          "id": "c0ffee00-3333-4444-8555-001122334455",
          "card_id": "7b2f3c4d-2222-4333-8444-fedcbafedcba",
          "path": "media/c0ffee00-3333-4444-8555-001122334455.png",
          "mime_type": "image/png"
        }
      ],
      "latex": null,
      "occlusion": null,
      "source_doc_id": null,
      "source_excerpt": null,
      "state": "learning",
      "fsrs": null,
      "due": 1762950000000,
      "suspended": false,
      "buried_until": null,
      "flagged": false,
      "sibling_id": null,
      "content_hash": null,
      "created_at": 1762942530000,
      "updated_at": 1762942530000
    }
  ]
}
```

| Поле | Тип | Обязательно | Комментарий |
|---|---|---|---|
| `id`, `deck_id` | string | да | Внутренние id на момент экспорта. |
| `front` | string | да | Не пустой (иначе `invalidCards`). |
| `back` | string | да | Может быть пустым только у `cloze`? Нет: в v1 обязателен (может быть `""` только если так хранилось; импорт принимает строку). |
| `hint` | string \| null | да | |
| `card_type` | `basic` \| `basic_reversed` \| `cloze` | да | Иное → `invalidCards`. |
| `tags` | string[] | да | До 3 (лишние не отбрасываются молча при импорте — валидируется до 3; нарушение → `invalidCards`). |
| `media` | array объектов `{id, card_id, path, mime_type}` | да | Пустой массив, если медиа нет. |
| `latex` | string \| null | да | |
| `occlusion` | string \| null | да | JSON масок (сырая строка SPEC A5). |
| `source_doc_id` | string \| null | да | |
| `source_excerpt` | string \| null | да | |
| `state` | `new` \| `learning` \| `review` \| `relearning` | да | Иное → `invalidCards`. При наличии `fsrs` колонка информативна: импорт берёт состояние из снимка FSRS. |
| `fsrs` | string \| null | да | Сырой JSON состояния FSRS. При импорте валидируется (`SchedulingCard`) и **перепривязывается к новому id карточки**; битый снимок → `invalidCards`. `null` ⇒ карточка импортируется как `new`. |
| `due` | int (epoch ms) \| null | да | При наличии `fsrs` импорт берёт `due` из снимка FSRS (колонка информативна). |
| `suspended`, `flagged` | bool | да | |
| `buried_until` | int (epoch ms) \| null | да | |
| `sibling_id` | string \| null | да | |
| `content_hash` | string \| null | да | Если `null` — импорт вычисляет `sha256(нормализованный front + "\u0000" + back)`. |
| `created_at`, `updated_at` | int (epoch ms) | да | |

## Импорт (нормативно)

1. Проверяется zip и лимиты (`DeckArchiveLimits`): вход ≤ 100 МБ (проверка размера файла **до чтения в память**), распаковано ≤ 300 МБ, JSON-файлы ≤ 32 МБ, количество записей ≤ 10 000.
2. `format_version` = 1; иначе ошибка «версия не поддерживается». Имя колоды (`deck.name`) после trim не пустое, иначе `invalidMeta`.
3. Создаётся **новая** колода (новый id; имя — из `meta.json` после trim или пользовательское, также с trim); id карточек/медиа генерируются заново.
4. **`content_hash` при импорте пересчитывается** по `front`+`back` (спецификация A5), значению из архива не доверяем: dedup и запись в БД — по пересчитанному хешу. Карточки с одинаковым пересчитанным хешем внутри архива: первая импортируется, остальные пропускаются (счётчик в предпросмотре).
5. **FSRS-снимок перепривязывается к новому id**: `cards.fsrs_json.cardId` — id карточки на момент экспорта, а импорт всегда создаёт новые id (п.3). Без перепривязки планировщик отверг бы снимок («чужой cardId»), и сессия импортированной колоды не запускалась бы. Импорт разбирает `fsrs` как `SchedulingCard`, заменяет `cardId` на новый и пишет сериализованный снимок; `state`/`due` берутся из снимка. Битый `fsrs` → `invalidCards` (историю повторений молча не теряем). `fsrs = null` ⇒ `state = new`, `due = null` (инвариант A5).
6. Медиа: файл `media/<id>` → хранилище приложения; запись в таблицу `media`; связь с карточкой через новый id.
7. Всё — одна транзакция; при ошибке откат (и удаление записанных медиафайлов).
8. Пользователю показываются только сообщения из ARB, маппинг по коду ошибки (`ArchiveErrorCode`).
9. Удаление колоды удаляет и строки `media` её карточек, и файлы в хранилище (best-effort) — см. `DriftDeckRepository.deleteDeck`.
## Совместимость и версии

- В v1 нет `review_logs`, `practice_logs`, настроек приложения и пресетов — только колода + карточки + медиа (границы контракта SPEC 0.4 п.4).
- Совместимое расширение: необязательное поле, игнорируемое старой версией → допускается без смены версии при явной записи в этой таблице; на практике — повышаем версию.
- Несовместимое изменение → `format_version = 2`, поддержка импорта v1 и v2 минимум одну версию.
