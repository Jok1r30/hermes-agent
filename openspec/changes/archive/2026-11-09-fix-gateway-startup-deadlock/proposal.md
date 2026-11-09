# Шлюз зависает на старте без WAL: вложенный read-контекст в `_idle_s`

> Оформлено задним числом: исправление сделано и закоммичено (`e1fddb9eb9`) до появления
> правила «сначала change». Задачи отмечены по факту и проверены заново при оформлении.

## Why

09.11.2026 на рабочей машине Hermes Desktop бесконечно показывал CONNECTING. По логам:

- `desktop.log`: каждые ~61 с `Desktop boot failed: Gateway starting (deadline)` — `hermes gateway ensure`
  ждёт 60 с и не дожидается готовности шлюза, Desktop повторяет.
- `gateway.log`: шлюз стартует, за 0,4–0,8 с прогревает «turn machinery», и через 2 минуты
  `shutdown_watchdog: Gateway event loop missed 3 consecutive liveness probes … exiting with code 75`.
  Цикл повторяется.
- `gateway-shutdown-watchdog.log`: главный поток стоит в `hermes_state.py:956` (`with self._lock:`)
  по цепочке `arm_startup_orphan_closes` → `_idle_s` (`session_viewer_close.py:243`) →
  `_physical_target` → `local_receipt` → `_read_ctx`.

Причина: `_idle_s` открывал `db._read_ctx()` и уже внутри него вызывал `_physical_target`, который
открывает второй `_read_ctx()`. С WAL внешний контекст берёт соединение из пула без блокировки, и
вложенность безвредна. Без WAL каждый `_read_ctx` держит `SessionDB._lock` — обычный
`threading.Lock`, без повторного входа, — и второй захват ждёт первый вечно.

WAL выключен там, где SQLite уязвима к WAL-reset (на рабочей машине — 3.45.3 из Python 3.13 с
python.org; Hermes тогда держит `journal_mode=DELETE`). Код доходит до `_idle_s`, когда прошлый
шлюз умер аварийно и оставил сессии-«сироты» (на рабочей машине — pid 17176, 09.11 06:13).
Пока сироты в базе, каждый перезапуск упирается в ту же блокировку.

## What Changes

- `gateway/session_viewer_close.py`, `_idle_s`: `target = _physical_target(...)` вычисляется до
  входа в `_read_ctx`; запрос и его аргумент не меняются. Комментарий объясняет, почему порядок важен.
- Регрессионный тест `tests/gateway/test_viewer_close_idle_non_wal.py`: БД без WAL, блокировка
  записи подменена на ту, что при повторном захвате падает через 5 с вместо зависания.
- Других вложенных вызовов `_physical_target` внутри `_read_ctx` в `gateway/` нет (проверено поиском).

## Impact

- Новая capability `gateway-startup`.
- Код: `gateway/session_viewer_close.py`; тест: `tests/gateway/test_viewer_close_idle_non_wal.py`.
- Рабочая машина ставится из офлайн-бандла форка: исправление попадёт туда с пересборкой бандла
  или ручной правкой `_idle_s` в `%LOCALAPPDATA%\hermes\hermes-agent\gateway\session_viewer_close.py`.
- Не меняет: выбор режима журнала (WAL/DELETE) и версию Python в бандле — это отдельные вопросы
  (Python 3.14 и SQLite ≥ 3.51.3 включили бы WAL и сняли условие зависания).
