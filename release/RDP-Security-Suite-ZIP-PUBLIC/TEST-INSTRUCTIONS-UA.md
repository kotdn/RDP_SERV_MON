# Інструкція для тестування (public build)

Дякуємо за участь у тестуванні RDP Security Service.

## 1) Встановлення

1. Розпакуйте архів у будь-яку папку.
2. Запустіть `UnblockMaster.bat` від імені адміністратора.
3. Введіть `master code` (його надає адміністратор збірки).
4. Підтвердьте код у Telegram (команда прийде в чат, потрібно відповісти `/approve <код>`).
5. Дочекайтесь завершення інсталяції.

`UnblockMaster.bat` автоматично:
- знімає блокування з файлів пакета (Mark-of-the-Web),
- запускає `install-clean.ps1` з підвищенням прав.

Для Telegram-підтвердження інсталятор бере `botToken`/`chatId` з `config.json` або `config.example.json`.
Якщо вони не заповнені, інсталятор попросить ввести їх вручну.

Якщо з'явиться SmartScreen:
- натисніть **Докладніше / More info**,
- далі **Виконати в будь-якому разі / Run anyway**.

## 2) Що перевірити

- Сервіс `RDPSecurityService` успішно встановився і запущений.
- Монітор запускається без помилок і показує події в реальному часі.
- При серії невдалих RDP-входів IP блокується згідно конфігу.
- Правило firewall `RDP_BLOCK_ALL` одне, а IP додаються/видаляються в його `RemoteIP`.
- Ручне розблокування IP в моніторі працює.

Команда перевірки firewall:

```powershell
netsh advfirewall firewall show rule name="RDP_BLOCK_ALL"
```

## 3) Що надіслати за підсумками тесту

- Версія Windows (10/11/Server + build).
- Чи пройшло встановлення з першого разу.
- Що спрацювало добре.
- Які помилки/дивну поведінку помітили.
- Кроки, як відтворити проблему.
- Скріншоти/логи (за можливості).

## 4) Де логи

- `C:\ProgramData\RDPSecurityService\access.log`
- `C:\ProgramData\RDPSecurityService\block_list.log`
- `C:\ProgramData\RDPSecurityService\service.log`
