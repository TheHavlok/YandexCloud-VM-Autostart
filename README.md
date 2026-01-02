# Yandex Cloud Preemptible VM Auto-Start Monitor

Сервис для автоматического контроля и запуска **прерываемых (Preemptible) виртуальных машин**
в **Yandex Cloud**.

Предназначен для сценариев, когда виртуальная машина:
- создаётся как *прерываемая* (дешевле),
- может быть остановлена Yandex Cloud в любой момент,
- должна автоматически подниматься обратно без ручного вмешательства.

Сервис работает в фоне как `systemd`-служба на Linux (Debian / Ubuntu).

---

## Зачем нужен этот проект

Прерываемые виртуальные машины в Yandex Cloud:
- стоят значительно дешевле обычных VM
- могут быть остановлены облаком в любой момент
- после остановки **не запускаются автоматически**

Это делает их неудобными для:
- VPN
- прокси
- тестовых серверов
- временных сервисов
- personal/dev-инфраструктуры

Данный сервис решает эту проблему:

- регулярно проверяет состояние VM
- если VM перешла в `STOPPED`, автоматически отправляет команду `start`
- позволяет использовать **прерываемые VM** без постоянного ручного контроля
- снижает расходы на инфраструктуру

---

## Основные возможности

- Мониторинг состояния виртуальной машины в Yandex Cloud
- Автоматический запуск при статусе `STOPPED`
- Оптимизирован для **Preemptible VM**
- Настраиваемый интервал проверки
- Непрерывная работа в фоне
- Автоматический перезапуск при ошибках
- Логирование через `journalctl`
- Работа без виртуального окружения Python

---

## Как это работает

systemd
└── run.sh
└── main.py
└── Yandex Cloud Compute API

1. `systemd` запускает сервис при старте системы
2. Python-скрипт запрашивает состояние VM через API
3. Если VM остановлена (`STOPPED`) — отправляется команда `start`
4. Сервис продолжает мониторинг с заданным интервалом

---

## Когда это особенно полезно

- Использование **прерываемых VM для VPN**
- Личные серверы и прокси
- Dev / test окружения
- Временные сервисы
- Минимизация затрат на облако

---

## Требования

### Операционная система
- Debian 10+
- Ubuntu 20.04+

### Программное обеспечение
- Python **3.8+**
- pip
- systemd
- Доступ в интернет

### Yandex Cloud
- Прерываемая (Preemptible) виртуальная машина
- IAM Token с правами:
  - `compute.instances.get`
  - `compute.instances.start`

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
git clone https://github.com/yourname/vpn-xsync.git
sudo mv vpn-xsync /opt/vpn-xsync
cd /opt/vpn-xsync
```

### 3. Настройка конфигурации

Открой файл main.py:

```python
INSTANCE_ID = "your-instance-id"
IAM_TOKEN  = "your-iam-token"
CHECK_INTERVAL = 60
```

Где взять значения

INSTANCE_ID — ID прерываемой VM в Yandex Cloud
IAM_TOKEN — IAM-токен (через yc iam create-token)


## Установка как systemd-служба
### Файл службы

```bash
[Unit]
Description=Yandex Cloud Preemptible VM Auto-Start Monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/vpn-xsync
ExecStart=/opt/vpn-xsync/run.sh
Restart=always
RestartSec=10
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
```

### Активация службы

```bash
sudo systemctl daemon-reload
sudo systemctl enable vpn-xsync
sudo systemctl start vpn-xsync
```