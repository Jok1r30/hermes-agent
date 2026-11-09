# Hermes в изоляции от сети

Форк [Hermes Agent](https://github.com/NousResearch/hermes-agent), в котором агент не ходит в интернет. Модель
работает локально через LM Studio, а фоновые обращения наружу выключены в
конфиге: загрузка бинарника tirith с GitHub Releases (`security.tirith_enabled`),
доустановка пакетов с PyPI на лету (`security.allow_lazy_installs`), каталог
моделей с nousresearch.com (`model_catalog.enabled`) и обновление справочника
models.dev (`models_dev.url` уводится в недостижимый адрес) и общая статистика
использования (`telemetry.shared_metrics`: ответ «Нет, спасибо» записан заранее,
поэтому полоса с предложением над чатом не появляется, а адрес отправки уведён
в недостижимый). Инструменты агента — веб-поиск, MCP-серверы, браузер — молчат,
пока их не вызовут.

Отсюда и способ установки: комплект собирается один раз на машине с сетью и
переносится одним архивом. На целевой машине скачиваются только пакеты
Python: нужен доступ к pypi.org или `set PIP_INDEX_URL=<зеркало>`.

1. **Собрать** — на машине с доступом к npm и nodejs.org:

   ```
   git clone https://github.com/Jok1r30/hermes-agent.git
   cd hermes-agent
   offline-bundle\build-bundle.bat
   ```

   20–40 минут. На выходе `hermes-bundle.zip` (~210 МБ) в корне репозитория
   (другое место — `set BUNDLE_OUT=D:\путь\hermes-bundle.zip`).

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

5. **Обновление заблокировано намеренно.** `hermes update` печатает
   предупреждение и выходит, в приложении вместо обновления открывается окно
   с тем же текстом. Штатное обновление — это `git pull` в чекауте, а комплект
   едет без `.git`, так что сработать оно не может, зато способно испортить
   дерево исходников. Обновляться нужно пересборкой: `git pull` и
   `offline-bundle\build-bundle.bat` на сборочной машине, затем пункты 2 и 3 заново. Как
   выпустить новый комплект — [RELEASE.md](RELEASE.md).

Что обязан содержать комплект — [openspec/specs/offline-bundle/spec.md](../openspec/specs/offline-bundle/spec.md).
