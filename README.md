<p align="center">
  <img src="assets/banner.png" alt="Hermes Agent" width="100%">
</p>

# Hermes Agent: офлайн-форк

Форк [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) для машин без
доступа в интернет. Агент ставится из одного архива и работает с моделью на вашем сервере:
LM Studio на этом же компьютере или корпоративный сервер моделей.

## Чем отличается от исходного проекта

- Установка из одного архива, без PowerShell и без Node на целевой машине.
- Обновление и проверка новых версий через интернет отключены.
- В настройках моделей доступны только свои адреса серверов (Custom endpoints).
- Фоновые обращения в интернет выключены в `config.yaml` при установке.

## Быстрый старт

На машине с интернетом собрать архив (20-40 минут):

```
git clone https://github.com/Jok1r30/hermes-agent.git
cd hermes-agent
offline-bundle\build-bundle.bat
```

На целевой машине распаковать `hermes-bundle.zip` и запустить установщик. Нужен Python
3.11-3.13 с python.org.

```
mkdir C:\hermes-setup
tar -xf hermes-bundle.zip -C C:\hermes-setup
C:\hermes-setup\install.bat
```

## Документация

| Что | Где |
| --- | --- |
| Установка и обновление | [offline-bundle/README.md](offline-bundle/README.md) |
| Выпуск нового архива | [offline-bundle/RELEASE.md](offline-bundle/RELEASE.md) |
| Требования к изменениям форка | [openspec/specs/](openspec/specs/) |
| Возможности самого агента | [README исходного проекта](https://github.com/NousResearch/hermes-agent#readme) |

Лицензия MIT, как у исходного проекта: [LICENSE](LICENSE).
