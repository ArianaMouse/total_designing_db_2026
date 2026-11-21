# FoodExpress — итоговый проект базы данных

Готовый локальный комплект для сдачи учебного проекта. Репозиторий Git не требуется.

## Состав

- `db/schema/install.sql` — установка всех объектов в правильном порядке через `psql`;
- `db/schema/*.sql` — схема, типы, таблицы, триггеры, процедуры, функция и представление;
- `db/schema/grants.sql` — создание роли `inspector` и выдача прав;
- `db/constraints.md` — обоснование ограничений и проектных решений;
- `db/tests.md` — заполненный протокол проверки;
- `db/foodexpress_makarova.backup` — бинарная резервная копия `pg_dump -Fc`.

## Имя схемы

Схема называется `makarova_food`, архив — `foodexpress_makarova.backup`, в соответствии с требованиями задания.

## Установка из SQL

Схема `exts` и расширение `uuid-ossp` должны быть подготовлены администратором заранее, как требует задание:

```sql
CREATE SCHEMA IF NOT EXISTS exts;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA exts;
```

Затем из каталога проекта:

```powershell
psql -U postgres -d foodexpress -f db/schema/install.sql
psql -U postgres -d foodexpress -f db/schema/grants.sql
```

Проверка под аудитором:

```powershell
psql -U inspector -d foodexpress
```

```sql
SET search_path TO makarova_food, exts;
CALL erase_test_data();
CALL insert_test_data(10);
SELECT * FROM get_statistic();
SELECT * FROM how_much_money ORDER BY year_month;
```

`insert_test_data(n)` добавляет новый независимый набор данных и может вызываться многократно. Для получения ровно контрольных количеств сначала вызывается `erase_test_data()`.

