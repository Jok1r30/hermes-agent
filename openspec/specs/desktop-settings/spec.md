# desktop-settings

Настройки desktop-приложения в форке.

## Requirements

### Requirement: Настройки провайдеров ограничены локальным сценарием

Раздел Providers ДОЛЖЕН предлагать только настройку собственных эндпоинтов.

#### Scenario: Пользователь открывает Providers

- **Given** desktop-приложение запущено
- **When** пользователь открывает раздел Providers
- **Then** доступен только пункт Custom endpoints
- **And** пунктов Accounts и API keys нет

#### Scenario: Переход по старой ссылке

- **Given** сохранена ссылка на удалённую вкладку, например `pview=keys`
- **When** она открывается
- **Then** показывается Custom endpoints
- **And** экран не падает
