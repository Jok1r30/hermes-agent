# offline-bundle — дельта требований

## ADDED Requirements

### Requirement: Комплект содержит собранный TUI

Сборщик `build-bundle.bat` ДОЛЖЕН помещать собранный бандл TUI в
`hermes_cli/tui_dist/entry.js` внутри комплекта — по пути, который проверяет
`_find_bundled_tui()` в `hermes_cli/main.py`.

#### Scenario: Сборка TUI прошла успешно

- **Given** на сборочной машине выполняется `build-bundle.bat`
- **And** `npm run build --workspace ui-tui` завершился успешно и создал `ui-tui/dist/entry.js`
- **When** сборщик доходит до стадии подготовки комплекта
- **Then** файл `hermes_cli/tui_dist/entry.js` существует в дереве исходников
- **And** он попадает в `hermes-bundle.zip` вместе с остальным содержимым `hermes_cli/`

#### Scenario: Сборка TUI провалилась

- **Given** `npm run build --workspace ui-tui` завершился с ошибкой
- **And** `ui-tui/dist/entry.js` отсутствует
- **When** сборщик доходит до стадии подготовки комплекта
- **Then** он печатает предупреждение, явно сообщающее, что комплект собирается без TUI
- **And** сборка продолжается — остальной комплект остаётся пригодным

### Requirement: Комплект содержит Node-рантайм

Сборщик ДОЛЖЕН класть в комплект `node.exe` того Node, которым он собирал
проект, потому что на целевой машине Node отсутствует, а установщик выставляет
`HERMES_SKIP_NODE_BOOTSTRAP=1` и тем самым запрещает Hermes скачать его самому.

#### Scenario: Node взят из portable-установки

- **Given** сборочная машина не имела подходящего Node на PATH
- **And** сборщик установил portable Node в `%LOCALAPPDATA%\hermes\node`
- **When** выполняется стадия подготовки комплекта
- **Then** `node/node.exe` присутствует в комплекте

#### Scenario: Node взят с PATH

- **Given** на сборочной машине уже есть Node 22.22 или новее на PATH
- **When** выполняется стадия подготовки комплекта
- **Then** `node/node.exe` присутствует в комплекте и является тем же исполняемым файлом, который разрешает `where node`

#### Scenario: Node не удалось разрешить

- **Given** путь к `node.exe` определить не удалось
- **When** сборщик доходит до стадии подготовки комплекта
- **Then** сборка прерывается с сообщением, называющим причину
- **And** неполный `hermes-bundle.zip` не создаётся

### Requirement: Установщик раскладывает Node туда, где Hermes его находит

Установщик `install.bat` ДОЛЖЕН помещать `node.exe` из комплекта в
`%HERMES_HOME%\node\node.exe` — первый каталог, который перебирает
`iter_hermes_node_dirs()` на Windows, — чтобы `find_node_executable("node")`
разрешал его без изменения PATH.

#### Scenario: Node есть в комплекте, на целевой машине его нет

- **Given** распакованный комплект содержит `node\node.exe`
- **And** `%HERMES_HOME%\node\node.exe` не существует
- **When** выполняется `install.bat`
- **Then** `node.exe` копируется в `%HERMES_HOME%\node\node.exe`
- **And** установщик сообщает, что Node-рантайм разложен

#### Scenario: Node уже установлен ранее

- **Given** `%HERMES_HOME%\node\node.exe` уже существует
- **When** выполняется `install.bat`
- **Then** существующий файл не перезаписывается

#### Scenario: Node отсутствует в комплекте

- **Given** распакованный комплект не содержит `node\node.exe`
- **When** выполняется `install.bat`
- **Then** установка доходит до конца
- **And** установщик сообщает, что TUI будет недоступен

### Requirement: Установщик подтверждает готовность TUI

Финальная проверка `install.bat` ДОЛЖНА отдельно сообщать о наличии обеих
частей, необходимых для запуска TUI, чтобы отсутствие любой из них было видно
сразу, а не при первом запуске `hermes --tui`.

#### Scenario: Обе части на месте

- **Given** установка завершена
- **And** существуют `hermes_cli\tui_dist\entry.js` и `%HERMES_HOME%\node\node.exe`
- **When** выполняется финальная стадия установщика
- **Then** он печатает, что TUI доступен

#### Scenario: Одной из частей нет

- **Given** установка завершена
- **And** отсутствует `hermes_cli\tui_dist\entry.js` или `%HERMES_HOME%\node\node.exe`
- **When** выполняется финальная стадия установщика
- **Then** он печатает, какой именно части не хватает
- **And** установка считается успешной — CLI и desktop-приложение работают без TUI
