# Configuration

Этот документ описывает конфигурацию системы снапшотов и восстановления.

---

## Общий принцип

Все скрипты используют конфигурацию через environment-файлы (.env).

По умолчанию:

- snapshot-docker → config/snapshot-docker.env
- snapshot-system → config/snapshot-system.env
- restore-docker → config/restore-docker.env
- restore-system → config/restore-system.env

Можно переопределить:

```bash
ENV_FILE=/custom/path.env ./script.sh
```

---

## Основные принципы

- Нет жёстко захардкоженных значений
- Есть безопасные значения по умолчанию
- Все пути настраиваемы
- Единый подход во всех скриптах

---

## Конфигурация снапшотов

### Docker snapshot

```bash
DEST_BASE=/mnt/nextcloud_data/.infra_snapshots/docker
KEEP_COUNT=28

DOCKER_PROJECTS_DIR=/opt/devteam/docker
DOCKER_ETC_DIR=/etc/docker
```

| Переменная           | Описание                         |
|----------------------|----------------------------------|
| DEST_BASE            | где хранятся снапшоты            |
| KEEP_COUNT           | сколько снапшотов хранить        |
| DOCKER_PROJECTS_DIR  | путь к docker-проектам           |
| DOCKER_ETC_DIR       | путь к /etc/docker               |

---

### System snapshot

```bash
DEST_BASE=/mnt/nextcloud_data/.infra_snapshots/system
KEEP_COUNT=14
```

| Переменная  | Описание                       |
|-------------|--------------------------------|
| DEST_BASE   | директория системных снапшотов |
| KEEP_COUNT  | сколько снапшотов хранить      |

---

## Конфигурация восстановления

### Docker restore

```bash
SNAP_BASE=/mnt/nextcloud_data/.infra_snapshots/docker
LOG_DIR=/mnt/nextcloud_data/.infra_snapshots/_logs

PROJECTS_DST=/opt/devteam/docker
ETC_DOCKER_DST=/etc/docker
```

| Переменная      | Описание                             |
|-----------------|--------------------------------------|
| SNAP_BASE       | откуда берём снапшоты                |
| LOG_DIR         | куда пишутся логи                    |
| PROJECTS_DST    | путь восстановления docker-проектов  |
| ETC_DOCKER_DST  | путь восстановления /etc/docker      |

---

### System restore

```bash
SNAP_BASE=/mnt/nextcloud_data/.infra_snapshots/system
LOG_DIR=/mnt/nextcloud_data/.infra_snapshots/_logs
```

| Переменная  | Описание                  |
|-------------|---------------------------|
| SNAP_BASE   | источник снапшотов        |
| LOG_DIR     | директория логов          |

---

## Поведение env-файлов

- Загружаются автоматически (если существуют)
- Переменные переопределяют значения по умолчанию
- Отсутствующие значения берутся из дефолтов скрипта

---

## Рекомендации

### 1. Использовать отдельный диск

```bash
/mnt/*
```

---

### 2. Ограничить доступ к конфигам

```bash
chmod 600 /etc/ext4-rollback-tool/*.env
```

---

### 3. Разумный retention

- Docker: 14–30 снапшотов
- System: 7–14 снапшотов

---

### 4. Не хранить снапшоты внутри /

Плохо:

```bash
/snapshots
```

Почему:

- риск рекурсивного восстановления
- риск случайного удаления

---

## Стратегия проверки

1. Создать снапшот  
2. Изменить систему  
3. Запустить restore с dry-run  
4. Проверить план  
5. Применить restore  

---

## Итог

Конфигурация:

- простая  
- гибкая  
- безопасная  
- готова к продакшену  
