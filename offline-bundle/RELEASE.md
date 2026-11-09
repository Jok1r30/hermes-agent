# Выпуск обновлённого офлайн-комплекта

Для тех, кто работает над форком и выпускает новый `hermes-bundle.zip`. Как комплект ставят на
целевой машине — в [README.md](README.md); что он обязан содержать — в
[openspec/specs/offline-bundle/spec.md](../openspec/specs/offline-bundle/spec.md). Все скрипты
комплекта лежат в папке `offline-bundle/`, команды ниже запускаются из корня репозитория.

Коротко: синхронизировать форк с апстримом (если нужно) → проверить правки форка → собрать
`offline-bundle\build-bundle.bat` → проверить архив и установку → выпустить. Обновить комплект на месте нельзя:
каждое обновление — это новый архив, который ставят поверх (пункты 2–3 [README.md](README.md)).

## 0. Что в форке своего

Правки форка — то, что надо сохранить при каждом слиянии с апстримом. У каждой есть спецификация
в `openspec/specs/`:

| Правка | Где в коде | Спецификация |
|---|---|---|
| Офлайн-комплект: сборщик и установщики | папка `offline-bundle/`: `build-bundle.bat`, `install.bat`, `install-hermes.bat`, `fetch-retry.mjs`, `README.md`, `RELEASE.md`; корневой `README.md` | `offline-bundle` |
| `hermes update` — заглушка вместо обновления | `cmd_update_disabled` и подмена `build_update_parser` в `hermes_cli/main.py` | `update-lockout` |
| Нет сетевых проверок версии | заглушка рядом с апстримовой `check_for_updates` в `hermes_cli/source_check.py`; закрыты баннер, `hermes --version`, эндпоинт дашборда | `update-lockout` |
| Десктоп: заглушка с гифкой вместо обновления | `apps/desktop/src/components/update-status.tsx`, `apps/desktop/public/update-disabled.gif`, обработчики `hermes:updates:*` в `apps/desktop/electron/main.ts` | `update-lockout` |
| В настройках провайдеров только Custom endpoints и `local` | `ENABLED_PROVIDER_VIEWS` в `apps/desktop/src/app/settings/` | `desktop-settings` |
| Длительность хода сохраняется в сессии | `_stamp_turn_duration` в `agent/session_persistence.py`, `apps/desktop/src/lib/chat-messages/hydration.ts` | `openspec/changes/persist-turn-duration` |

Конфиг сетевой изоляции (`security.tirith_enabled`, `model_catalog.enabled`, `models_dev.url` и др.)
пишет `install.bat` (`:write_config`), только если `config.yaml` ещё нет.

## 1. Сборочная машина

- Windows 10/11 x64 с доступом к npm, nodejs.org и зеркалу Electron (за прокси — `set HTTPS_PROXY=…`,
  для Electron — `set ELECTRON_MIRROR=…`).
- Git, Python 3.11–3.13 с python.org, Node 26.4+ (нет или старее — `build-bundle.bat` сам поставит portable Node
  в `%LOCALAPPDATA%\hermes\node`).
- Около 10 ГБ свободного места: `node_modules`, Electron, промежуточная папка `.bundle-stage`.

## 2. Синхронизация с апстримом (если нужна)

```
git remote add upstream https://github.com/NousResearch/hermes-agent.git   # один раз
git fetch upstream
git switch -c sync/upstream-YYYY-MM-DD main
git merge upstream/main
```

Апстрим часто переносит код, который правил форк, поэтому конфликт может и не возникнуть, а правка
просто потеряется. После слияния пройдите по таблице из п. 0 и убедитесь, что каждая правка на месте:

```
git grep -n "cmd_update_disabled" -- hermes_cli/
git grep -n "ENABLED_PROVIDER_VIEWS" -- apps/desktop/src/
git grep -n "_stamp_turn_duration" -- agent/ run_agent.py
git grep -n "update-disabled.gif" -- apps/desktop/
```

Если правка уехала, перенесите её на новое место и опишите это в сообщении merge-коммита. Образец —
`17917136b6 Merge upstream/main: синхронизация форка (35889 коммитов, с 20 августа)`. Если у правки
поменялось место, обновите и её спецификацию в `openspec/specs/`.

Корневой `README.md` в форке свой — короткая карточка на русском. Апстрим часто меняет свой README,
и при слиянии будет конфликт: оставляйте версию форка (`git checkout --ours README.md`).

Сверьте и требование к Node: апстрим поднимает `engines` в `package.json`, а `build-bundle.bat` и
`install-hermes.bat` проверяют версию и качают portable Node своей строкой (`node -e …` и
`latest-vNN.x`). После коммита `4d5c6cfb0c chore(node): require Node >=26` старая проверка на 22.22
пропускала portable Node 22, и `npm ci` падал с `EBADENGINE`.

```
git grep -n -A3 "\"engines\"" -- package.json
git grep -n "process.exit((v\[0\]" -- offline-bundle/
```

## 3. Проверки перед сборкой

```
scripts/run_tests.sh tests/hermes_cli/
npm ci
npm run test --workspace apps/desktop -- src/app/updates-overlay.unsupported.test.tsx src/lib/chat-messages.test.ts
```

Апстримовые тесты, которые описывают настоящее обновление, в форке падать не должны: их помечают
class-level skip с причиной, а тело теста не трогают, чтобы следующие слияния ложились чисто. Рядом
кладут свой тест на поведение форка (пример — `TestForkUpdateCheckEndpoint` в
`tests/hermes_cli/test_dashboard_admin_endpoints.py`).

Вручную из чекаута (нужен venv с `pip install -e .`):
- `hermes update` печатает предупреждение и выходит, ничего не меняя;
- `hermes --version` не обращается к GitHub.

## 4. Сборка

Сохраняйте архив вне репозитория: `hermes-bundle.zip` и `.bundle-stage\` не внесены в `.gitignore`,
и при `git add -A` 200-мегабайтный архив попадёт в коммит.

```
git switch main
git pull
set BUNDLE_OUT=D:\hermes-releases\hermes-bundle-YYYY-MM-DD-<sha>.zip
offline-bundle\build-bundle.bat
```

`<sha>` — `git rev-parse --short HEAD`. Сборка идёт 20–40 минут. В конце должно быть
`TUI: bundled`. Если напечатано `TUI: MISSING`, комплект не выпускать: без TUI на целевой машине не
работает вкладка Chat десктопа.

На стадии 4/6 упаковщик сам качает с GitHub Electron, 7-Zip, Windows Kits, библиотеку подписи, .NET и
rcedit. Соединение он ждет 10 секунд, и при нестабильной связи загрузка падает с одной строкой
`TypeError: fetch failed`. Хуже всего с Electron: после архива на 110 МБ отдельно качается
`SHASUMS256.txt`, и если этот запрос не прошел, архив выбрасывается. Поэтому на время упаковки сборщик
подключает `offline-bundle/fetch-retry.mjs` (через `NODE_OPTIONS=--import`): он повторяет запрос до шести
раз, если соединение не установилось или оборвалось, и пишет об этом строкой `[fetch-retry]`. Сверх
того сборщик до трех раз перезапускает саму упаковку, а скачанное остается в `.cache\desktop-inputs`.
В архив этот кэш и `fetch-retry.mjs` не попадают.

## 5. Проверка архива

```
tar -tf D:\hermes-releases\hermes-bundle-….zip | findstr /r /c:"^install.bat" /c:"^desktop/Hermes.exe" /c:"^node/node.exe" /c:"^src/pyproject.toml" /c:"^src/hermes_cli/tui_dist/entry.js" /c:"^src/hermes_cli/web_dist/index.html"
```

Должны найтись все шесть строк. Затем — пробная установка, лучше на отдельной машине или ВМ:

```
mkdir C:\hermes-setup
tar -xf hermes-bundle-….zip -C C:\hermes-setup
cd C:\hermes-setup
install.bat
```

На шаге 7/7 должно быть `TUI: ready`; после установки `hermes doctor` проходит, `hermes update`
выдаёт заглушку, десктоп открывается с ярлыка, в About и в окне обновлений — гифка-заглушка.

Ставите на своей машине — помните: `install.bat` через `setx` переписывает пользовательские
переменные `HERMES_DESKTOP_HERMES`, `HERMES_DESKTOP_HERMES_ROOT` и `HERMES_SKIP_NODE_BOOTSTRAP`.
С `set HERMES_HOME=C:\hermes-test` файлы лягут в отдельную папку, но переменные всё равно будут
указывать на неё — после проверки верните прежние значения.

## 6. Выпуск

1. Контрольная сумма для получателей:
   `certutil -hashfile hermes-bundle-….zip SHA256`.
2. Тег на собранный коммит: `git tag -a bundle-YYYY-MM-DD -m "<что изменилось>"` и
   `git push origin bundle-YYYY-MM-DD`.
3. GitHub Release на этот тег (через веб или `gh release create bundle-YYYY-MM-DD <архив> --notes-file <файл>`).
   В заметках — что изменилось для пользователя, коммит, SHA-256 и ссылка на `offline-bundle/README.md`.
4. Получателям: удалить старую распаковку и выполнить пункты 2–3 `offline-bundle/README.md` с новым архивом.
   `config.yaml` и данные в `%LOCALAPPDATA%\hermes` установщик не трогает.

Тегов и релизов в `origin` пока нет: схема `bundle-YYYY-MM-DD` вводится этой инструкцией.

## Известные ограничения

- **На целевой машине нужен PyPI или зеркало.** Python-зависимостей в архиве нет: `install.bat`
  ставит их `pip install -e ".[all]"` и без доступа к pypi.org останавливается. Тогда перед
  запуском нужен `set PIP_INDEX_URL=<корпоративное зеркало>` или `HTTPS_PROXY`.
- **`install-hermes.bat` ждёт `hermes-desktop-bundle.zip`, а `build-bundle.bat` такого архива не
  собирает.** Для офлайн-комплекта используется `install.bat`. `install-hermes.bat` — для установки
  из чекаута, а без этого архива десктоп собирается на месте, и это долго.
- **Сборщик исключает папки по имени на любой глубине** (`robocopy /XD "web" "docs" "tests" …`).
  Поэтому вместе с корневыми `web/`, `docs/`, `tests/` из комплекта выпадают и `skills/web/`,
  `plugins/web/` (провайдеры веб-поиска), `plugins/hermes-achievements/docs/`. Намеренно ли это,
  пока не проверено.
- `scripts/build-bundle.ps1` и `scripts/build-bundle.sh` — апстримовая сборка десктоп-приложения
  (DMG/AppImage/установщики). К офлайн-комплекту форка они не относятся.
