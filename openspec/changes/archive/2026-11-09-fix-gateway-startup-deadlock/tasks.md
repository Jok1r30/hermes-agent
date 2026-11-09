# Tasks

- [x] 1.1 В `_idle_s` (`gateway/session_viewer_close.py`) вычислять `_physical_target` до `db._read_ctx()`.
- [x] 1.2 Найти другие вызовы `_physical_target` внутри открытого `_read_ctx` в `gateway/` — других нет.
- [x] 1.3 Регрессионный тест `tests/gateway/test_viewer_close_idle_non_wal.py`: падает на коде до правки
      (`AssertionError: nested SessionDB read context…`), проходит с правкой.
- [x] 1.4 Прогон `tests/gateway/test_viewer_close_lifecycle.py`, нового теста и
      `tests/hermes_state/test_session_db_read_path_split.py` — все проходят.
- [x] 1.5 Коммит `e1fddb9eb9`, отправлен в `origin/main`.
- [x] 1.6 Сверить реализацию с требованиями `specs/gateway-startup/spec.md`.
