# Обоснование ограничений FoodExpress

Схема: `makarova_food`. Таблица заказа сохранена под контрактным именем `"order"`; двойные кавычки используются осознанно, потому что `order` — ключевое слово PostgreSQL (BR-13.1).

## Enum-типы

| Тип | Значения | Основание |
|---|---|---|
| `restaurant_status` | `активен`, `неактивен` | BR-4.3 |
| `product_status` | `доступно`, `нет_в_наличии`, `архив` | BR-5.5 |
| `courier_status` | `свободен`, `занят`, `на_доставке`, `уволен` | BR-6.2 |
| `order_status` | `создан`, `готовится`, `в_доставке`, `доставлен`, `отменён` | BR-7.7 |
| `order_pay_status` | `ожидает`, `оплачен`, `ошибка` | BR-7.9 |
| `payment_status` | `успех`, `ошибка`, `в_обработке` | BR-8.2 |
| `payment_type` | `карта`, `наличные`, `безнал` | BR-8.2, BR-8.6 |
| `review_entity_type` | `блюдо`, `ресторан`, `заказ` | BR-9.1 |

Все восемь перечислений реализованы через `CREATE TYPE ... AS ENUM`, как требует BR-11.5.

## Проектные ловушки

### `payment` — атрибуты и агрегированный статус

В `payment` добавлены `payment_type`, `amount`, `transaction_id`, `transaction_timestamp`, `status`: это полный состав попытки оплаты из BR-8.2. Тип оплаты находится именно в попытке, а не в заказе, потому что BR-8.6 разрешает разные способы в последовательных попытках. `trg_payment_validate_amount` проверяет равенство суммы итогу заказа (BR-8.4). `trg_payment_sync_order_status` после INSERT/UPDATE/DELETE вычисляет `order.pay_status` по BR-8.7. Частичный уникальный индекс разрешает не более одной успешной попытки на заказ (BR-8.1); наличие успешной попытки является состоянием процесса и обеспечивается генератором/рабочим сценарием, потому что запрещать промежуточное состояние без успеха нельзя.

### Принадлежность адреса клиенту

`"order".(client_id, address_id)` имеет составной FK на `client_address(client_id, address_id)`. Поэтому записать чужой адрес невозможно даже прямым SQL (BR-7.4). Отдельные FK на `client` и `address` оставлены для явного выполнения связей концептуальной ERD.

### Один ресторан в заказе

Триггер `trg_order_structure_same_restaurant` перед вставкой/сменой позиции сравнивает `order.restaurant_id` и `product.restaurant_id` и отклоняет несовпадение (BR-7.3). Дублировать `restaurant_id` в `order_structure` не стали: это создало бы транзитивную зависимость и ухудшило 3НФ.

### Полиморфный `review.entity_id`

Сохранён контракт ERD `entity_type + entity_id`. Обычный FK на три разные таблицы невозможен. Триггер `trg_review_validate_target` проверяет, что автор совпадает с клиентом заказа, ресторан совпадает с рестораном заказа, блюдо присутствует в `order_structure`, а для типа `заказ` `entity_id = order_id` (BR-9.1, BR-9.2). Это даёт ссылочную целостность без трёх разреженных FK-колонок.

## CHECK-ограничения

| Таблица | Ограничение | Основание и смысл |
|---|---|---|
| `address` | непустые `street`, `house_number`; `apartment_office` либо NULL, либо непустой | BR-3.1, BR-3.2, BR-11.3 |
| `client` | непустой `login` | BR-2.1, BR-11.3 |
| `client` | `password ~ '^[0-9a-f]{32}$'` | BR-2.3: хранится MD5 |
| `client` | телефон в формате `+` и 11–15 цифр | BR-2.1 и разумный технический формат из BR-11.6 |
| `restaurant` | непустые имя, описание и реквизиты | BR-4.1, BR-4.5, BR-11.3 |
| `restaurant` | `work_end > work_start` | BR-4.4 |
| `restaurant` | `rating IS NULL OR rating BETWEEN 0 AND 5` | BR-4.2, BR-9.7 |
| `product_category` | непустое название | BR-5.7, BR-11.3 |
| `product` | непустые название и описание | BR-5.2, BR-11.3 |
| `product` | `price >= 0` | BR-5.3 |
| `product` | `rating IS NULL OR rating BETWEEN 0 AND 5` | BR-5.4, BR-9.7 |
| `product` | `photo_url` либо NULL, либо непустой | BR-5.6 |
| `courier` | непустое ФИО и корректно оформленный телефон | BR-6.1, BR-11.3 |
| `courier` | `coefficient BETWEEN 0.10 AND 0.50` | BR-6.4 |
| `courier` | у статуса `уволен` есть `dismissal_date` | BR-6.3 |
| `courier` | увольнение не раньше найма | следует из смысла дат BR-6.1 и общего требования согласованности BR-11.3 |
| `courier_pay` | `year > 0`, `month BETWEEN 1 AND 12` | период выплаты по BR-10.1–BR-10.3 |
| `courier_pay` | `amount >= 0` | BR-10.4 |
| `courier_pay` | коэффициент в диапазоне 0.10–0.50 | BR-6.4, BR-10.2 |
| `order` | `order_amount >= 0` | BR-7.10 |
| `order` | `total_amount >= 1000` | BR-1.8, BR-7.11 |
| `order` | доставка не раньше создания | BR-7.13 |
| `order` | timestamp доставки заполнен ровно для статуса `доставлен` | BR-7.12 |
| `order` | непустое описание | BR-11.3 применительно к атрибуту ERD |
| `payment` | `amount > 0` | BR-8.2, BR-8.4 |
| `payment` | непустой внешний идентификатор | BR-8.3 |
| `order_structure` | `quantity > 0` | BR-7.15 |
| `review` | непустой текст | BR-9.3, BR-11.3 |
| `review` | фотография либо NULL, либо непустая ссылка | BR-9.3 |
| `review` | `rating BETWEEN 1 AND 5` | BR-9.4 |

## UNIQUE и первичные составные ключи

| Таблица | Столбцы/условие | Основание |
|---|---|---|
| `address` | `UNIQUE NULLS NOT DISTINCT (street, house_number, apartment_office)` | один физический адрес хранится одной строкой; иначе запрет общего адреса ресторанов из BR-3.3 можно обойти дубликатом |
| `client` | `login` | BR-2.2 |
| `client` | `phone_number` | BR-2.2 |
| `client_address` | PK `(client_id, address_id)` | BR-2.5 запрещает повторную привязку |
| `restaurant` | `address_id` | BR-3.3 запрещает двум ресторанам один адрес |
| `courier_pay` | PK `(year, month, courier_id)` | BR-10.3: одна выплата курьеру за месяц |
| `payment` | `transaction_id` | BR-8.3 |
| `payment` | частичный уникальный индекс по `order_id WHERE status='успех'` | BR-8.1: не более одной успешной попытки |
| `order_structure` | PK `(order_id, product_id)` | BR-7.16 |
| `review` | `(order_id, entity_type, entity_id)` | BR-9.5: один отзыв на объект в заказе |

## Внешние ключи

| Дочерняя таблица | Столбцы | Родитель | Основание |
|---|---|---|---|
| `client_address` | `client_id` | `client` | BR-2.4 |
| `client_address` | `address_id` | `address` | BR-2.4, BR-3.4 |
| `restaurant` | `address_id` | `address` | BR-3.3 |
| `product` | `product_category_id` | `product_category` | BR-5.1, BR-5.7 |
| `product` | `restaurant_id` | `restaurant` | BR-5.1 |
| `courier_pay` | `courier_id` | `courier` | BR-10.1–BR-10.3 |
| `order` | `courier_id` | `courier` | BR-7.5 |
| `order` | `client_id` | `client` | BR-7.1, BR-7.2 |
| `order` | `address_id` | `address` | BR-7.4 |
| `order` | `restaurant_id` | `restaurant` | BR-7.2 |
| `order` | `(client_id, address_id)` | `client_address` | BR-7.4 |
| `payment` | `order_id` | `order` | BR-8.1 |
| `order_structure` | `order_id` | `order` | BR-7.14 |
| `order_structure` | `product_id` | `product` | BR-7.14 |
| `review` | `client_id` | `client` | BR-9.2 |
| `review` | `order_id` | `order` | BR-9.2 |

Адреса не каскадно удаляются ни через ресторан, ни через клиента: `address` остаётся самостоятельной сущностью, что выполняет BR-3.5. Каскад для `client_address` со стороны клиента удаляет только связь, не сам адрес; используемые в заказах связи защищены составным FK.

## Осознанно разрешённые NULL

| Таблица | Столбец | Основание |
|---|---|---|
| `address` | `apartment_office` | BR-3.2 |
| `restaurant` | `rating` | BR-9.7: без отзывов рейтинг NULL |
| `product` | `photo_url` | BR-5.6 |
| `product` | `rating` | BR-9.7 |
| `courier` | `dismissal_date` | BR-6.3 |
| `order` | `delivery_timestamp` | BR-7.12 до доставки |
| `review` | `photo_url` | BR-9.3 |

Остальные бизнес-атрибуты имеют `NOT NULL` в соответствии с BR-11.3. Все ID — UUID с серверным default `exts.uuid_generate_v4()` по BR-11.1.

## DEFAULT и GENERATED

| Объект | Решение | Основание |
|---|---|---|
| все одиночные ID | `DEFAULT exts.uuid_generate_v4()` | BR-11.1 |
| `courier.coefficient` | `DEFAULT 0.10` | BR-6.5 |
| timestamps создания | `DEFAULT localtimestamp` | BR-7.1, BR-8.2, BR-9.3, BR-11.2 |
| `order.status` | `DEFAULT 'создан'` | естественное начальное состояние из BR-7.7 |
| `order.pay_status` | `DEFAULT 'ожидает'` | BR-8.7 до успешной попытки |
| `order.commission` | GENERATED как 10% от `order_amount` | BR-1.4, BR-7.10 |
| `order.total_amount` | GENERATED как сумма основы и комиссии | BR-7.10 |

GENERATED-колонки исключают рассогласование трёх денежных полей и сохраняют требуемые контрактом столбцы.

## Нормализация и осознанная денормализация

Таблицы связей имеют составные ключи, а каждый неключевой атрибут зависит от полного ключа. Категория, адрес, попытка платежа, позиция заказа и выплата вынесены отдельно; транзитивных зависимостей между обычными атрибутами нет. Схема находится не ниже 3НФ.

Исключения осознанны:

- `order.commission` и `order.total_amount` — хранимые вычисляемые колонки, всегда выводимые из `order_amount` по BR-1.4 и BR-7.10;
- `product.rating` и `restaurant.rating` — агрегаты для быстрого чтения, синхронно поддерживаемые `rating_change` при INSERT/UPDATE/DELETE по BR-9.6–BR-9.7;
- `order.pay_status` — агрегат попыток оплаты, синхронно поддерживаемый триггером по BR-8.7;
- `review.entity_type + entity_id` — контрактный полиморфизм, валидируемый триггером.

`insert_test_data(n)` добавляет отдельную порцию данных. Это позволяет многократный вызов без очистки (FOOD-102); для контрольных количеств вызывается `erase_test_data()`.
