# Гифка не показывается: окно недостижимо

## Why

Мой же change `disable-update-in-fork` собран из двух половин, которые друг
другу противоречат:

- `hermes:updates:check` отвечает `supported: false`;
- окно с текстом и гифкой открывается по `hermes:updates:apply`.

Но при `supported: false` оверлей обновлений рисует `CenteredStatus` без кнопки
установки (`updates-overlay.tsx:199`), а значит `apply` не вызывается никогда.
Пользователь видит штатную плашку «Update not available» с моим текстом —
и без гифки. Отдельное окно недостижимо в принципе.

## What Changes

Показывать гифку там, куда пользователь реально попадает, — в самом оверлее.

- `updates-overlay.tsx`: в ветке `!status.supported` под текстом рендерится
  гифка.
- Гифка переезжает в `apps/desktop/public/`, потому что рендерер берёт
  картинки оттуда через `assetPath()`; `public/**` уже входит в упаковку.
- Из `electron/main.ts` удаляются `showUpdateDisabledWindow` и окно —
  они больше не нужны, а мёртвый код в чужом файле только мешает.
  `hermes:updates:apply` продолжает отвечать отказом на случай прямого вызова.
- `apps/desktop/assets/update-disabled.html` и копия гифки там удаляются.

## Impact

- Capability `update-lockout`: требование про окно заменяется требованием
  про оверлей.
- Файлы: `apps/desktop/src/app/updates-overlay.tsx`,
  `apps/desktop/electron/main.ts`, перемещение гифки.
- Проверять надо в собранном приложении: прошлый раз я проверил содержимое
  окна отдельным Electron-скриптом, а достижимость самого окна — нет.
  Именно этот разрыв и пропустил баг.
