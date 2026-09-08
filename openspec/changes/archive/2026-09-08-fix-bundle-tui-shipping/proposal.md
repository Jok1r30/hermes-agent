# Довезти TUI до целевой машины в офлайн-комплекте

## Why

Форк ставится на машину, где EDR блокирует PowerShell, а npm/Node/Electron
запускать нельзя. Всё тяжёлое собирается на быстрой машине скриптом
`build-bundle.bat` и переносится одним `hermes-bundle.zip`, который на целевой
машине разворачивает `install.bat`.

Сейчас TUI до целевой машины не доезжает вообще, и `hermes --tui` там не
запускается. Две независимые причины:

1. **Собранный файл не попадает в архив.** `ui-tui/scripts/build.mjs` пишет
   результат в `ui-tui/dist/entry.js`. Hermes ищет прибранный бандл в
   `hermes_cli/tui_dist/entry.js` (`_find_bundled_tui`, `hermes_cli/main.py:2253`)
   либо в `$HERMES_TUI_DIR/dist/entry.js`. Ни того, ни другого сборщик не
   создаёт: `ui-tui` стоит в списке исключений `robocopy` в
   `build-bundle.bat:151`, а `HERMES_TUI_DIR` установщик не выставляет.
   Комментарий в `build-bundle.bat:102-106` утверждает, что вывод сборки
   ui-tui попадает в `hermes_cli\tui_dist` — это неверно и вводит в
   заблуждение при следующей правке.

2. **На целевой машине нет Node.** Даже с доехавшим `entry.js` запуск TUI
   идёт через `node --expose-gc entry.js`. Установщик Node не переносит и при
   этом выставляет `HERMES_SKIP_NODE_BOOTSTRAP=1`, запрещая Hermes скачать его
   самому (это осознанное решение — nodejs.org недоступен). `_node_bin("node")`
   в такой ситуации печатает `node not found — install Node.js to use the TUI`
   и завершает процесс.

Отдельно: поведение при отсутствии TUI хуже, чем считалось. Это не мягкий
откат на Python-интерфейс — `_ensure_tui_workspace` не находит ни `ui-tui/`
(исключён из архива), ни `.git` (тоже исключён), поэтому `git restore`
невозможен, и команда завершается `sys.exit(1)` с советом выполнить
`git restore -- ui-tui` в чекауте, которого на целевой машине нет.

## What Changes

- `build-bundle.bat` копирует `ui-tui\dist\entry.js` в
  `hermes_cli\tui_dist\entry.js` сразу после сборки TUI — файл едет внутри уже
  копируемого дерева `hermes_cli\`, менять исключения `robocopy` не нужно.
- `build-bundle.bat` кладёт в комплект `node.exe`, взятый из того Node,
  которым он сам собирал (portable из `%LOCALAPPDATA%\hermes\node` или
  системный с PATH — оба случая разрешаются через `where node`).
- `build-bundle.bat` явно сообщает, довезён TUI или нет, вместо молчаливого
  пропуска: сейчас при провале сборки печатается WARN, но комплект всё равно
  собирается без TUI и об этом больше нигде не говорится.
- `install.bat` раскладывает `node.exe` в `%HERMES_HOME%\node\node.exe` —
  это ровно та раскладка, которую ожидает `iter_hermes_node_dirs()` на Windows
  и которую создаёт штатный `install.ps1`, так что `find_node_executable`
  подхватывает его без правок PATH.
- Итоговая проверка установки дополняется запуском TUI.

Выбран путь через `hermes_cli/tui_dist/`, а не через `HERMES_TUI_DIR`
(которым пользуются Nix и Docker-образ), потому что он не требует ещё одной
переменной окружения и не добавляет каталог в архив: бандл самодостаточен
(`build.mjs`: «single self-contained dist/entry.js. No runtime node_modules
needed»), а `hermes_cli\` копируется целиком и так.

## Impact

- Затронутая capability: `offline-bundle`.
- Файлы: `build-bundle.bat`, `install.bat`.
- Размер комплекта вырастает примерно на 80 МБ (`node.exe`) — против текущих
  ~336 МБ.
- Код самого Hermes не меняется: обе точки входа (`tui_dist`, managed node
  tree) уже поддерживаются upstream и покрыты тестами
  (`tests/hermes_cli/test_tui_bundled.py`).
- Инструкцию по развёртыванию (артефакт «Развёртывание форка Hermes») после
  реализации нужно поправить: раздел «Известные дефекты» описывает только
  первую из двух причин и неверно утверждает, что без правки CLI «откатывается
  на Python-интерфейс».
