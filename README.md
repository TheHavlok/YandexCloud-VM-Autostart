# Yandex Cloud Preemptible VM Auto-Start Monitor

Сервис для автоматического контроля и запуска **прерываемых (Preemptible) виртуальных машин** в **Yandex Cloud**.  

Предназначен для сценариев, когда виртуальная машина:

- создаётся как *прерываемая* (дешевле стандартной VM),  
- может быть остановлена Yandex Cloud в любой момент,  
- должна автоматически подниматься обратно без ручного вмешательства.

Сервис работает в фоне как `systemd`-служба на Linux (Debian / Ubuntu).  

---

## Как это работает

1. `systemd` запускает сервис при старте системы.  
2. Python-скрипт проверяет состояние VM через Yandex Cloud API.  
3. Если VM остановлена (`STOPPED`) — отправляется команда `start`.  
4. Скрипт повторяет проверку через заданный интервал (`CHECK_INTERVAL`).  

---

## Основные возможности

- Автоматический мониторинг и запуск VM.  
- Поддержка **прерываемых VM** (Preemptible).  
- Интерактивное получение **IAM токена** через OAuth.  
- Выбор конкретного **Cloud**, **Folder** и **INSTANCE_ID** при нескольких объектах.  
- Сохранение конфигурации в файл `~/.yc_autostart_credentials` для последующих запусков.  
- Цветной вывод в терминал с подсветкой важных параметров.  

---

## Требования

### Yandex Cloud

- Прерываемая (Preemptible) виртуальная машина  
- IAM Token  
- INSTANCE ID  

### Система

- Linux (Debian / Ubuntu)  
- Python 3  
- Модуль `requests`  

---

## Установка

### 1. Установка системных зависимостей

```bash
sudo apt update
sudo apt install -y python3 python3-pip
sudo pip3 install requests
```

### 2. Клонирование проекта

```bash
git clone https://github.com/TheHavlok/YandexCloud-VM-Autostart.git
sudo mv YandexCloud-VM-Autostart /opt/YandexCloud-VM-Autostart
cd /opt/YandexCloud-VM-Autostart
```

### 3. Настройка конфигурации

Можно указать данные вручную в main.py:

```bash
INSTANCE_ID = "your-instance-id"
IAM_TOKEN  = "your-iam-token"
CHECK_INTERVAL = 60  # секунды
```

Или использовать интерактивный режим:

```bash
python3 main.py --getmyinfo
```

В интерактивном режиме:

1. Вставьте ваш OAuth токен (инструкция: OAuth Token).

2. Скрипт автоматически обменяет его на IAM токен.

3. Если несколько Clouds или Folders — можно выбрать нужный.

4. Скрипт покажет список доступных VM и предложит сохранить IAM токен и INSTANCE_ID в файл ~/.yc_autostart_credentials.

После сохранения файла, скрипт будет использовать эти данные при последующих запусках.

---

## Установка как systemd-служба

### 1. Создайте файл службы

```bash
sudo nano /etc/systemd/system/yc-autostart.service
```

Вставьте:

```ini
[Unit]
Description=Yandex Cloud Preemptible VM Auto-Start Monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/YandexCloud-VM-Autostart
ExecStart=/usr/bin/python3 /opt/YandexCloud-VM-Autostart/main.py
Restart=always
RestartSec=10
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
```

### 2. Активация службы

```bash
sudo systemctl daemon-reload
sudo systemctl enable yc-autostart
sudo systemctl start yc-autostart
```

### 3. Статус службы

```bash
sudo systemctl status yc-autostart
```

---

## Использование

  - Интерактивный режим получения IAM токена и INSTANCE_ID:

  ```bash
  python3 main.py --getmyinfo
  ```

  - Обычный запуск мониторинга:
  ```bash
  python3 main.py
  ```
  Служба systemd автоматически запускает скрипт в фоне и перезапускает при остановке VM.

## Файл конфигурации

После интерактивного получения токена создаётся файл:

```bash
~/.yc_autostart_credentials
```

Пример содержимого:

```bash
INSTANCE_ID="dsfgsdfgsdfhsdfgh"
IAM_TOKEN="t1.XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
```

## Настройка интервала проверки

Измените параметр CHECK_INTERVAL в main.py (в секундах).
Пример:

```python
CHECK_INTERVAL = 60  # проверка каждую минуту
```