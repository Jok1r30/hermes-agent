# Hermes в изоляции от сети

Форк [Hermes Agent](README.md), в котором агент не ходит в интернет. Модель
работает локально через LM Studio, а фоновые обращения наружу выключены в
конфиге: загрузка бинарника tirith с GitHub Releases (`security.tirith_enabled`),
доустановка пакетов с PyPI на лету (`security.allow_lazy_installs`), каталог
моделей с nousresearch.com (`model_catalog.enabled`) и обновление справочника
models.dev (`models_dev.url` уводится в недостижимый адрес). Инструменты агента —
веб-поиск, MCP-серверы, браузер — молчат, пока их не вызовут; телеметрии в
проекте нет.

Отсюда и способ установки: комплект собирается один раз на машине с сетью и
переносится одним архивом, так что на целевой машине ничего не скачивается.

1. **Собрать** — на машине с доступом к npm и nodejs.org:

   ```
   git clone https://github.com/Jok1r30/hermes-agent.git
   cd hermes-agent
   build-bundle.bat
   ```

   20–40 минут. На выходе `hermes-bundle.zip` (~210 МБ) рядом со скриптом.

2. **Распаковать** — куда угодно на целевой машине, установщик сам перенесёт
   файлы куда нужно:

   ```
   mkdir C:\hermes-setup
   tar -xf hermes-bundle.zip -C C:\hermes-setup
   ```

   `mkdir` обязателен: `tar -C` не создаёт каталог, а падает с `could not chdir`.

3. **Запустить** — из распакованной папки:

   ```
   cd C:\hermes-setup
   install.bat
   ```

   Нужен Python 3.11–3.13 с python.org, не из Microsoft Store. Всё встаёт в
   `%LOCALAPPDATA%\hermes`. Дальше CLI — `%LOCALAPPDATA%\hermes\hermes.cmd`,
   полноэкранный интерфейс — он же с `--tui`. Перед первым запросом в LM Studio
   загрузить модель и нажать Start Server на вкладке Developer.

4. **Desktop-приложение** — ярлык Hermes на рабочем столе, который создаёт
   установщик. Сам исполняемый файл лежит в
   `%LOCALAPPDATA%\hermes\desktop\Hermes.exe`.

Подробности — сетевая изоляция построчно, известные дефекты, разбор сборки —
в [runbook'е](https://claude.ai/code/artifact/ed8b9cc7-dae8-4fdd-b67d-995d2c907c51).
