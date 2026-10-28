# Убрать Accounts и API keys из настроек провайдеров

## Why

Модель работает локально через LM Studio. Логин в облачные аккаунты и ключи
к чужим API форку не нужны: это лишние экраны, которые к тому же подталкивают
завести то самое сетевое взаимодействие, от которого форк уходит.

Custom endpoints остаётся — именно им указывают на локальный сервер.

## What Changes

- Из подменю Providers убираются пункты Accounts и API keys
  (`settings/index.tsx`), остаётся Custom endpoints.
- `PROVIDER_VIEWS` в `providers-settings.tsx` сокращается до
  `['custom-endpoints']`, значение по умолчанию — оно же.
- Экраны и их файлы не удаляются: правится только навигация и список
  доступных вкладок, чтобы правка оставалась маленькой и обратимой.

## Impact

- Новая capability `desktop-settings`.
- Файлы: `apps/desktop/src/app/settings/index.tsx`,
  `apps/desktop/src/app/settings/providers-settings.tsx`.
- Ключи провайдеров, если они уже заданы, продолжают работать — убирается
  только интерфейс для их правки. Отредактировать их можно в `.env`
  и `config.yaml`.
