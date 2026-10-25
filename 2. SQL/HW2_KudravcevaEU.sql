-- ============================================================
-- Домашнее задание к лекции «SQL. Продвинутый»
-- Школа Аналитиков · учебная база hh_school
-- Автор: Кудрявцева Екатерина 
-- ============================================================

SET search_path TO hh_school;

-- ============================================================
-- БЛОК А
-- ============================================================

-- ЗАДАНИЕ 1
-- Проверка: звонки без response_id
SELECT COUNT(*) AS rows_cnt,
       string_agg(call_id::text, ', ' ORDER BY call_id) AS call_ids
FROM calls
WHERE response_id IS NULL;

-- Проверка: сообщения, у которых response_id не существует в responses 
SELECT COUNT(*) AS bad_messages
FROM messages m
LEFT JOIN responses r ON r.response_id = m.response_id
WHERE r.response_id IS NULL;

-- Проверка: звонки, у которых response_id не существует в responses (без тех, где response_id IS NULL, 
-- их нашла выше)
SELECT COUNT(*) AS bad_calls
FROM calls c
LEFT JOIN responses r ON r.response_id = c.response_id
WHERE c.response_id IS NOT NULL
  AND r.response_id IS NULL;

-- Проверка на согласованность идентификаторов: сравнение идентификаторов вакансии, работодателя и соискателя
-- в звонках и сообщениях с тем, что в отклике
SELECT 'calls' AS type_of_communication, COUNT(*) AS bad_rows
FROM calls c
JOIN responses r ON r.response_id = c.response_id
JOIN vacancies v ON v.vacancy_id = r.vacancy_id
WHERE c.vacancy_id <> r.vacancy_id
   OR c.employer_id <> v.employer_id
   OR c.applicant_id <> r.resume_id
UNION ALL
SELECT 'messages', COUNT(*)
FROM messages m
JOIN responses r ON r.response_id = m.response_id
JOIN vacancies v ON v.vacancy_id = r.vacancy_id
WHERE m.vacancy_id <> r.vacancy_id
   OR m.employer_id <> v.employer_id
   OR m.applicant_id <> r.resume_id;

-- Проверка: поиск событий раньше отклика и позже 7 дней (для следующих заданий)
SELECT 'calls: раньше отклика' AS problem, COUNT(*) AS rows_cnt,
       left(string_agg(c.call_id::text, ', ' ORDER BY c.call_id), 60) AS first_ids
FROM calls c
JOIN responses r ON r.response_id = c.response_id
WHERE c.call_at < r.created_at
UNION ALL
SELECT 'calls: позже 7 дней', COUNT(*),
       left(string_agg(c.call_id::text, ', ' ORDER BY c.call_id), 60)
FROM calls c
JOIN responses r ON r.response_id = c.response_id
WHERE c.call_at >= r.created_at + INTERVAL '7 days'
UNION ALL
SELECT 'messages: раньше отклика', COUNT(*),
       left(string_agg(m.message_id::text, ', ' ORDER BY m.message_id), 60)
FROM messages m
JOIN responses r ON r.response_id = m.response_id
WHERE m.sent_at < r.created_at
UNION ALL
SELECT 'messages: позже 7 дней', COUNT(*),
       left(string_agg(m.message_id::text, ', ' ORDER BY m.message_id), 60)
FROM messages m
JOIN responses r ON r.response_id = m.response_id
WHERE m.sent_at >= r.created_at + INTERVAL '7 days';

SELECT DISTINCT status FROM calls;
-- Проверка: звонки со статусом error
SELECT c.call_id, status, call_tags FROM calls c
WHERE status = 'error';

-- Проверка: звонки без длительности (если есть со статусом successful, то это ошибка в данных)
SELECT status, COUNT(*) AS calls_without_duration
FROM calls
WHERE call_duration IS NULL
GROUP BY status;

-- Проверка: сообщения без нужных ключей в message_meta
SELECT 'no_channel' AS check_name,
       COUNT(*) AS bad_rows,
       string_agg(message_id::text, ', ' ORDER BY message_id) AS message_ids
FROM messages
WHERE NOT (message_meta ? 'channel')
UNION ALL
SELECT 'no_is_read',
       COUNT(*),
       string_agg(message_id::text, ', ' ORDER BY message_id)
FROM messages
WHERE NOT (message_meta ? 'is_read')
UNION ALL
SELECT 'no_attachments',
       COUNT(*),
       string_agg(message_id::text, ', ' ORDER BY message_id)
FROM messages
WHERE NOT (message_meta ? 'attachments');

-- Анализ длительности успешных звонков
WITH successful AS (
    SELECT call_id, call_duration
    FROM calls
    WHERE status = 'successful'
),
p99 AS (
    SELECT PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY call_duration) AS p99_value
    FROM successful
)
SELECT COUNT(*) AS calls_cnt,
       ROUND(AVG(s.call_duration), 2) AS mean_sec,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY s.call_duration) AS median_sec,
       MAX(p.p99_value) AS p99_sec,
       COUNT(*) FILTER (WHERE s.call_duration > p.p99_value) AS above_p99_cnt,
       ROUND(AVG(s.call_duration) FILTER (WHERE s.call_duration <= p.p99_value), 2) AS mean_without_above_p99
FROM successful s
CROSS JOIN p99 p;

-- Звонки дольше 99-перцентиля
SELECT call_id, call_duration
FROM calls
WHERE call_duration > 890.4;

-- Вывод:

-- Во всех звонках и сообщениях вакансия, работодатель и соискатель совпадают с тем, что записано в отклике (0 расхождений), 
-- ни одно событие не произошло раньше самого отклика, а в message_meta у всех сообщений есть ключи channel, is_read и 
-- attachments.
-- Однако, в данных присутствуют следующие проблемы:
--  1) В таблице calls 8 звонков без response_id (call_id 700244–700251). Нельзя понять, к какому отклику они относятся,
--     коммуникацию по конкретному отклику по ним посчитать соответственно тоже не получится. Это влияет на дальнейший анализ, 
--     восстановить полную цепочку коммуникации с этими записями не получится,такие звонки исключаю
--  2) 1 звонок со статусом error (call_id 700163, в call_tags - technical_error). Неизвестно, состоялся ли разговор, поэтому 
--     не считаю коммуникацией, из анализа исключаю
-- Также, есть записи, где длительность у неуспешных и error-звонков пустая (NULL). Это допустимо по правилам таблицы, влияет 
-- только на атрибут длительность, но не на факт попытки звонка. Записи не исключаю

-- Для следующих заданий также проверила, какие события происходят позже первых 7 дней после отклика. 
-- Выяснила, что таких событий: 75 звонков и 886 сообщений. В запросе я показываю количество и
-- только начало списка id (первые 60), потому что полные списки очень длинные и в комментарии были бы нечитаемы. 
-- Эти события настоящие, но они вне окна "первые 7 дней", поэтому влияют на факт коммуникации, далее они будут 
-- отфильтрованы.

-- По длительности успешных звонков: таких звонков 181, среднее 467,28с, медиана 438 с, 99-й перцентиль 890,4 с. 
-- Выше него всего 2 звонка (id = 700159 длительностью 892с; id = 700199 длит. 899c). Если их убрать, среднее станет 462,49 с,
-- то есть изменится примерно на 5 секунд. Это не ошибки: 15 минут разговора с работодателем - нормальная длительность. 
-- Считаю их допустимыми выбросами: из данных не удаляю, а при описании длительности лучше смотреть на медиану

-- ============================================================
-- БЛОК Б
-- ============================================================

-- ЗАДАНИЕ 2
-- Считаю коммуникацией со стороны работодателя:
--   - сообщения, которые написал работодатель;
--   - звонки работодателя со статусом successful или unsuccessful — недозвон тоже
--     попытка связаться
-- Убираю: звонки без отклика, звонок со статусом error и всё, что вне окна 7 дней
WITH responses_base AS (
    -- отклик, работодатель и роль из вакансии
    SELECT r.response_id, r.created_at, r.status, v.employer_id, v.professional_role
    FROM responses r
    JOIN vacancies v ON v.vacancy_id = r.vacancy_id
),
employer_calls AS (
    SELECT c.response_id, c.employer_id, c.call_id AS event_id,
           c.call_at AS event_at, 'call' AS event_type
    FROM calls c
    JOIN responses_base rb ON rb.response_id = c.response_id
    WHERE c.caller_role = 'employer'
      AND c.status IN ('successful', 'unsuccessful')
      AND c.call_at >= rb.created_at
      AND c.call_at <  rb.created_at + INTERVAL '7 days'
),
employer_messages AS (
    SELECT m.response_id, m.employer_id, m.message_id AS event_id,
           m.sent_at AS event_at, 'message' AS event_type
    FROM messages m
    JOIN responses_base rb ON rb.response_id = m.response_id
    WHERE m.sender_role = 'employer'
      AND m.sent_at >= rb.created_at
      AND m.sent_at <  rb.created_at + INTERVAL '7 days'
),
events AS (
    SELECT response_id, employer_id, event_id, event_at, event_type FROM employer_calls
    UNION ALL
    SELECT response_id, employer_id, event_id, event_at, event_type FROM employer_messages
)

SELECT COUNT(*) AS total_events,
       COUNT(DISTINCT response_id) AS responses_with_comm,
       COUNT(*) FILTER (WHERE event_type = 'call') AS calls_cnt,
       COUNT(*) FILTER (WHERE event_type = 'message') AS messages_cnt
FROM events;

-- Всего откликов:
SELECT COUNT(*) FROM responses;


-- Вывод: 
-- За первые 7 дней после откликов работодатели совершили 1095 действий по 382 откликам из 628, то есть с откликами работают
-- примерно в 6 случаях из 10. Почти все совершенные действия — сообщения (988), звонков всего 107


-- ЗАДАНИЕ 3
-- Шаг 1
WITH responses_base AS (
    -- отклик, работодатель и роль из вакансии
    SELECT r.response_id, r.created_at, r.status, v.employer_id, v.professional_role
    FROM responses r
    JOIN vacancies v ON v.vacancy_id = r.vacancy_id
),
employer_calls AS (
    -- звонки работодателя
    SELECT c.response_id, c.employer_id, c.call_id::text AS event_id,
           c.call_at AS event_at, 'call' AS event_type
    FROM calls c
    JOIN responses_base rb ON rb.response_id = c.response_id
    WHERE c.caller_role = 'employer'
      AND c.status IN ('successful', 'unsuccessful')
      AND c.call_at >= rb.created_at
      AND c.call_at <  rb.created_at + INTERVAL '7 days'
),
employer_messages AS (
    -- сообщения работодателя
    SELECT m.response_id, m.employer_id, m.message_id::text AS event_id,
           m.sent_at AS event_at, 'message' AS event_type
    FROM messages m
    JOIN responses_base rb ON rb.response_id = m.response_id
    WHERE m.sender_role = 'employer'
      AND m.sent_at >= rb.created_at
      AND m.sent_at <  rb.created_at + INTERVAL '7 days'
),
events AS (
    SELECT response_id, employer_id, event_id, event_at, event_type FROM employer_calls
    UNION ALL
    SELECT response_id, employer_id, event_id, event_at, event_type FROM employer_messages
),
events_ordered AS (
    -- нумерация событий внутри отклика; при равном времени порядок: event_type, потом event_id
    SELECT e.response_id, e.employer_id, e.event_id, e.event_at, e.event_type,
           ROW_NUMBER() OVER (PARTITION BY e.response_id
                              ORDER BY e.event_at, e.event_type, e.event_id) AS event_num,
           LAG(e.event_at) OVER (PARTITION BY e.response_id
                                 ORDER BY e.event_at, e.event_type, e.event_id) AS prev_event_at,
           LEAD(e.event_type) OVER (PARTITION BY e.response_id
                                    ORDER BY e.event_at, e.event_type, e.event_id) AS next_event_type,
           COUNT(*) OVER (PARTITION BY e.response_id
                          ORDER BY e.event_at, e.event_type, e.event_id) AS comm_so_far,
           FIRST_VALUE(e.event_type) OVER (PARTITION BY e.response_id
                          ORDER BY e.event_at, e.event_type, e.event_id
                          ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS first_type,
           LAST_VALUE(e.event_type) OVER (PARTITION BY e.response_id
                          ORDER BY e.event_at, e.event_type, e.event_id
                          ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_type
    FROM events e
)

SELECT response_id, event_num, event_type, event_id, event_at,
       prev_event_at, next_event_type, comm_so_far, first_type, last_type
FROM events_ordered
ORDER BY response_id, event_num
LIMIT 20;

-- Шаг 2
WITH responses_base AS (
    -- отклик, работодатель и роль из вакансии (в responses их нет)
    SELECT r.response_id, r.created_at, r.status, v.employer_id, v.professional_role
    FROM responses r
    JOIN vacancies v ON v.vacancy_id = r.vacancy_id
),
employer_calls AS (
    -- звонки работодателя
    SELECT c.response_id, c.employer_id, c.call_id::text AS event_id,
           c.call_at AS event_at, 'call' AS event_type
    FROM calls c
    JOIN responses_base rb ON rb.response_id = c.response_id
    WHERE c.caller_role = 'employer'
      AND c.status IN ('successful', 'unsuccessful')
      AND c.call_at >= rb.created_at
      AND c.call_at <  rb.created_at + INTERVAL '7 days'
),
employer_messages AS (
    -- сообщения работодателя
    SELECT m.response_id, m.employer_id, m.message_id::text AS event_id,
           m.sent_at AS event_at, 'message' AS event_type
    FROM messages m
    JOIN responses_base rb ON rb.response_id = m.response_id
    WHERE m.sender_role = 'employer'
      AND m.sent_at >= rb.created_at
      AND m.sent_at <  rb.created_at + INTERVAL '7 days'
),
events AS (
    SELECT response_id, employer_id, event_id, event_at, event_type FROM employer_calls
    UNION ALL
    SELECT response_id, employer_id, event_id, event_at, event_type FROM employer_messages
),
events_ordered AS (
    -- нумерация события внутри отклика; при равном времени порядок: event_type, потом event_id
    SELECT e.response_id, e.employer_id, e.event_id, e.event_at, e.event_type,
           ROW_NUMBER() OVER (PARTITION BY e.response_id
                              ORDER BY e.event_at, e.event_type, e.event_id) AS event_num,
           LAG(e.event_at) OVER (PARTITION BY e.response_id
                                 ORDER BY e.event_at, e.event_type, e.event_id) AS prev_event_at,
           LEAD(e.event_type) OVER (PARTITION BY e.response_id
                                    ORDER BY e.event_at, e.event_type, e.event_id) AS next_event_type,
           COUNT(*) OVER (PARTITION BY e.response_id
                          ORDER BY e.event_at, e.event_type, e.event_id) AS comm_so_far,
           FIRST_VALUE(e.event_type) OVER (PARTITION BY e.response_id
                          ORDER BY e.event_at, e.event_type, e.event_id
                          ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS first_type,
           LAST_VALUE(e.event_type) OVER (PARTITION BY e.response_id
                          ORDER BY e.event_at, e.event_type, e.event_id
                          ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_type
    FROM events e
),
response_agg AS (
    -- сворачиваю события до одной строки на отклик
    SELECT response_id,
           COUNT(*) AS comm_cnt,
           COUNT(*) FILTER (WHERE event_type = 'call') AS call_cnt,
           COUNT(*) FILTER (WHERE event_type = 'message') AS msg_cnt,
           MIN(event_at) AS first_comm_at,
           MAX(event_type) FILTER (WHERE event_num = 1) AS first_comm_type,
           MAX(event_type) FILTER (WHERE event_num = 2) AS second_comm_type,
           MAX(last_type) AS last_comm_type,
           MAX(EXTRACT(EPOCH FROM (event_at - prev_event_at)) / 3600) AS max_gap_hours
    FROM events_ordered
    GROUP BY response_id
),
mart AS (
    SELECT rb.response_id, rb.employer_id, rb.professional_role, rb.status,
           COALESCE(a.comm_cnt, 0) AS comm_cnt,
           COALESCE(a.call_cnt, 0) AS call_cnt,
           COALESCE(a.msg_cnt, 0)  AS msg_cnt,
           a.first_comm_at, a.first_comm_type, a.second_comm_type, a.last_comm_type,
           ROUND((EXTRACT(EPOCH FROM (a.first_comm_at - rb.created_at)) / 3600)::numeric, 2) AS hours_to_first,
           ROUND(a.max_gap_hours::numeric, 2) AS max_gap_hours
    FROM responses_base rb
    LEFT JOIN response_agg a ON a.response_id = rb.response_id
)

SELECT COUNT(*) AS rows_total,
       COUNT(*) FILTER (WHERE comm_cnt > 0) AS responses_with_comm,
       COUNT(*) FILTER (WHERE comm_cnt = 0) AS responses_without_comm,
       COUNT(*) FILTER (WHERE first_comm_type = 'message') AS first_is_message,
       COUNT(*) FILTER (WHERE first_comm_type = 'call') AS first_is_call
FROM mart;

-- Вывод:
-- Всего в витрине 628 строк, из которых с коммуникацией 382 отклика и без коммуникации 246 откликов. Получается, 
-- что почти у 4 откликов из 10 за первую неделю работодатель никак не отреагировал. Сообщение в качестве первой 
-- коммуникации у 314 откликов, звонок - у 68.


-- ============================================================
-- БЛОК В
-- ============================================================

-- ЗАДАНИЕ 4
-- Беру только пары (professional_role + employer_id), у которых не меньше 8 откликов
WITH responses_base AS (
    SELECT r.response_id, r.created_at, r.status, v.employer_id, v.professional_role
    FROM responses r
    JOIN vacancies v ON v.vacancy_id = r.vacancy_id
),
employer_calls AS (
    SELECT c.response_id, c.employer_id, c.call_id::text AS event_id,
           c.call_at AS event_at, 'call' AS event_type
    FROM calls c
    JOIN responses_base rb ON rb.response_id = c.response_id
    WHERE c.caller_role = 'employer'
      AND c.status IN ('successful', 'unsuccessful')
      AND c.call_at >= rb.created_at
      AND c.call_at <  rb.created_at + INTERVAL '7 days'
),
employer_messages AS (
    SELECT m.response_id, m.employer_id, m.message_id::text AS event_id,
           m.sent_at AS event_at, 'message' AS event_type
    FROM messages m
    JOIN responses_base rb ON rb.response_id = m.response_id
    WHERE m.sender_role = 'employer'
      AND m.sent_at >= rb.created_at
      AND m.sent_at <  rb.created_at + INTERVAL '7 days'
),
events AS (
    SELECT response_id, employer_id, event_id, event_at, event_type FROM employer_calls
    UNION ALL
    SELECT response_id, employer_id, event_id, event_at, event_type FROM employer_messages
),
events_ordered AS (
    SELECT e.response_id, e.employer_id, e.event_id, e.event_at, e.event_type,
           ROW_NUMBER() OVER (PARTITION BY e.response_id
                              ORDER BY e.event_at, e.event_type, e.event_id) AS event_num,
           LAG(e.event_at) OVER (PARTITION BY e.response_id
                                 ORDER BY e.event_at, e.event_type, e.event_id) AS prev_event_at,
           LEAD(e.event_type) OVER (PARTITION BY e.response_id
                                    ORDER BY e.event_at, e.event_type, e.event_id) AS next_event_type,
           COUNT(*) OVER (PARTITION BY e.response_id
                          ORDER BY e.event_at, e.event_type, e.event_id) AS comm_so_far,
           FIRST_VALUE(e.event_type) OVER (PARTITION BY e.response_id
                          ORDER BY e.event_at, e.event_type, e.event_id
                          ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS first_type,
           LAST_VALUE(e.event_type) OVER (PARTITION BY e.response_id
                          ORDER BY e.event_at, e.event_type, e.event_id
                          ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_type
    FROM events e
),
response_agg AS (
    SELECT response_id,
           COUNT(*) AS comm_cnt,
           COUNT(*) FILTER (WHERE event_type = 'call') AS call_cnt,
           COUNT(*) FILTER (WHERE event_type = 'message') AS msg_cnt,
           MIN(event_at) AS first_comm_at,
           MAX(event_type) FILTER (WHERE event_num = 1) AS first_comm_type,
           MAX(event_type) FILTER (WHERE event_num = 2) AS second_comm_type,
           MAX(last_type) AS last_comm_type,
           MAX(EXTRACT(EPOCH FROM (event_at - prev_event_at)) / 3600) AS max_gap_hours
    FROM events_ordered
    GROUP BY response_id
),
mart AS (
    SELECT rb.response_id, rb.employer_id, rb.professional_role, rb.status,
           COALESCE(a.comm_cnt, 0) AS comm_cnt,
           COALESCE(a.call_cnt, 0) AS call_cnt,
           COALESCE(a.msg_cnt, 0)  AS msg_cnt,
           a.first_comm_at, a.first_comm_type, a.second_comm_type, a.last_comm_type,
           ROUND((EXTRACT(EPOCH FROM (a.first_comm_at - rb.created_at)) / 3600)::numeric, 2) AS hours_to_first,
           ROUND(a.max_gap_hours::numeric, 2) AS max_gap_hours
    FROM responses_base rb
    LEFT JOIN response_agg a ON a.response_id = rb.response_id
),
pairs AS (
    SELECT professional_role, employer_id,
           COUNT(*) AS responses_cnt,
           COUNT(*) FILTER (WHERE comm_cnt > 0) AS responses_with_comm,
           ROUND(100.0 * COUNT(*) FILTER (WHERE comm_cnt > 0) / COUNT(*), 1) AS share_with_comm_pct,
           ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY hours_to_first)
                  FILTER (WHERE comm_cnt > 0))::numeric, 2) AS median_hours,
           ROUND((PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY hours_to_first)
                  FILTER (WHERE comm_cnt > 0))::numeric, 2) AS p90_hours,
           ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'invited') / COUNT(*), 1) AS invite_conversion_pct
    FROM mart
    GROUP BY professional_role, employer_id
    HAVING COUNT(*) >= 8
),
ranked AS (
    SELECT p.*,
           DENSE_RANK() OVER (PARTITION BY professional_role
                              ORDER BY share_with_comm_pct DESC, median_hours ASC) AS place
    FROM pairs p
)
SELECT professional_role, place, employer_id, responses_cnt, responses_with_comm,
       share_with_comm_pct, median_hours, p90_hours, invite_conversion_pct
FROM ranked
WHERE place <= 2
ORDER BY professional_role, place, employer_id;

-- Вывод:

-- professional_role, место и employer_id для всех строк итогового результата: 
-- Разработчик: 1 - 112, 2 - 104
-- Тестировщик: 1 - 107, 2 - 108
-- Аналитик данных: 1 - 109, 2 - 103
-- Продуктовый аналитик: 1 - 103, 2 - 102
-- Дата-инженер: 1 - 106, 2 - 101

-- Всего получилось 10 строк (по 2 места в каждой из 5 ролей), одинаковых мест нет. Сильнее всего с откликами
-- работают работодатель 109 среди аналитиков данных (на 89,5% откликов есть реакция) и 107 среди тестировщиков
-- (88,2%). Самый быстрый — работодатель 108 у тестировщиков: половина его реакций приходит в первые 5,67 часа,
-- но у него всего 8 откликов, поэтому однозначный вывод сделать нельзя. Важно, что высокая доля
-- реакций не гарантирует высокой конверсии в приглашение: у 109 в приглашение превращаются 15,8% откликов,
-- а у 107 — 41,2%. Самой высокой конверсией выделаются тестировщики (37,5% и 41,2% против 10–20% у остальных).


-- ЗАДАНИЕ 5
-- Беру все сообщения (и соискателя, и работодателя), через LAG смотрю на предыдущее
-- сообщение в этом же отклике. Если сообщение от работодателя, а предыдущее было от соискателя — это ответ
WITH messages_7d AS (
    SELECT m.message_id, m.response_id, m.employer_id, m.sender_role, m.sent_at
    FROM messages m
    JOIN responses r ON r.response_id = m.response_id
    WHERE m.sent_at >= r.created_at
      AND m.sent_at <  r.created_at + INTERVAL '7 days'
),
with_prev AS (
    SELECT message_id, response_id, employer_id, sender_role, sent_at,
           LAG(sender_role) OVER (PARTITION BY response_id ORDER BY sent_at, message_id) AS prev_sender,
           LAG(sent_at)     OVER (PARTITION BY response_id ORDER BY sent_at, message_id) AS prev_sent_at
    FROM messages_7d
),
answers AS (
    SELECT employer_id,
           EXTRACT(EPOCH FROM (sent_at - prev_sent_at)) / 3600 AS answer_hours
    FROM with_prev
    WHERE sender_role = 'employer'
      AND prev_sender = 'applicant'
)
SELECT employer_id,
       COUNT(*) AS answers_cnt,
       ROUND(AVG(answer_hours)::numeric, 2) AS mean_hours,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY answer_hours)::numeric, 2) AS median_hours,
       ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY answer_hours)::numeric, 2) AS p90_hours
FROM answers
GROUP BY employer_id
ORDER BY median_hours ASC, employer_id;


-- Общее количество найденных ответов
WITH messages_7d AS (
    SELECT m.message_id, m.response_id, m.employer_id, m.sender_role, m.sent_at
    FROM messages m
    JOIN responses r ON r.response_id = m.response_id
    WHERE m.sent_at >= r.created_at
      AND m.sent_at <  r.created_at + INTERVAL '7 days'
),
with_prev AS (
    SELECT message_id, response_id, employer_id, sender_role, sent_at,
           LAG(sender_role) OVER (PARTITION BY response_id ORDER BY sent_at, message_id) AS prev_sender,
           LAG(sent_at)     OVER (PARTITION BY response_id ORDER BY sent_at, message_id) AS prev_sent_at
    FROM messages_7d
)
SELECT COUNT(*) AS total_answers
FROM with_prev
WHERE sender_role = 'employer'
  AND prev_sender = 'applicant';


-- Вывод:
-- Всего ответов работодателей на сообщение соискателя 749. Минимальная медиана у employer_id = 107: 3,93 часа.
--
-- Когда соискатель сам пишет в чат, работодатели отвечают довольно быстро и примерно одинаково: у всех 11
-- работодателей медиана ответа лежит между 3,9 и 4,9 часа, а 90% ответов приходят не позже примерно 20 часов с момента отправки сообщения.
-- Самый быстрый — работодатель 107 (3,93 ч). Любопытно, что между работодателями в ответах разница гораздо меньше, 
-- чем в скорости первой реакции на отклик: в диалоге они ведут себя похоже, а отличаются тем, вступают ли они в диалог вообще

-- ============================================================
-- БЛОК Г
-- ============================================================

-- ЗАДАНИЕ 6
-- 6.1
-- Проверка тегов: successful - есть тег connected, unsuccessful — есть тег no_answer; error — есть тег technical_error.
WITH responses_base AS (
    SELECT r.response_id, r.created_at, r.status, v.employer_id, v.professional_role
    FROM responses r
    JOIN vacancies v ON v.vacancy_id = r.vacancy_id
),
employer_calls AS (
    SELECT c.response_id, c.employer_id, c.call_id::text AS event_id,
           c.call_at AS event_at, 'call' AS event_type
    FROM calls c
    JOIN responses_base rb ON rb.response_id = c.response_id
    WHERE c.caller_role = 'employer'
      AND c.status IN ('successful', 'unsuccessful')
      AND c.call_at >= rb.created_at
      AND c.call_at <  rb.created_at + INTERVAL '7 days'
),
employer_messages AS (
    SELECT m.response_id, m.employer_id, m.message_id::text AS event_id,
           m.sent_at AS event_at, 'message' AS event_type
    FROM messages m
    JOIN responses_base rb ON rb.response_id = m.response_id
    WHERE m.sender_role = 'employer'
      AND m.sent_at >= rb.created_at
      AND m.sent_at <  rb.created_at + INTERVAL '7 days'
),
events AS (
    SELECT response_id, employer_id, event_id, event_at, event_type FROM employer_calls
    UNION ALL
    SELECT response_id, employer_id, event_id, event_at, event_type FROM employer_messages
),
calls_checked AS (
    SELECT c.call_id, c.call_tags,
           CASE WHEN c.status = 'successful' AND 'connected' = ANY(c.call_tags) THEN 1
                WHEN c.status = 'unsuccessful' AND 'no_answer' = ANY(c.call_tags) THEN 1
                WHEN c.status = 'error' AND 'technical_error' = ANY(c.call_tags) THEN 1
                ELSE 0 END AS is_consistent
    FROM events e
    JOIN calls c ON c.call_id::text = e.event_id
    WHERE e.event_type = 'call'
),
valid_calls AS (
    -- у каждого валидного звонка считаю, сколько у него бизнес-тегов
    SELECT call_id,
           ('screening' = ANY(call_tags))::int AS is_screening,
           ('interview' = ANY(call_tags))::int AS is_interview,
           ('follow_up' = ANY(call_tags))::int AS is_follow_up,
           ('details'   = ANY(call_tags))::int AS is_details
    FROM calls_checked
    WHERE is_consistent = 1
)
SELECT (SELECT COUNT(*) FROM calls_checked) AS calls_checked,
       COUNT(*) AS valid_calls,
       SUM(is_screening) AS screening,
       SUM(is_interview) AS interview,
       SUM(is_follow_up) AS follow_up,
       SUM(is_details)   AS details,
       COUNT(*) FILTER (WHERE is_screening + is_interview + is_follow_up + is_details >= 1) AS with_business_tag,
       ROUND(AVG(is_screening + is_interview + is_follow_up + is_details), 2) AS avg_business_tags_per_call
FROM valid_calls;

-- Вывод:
-- В анализ входят 107 звонков работодателя со статусами successful и unsuccessful. Error-звонок 700163 в анализ не входит
-- по решению задания 1 (технический сбой, не факт коммуникации).
-- Все 107 звонков слоя согласованы со своими тегами: противоречий между статусом и техническими тегами нет, 
-- поэтому valid_calls = 107.
--
-- Бизнес-теги распределены следующим образом: screening 25, interview 30, follow_up 29, details 23.
-- У каждого звонка ровно один бизнес-тег (среднее 1,00), и хотя бы один бизнес-тег есть у всех 107 валидных звонков.
-- Недозвоны (no_answer) остались в выборке: данные у них согласованные, просто разговор не состоялся.


-- 6.2
-- Признак прочтения лежит в ключе is_read. Если канала нет, сообщение попадает в группу «не указан».
WITH employer_msgs AS (
    SELECT m.message_id,
           COALESCE(m.message_meta ->> 'channel', 'не указан') AS channel,
           (m.message_meta ->> 'is_read')::boolean AS is_read,
           COALESCE(jsonb_array_length(m.message_meta -> 'attachments'), 0) AS attachments_cnt
    FROM messages m
    JOIN responses r ON r.response_id = m.response_id
    WHERE m.sender_role = 'employer'
      AND m.sent_at >= r.created_at
      AND m.sent_at <  r.created_at + INTERVAL '7 days'
)
SELECT channel,
       COUNT(*) AS messages_cnt,
       COUNT(is_read) AS read_flag_known,
       COUNT(*) FILTER (WHERE is_read = FALSE) AS unread_cnt,
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_read = FALSE) / NULLIF(COUNT(is_read), 0), 1) AS unread_share_pct,
       COUNT(*) FILTER (WHERE attachments_cnt >= 1) AS with_attachment_cnt,
       ROUND(100.0 * COUNT(*) FILTER (WHERE attachments_cnt >= 1) / COUNT(*), 1) AS attachment_share_pct
FROM employer_msgs
GROUP BY channel
ORDER BY channel;

-- Вывод:
-- mobile_app: сообщений 360; флаг прочтения известен у 360; не прочитано 36 (10,0%); с вложением 14 сообщений (3,9%).
-- web: сообщений 628; флаг прочтения известен у 628; не прочитано 52 (8,3%); с вложением 25 (4,0%).
-- Группы "не указан" нет (0 сообщений): канал в этих данных заполнен везде, но запрос это учитывает

-- Через канал web идёт примерно две трети сообщений работодателей (628 из 988), через мобильное приложение — треть
-- (360). Не прочитанными остаются 8–10% сообщений, в приложении чуть чаще (10,0% против 8,3%), но разница
-- небольшая. Вложения встречаются редко, примерно в 4% сообщений, и от канала не зависят

-- ============================================================
-- БЛОК Д
-- ============================================================

-- ЗАДАНИЕ 7
-- Сравниваю две группы: invited и other.
--
-- Гипотеза 1. Приглашенным соискателям работодатель отвечает чаще и быстрее.
-- Что проверяю: долю откликов, где была коммуникация; медиану часов до первой коммуникации.
-- Гипотеза подтверждается, если у invited доля выше и медиана хотя бы на 20% меньше
--
-- Гипотеза 2. С приглашенными общаются больше: больше контактов, чаще бывает звонок, 
-- паузы короче, и соискатель чаще отвечает.
-- Что проверяю: среднее число коммуникаций на отклик с коммуникацией; долю откликов со звонком
-- среди откликов с коммуникацией; медиану максимальной паузы между коммуникациями, часы;
-- долю откликов среди откликов с коммуникацией, где соискатель сам написал сообщение в первые 7 дней.
-- Гипотеза подтверждается, если все четыре показателя сдвинуты в пользу invited.


WITH responses_base AS (
    SELECT r.response_id, r.created_at, r.status, v.employer_id, v.professional_role
    FROM responses r
    JOIN vacancies v ON v.vacancy_id = r.vacancy_id
),
employer_calls AS (
    SELECT c.response_id, c.employer_id, c.call_id::text AS event_id,
           c.call_at AS event_at, 'call' AS event_type
    FROM calls c
    JOIN responses_base rb ON rb.response_id = c.response_id
    WHERE c.caller_role = 'employer'
      AND c.status IN ('successful', 'unsuccessful')
      AND c.call_at >= rb.created_at
      AND c.call_at <  rb.created_at + INTERVAL '7 days'
),
employer_messages AS (
    SELECT m.response_id, m.employer_id, m.message_id::text AS event_id,
           m.sent_at AS event_at, 'message' AS event_type
    FROM messages m
    JOIN responses_base rb ON rb.response_id = m.response_id
    WHERE m.sender_role = 'employer'
      AND m.sent_at >= rb.created_at
      AND m.sent_at <  rb.created_at + INTERVAL '7 days'
),
events AS (
    SELECT response_id, employer_id, event_id, event_at, event_type FROM employer_calls
    UNION ALL
    SELECT response_id, employer_id, event_id, event_at, event_type FROM employer_messages
),
events_ordered AS (
    SELECT e.response_id, e.employer_id, e.event_id, e.event_at, e.event_type,
           ROW_NUMBER() OVER (PARTITION BY e.response_id
                              ORDER BY e.event_at, e.event_type, e.event_id) AS event_num,
           LAG(e.event_at) OVER (PARTITION BY e.response_id
                                 ORDER BY e.event_at, e.event_type, e.event_id) AS prev_event_at,
           LEAD(e.event_type) OVER (PARTITION BY e.response_id
                                    ORDER BY e.event_at, e.event_type, e.event_id) AS next_event_type,
           COUNT(*) OVER (PARTITION BY e.response_id
                          ORDER BY e.event_at, e.event_type, e.event_id) AS comm_so_far,
           FIRST_VALUE(e.event_type) OVER (PARTITION BY e.response_id
                          ORDER BY e.event_at, e.event_type, e.event_id
                          ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS first_type,
           LAST_VALUE(e.event_type) OVER (PARTITION BY e.response_id
                          ORDER BY e.event_at, e.event_type, e.event_id
                          ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_type
    FROM events e
),
response_agg AS (
    SELECT response_id,
           COUNT(*) AS comm_cnt,
           COUNT(*) FILTER (WHERE event_type = 'call') AS call_cnt,
           COUNT(*) FILTER (WHERE event_type = 'message') AS msg_cnt,
           MIN(event_at) AS first_comm_at,
           MAX(event_type) FILTER (WHERE event_num = 1) AS first_comm_type,
           MAX(event_type) FILTER (WHERE event_num = 2) AS second_comm_type,
           MAX(last_type) AS last_comm_type,
           MAX(EXTRACT(EPOCH FROM (event_at - prev_event_at)) / 3600) AS max_gap_hours
    FROM events_ordered
    GROUP BY response_id
),
mart AS (
    SELECT rb.response_id, rb.employer_id, rb.professional_role, rb.status,
           COALESCE(a.comm_cnt, 0) AS comm_cnt,
           COALESCE(a.call_cnt, 0) AS call_cnt,
           COALESCE(a.msg_cnt, 0)  AS msg_cnt,
           a.first_comm_at, a.first_comm_type, a.second_comm_type, a.last_comm_type,
           ROUND((EXTRACT(EPOCH FROM (a.first_comm_at - rb.created_at)) / 3600)::numeric, 2) AS hours_to_first,
           ROUND(a.max_gap_hours::numeric, 2) AS max_gap_hours
    FROM responses_base rb
    LEFT JOIN response_agg a ON a.response_id = rb.response_id
),
applicant_replies AS (
    -- сколько сообщений написал соискатель в первые 7 дней
    SELECT m.response_id, COUNT(*) AS applicant_msgs
    FROM messages m
    JOIN responses_base rb ON rb.response_id = m.response_id
    WHERE m.sender_role = 'applicant'
      AND m.sent_at >= rb.created_at
      AND m.sent_at <  rb.created_at + INTERVAL '7 days'
    GROUP BY m.response_id
),
responses_ext AS (
    SELECT mt.response_id, mt.status, mt.comm_cnt, mt.call_cnt, mt.hours_to_first, mt.max_gap_hours,
           COALESCE(ar.applicant_msgs, 0) AS applicant_msgs
    FROM mart mt
    LEFT JOIN applicant_replies ar ON ar.response_id = mt.response_id
)
SELECT CASE WHEN status = 'invited' THEN 'invited' ELSE 'other' END AS grp,
       COUNT(*) AS responses_cnt,
       COUNT(*) FILTER (WHERE comm_cnt > 0) AS responses_with_comm,
       ROUND(100.0 * COUNT(*) FILTER (WHERE comm_cnt > 0) / COUNT(*), 1) AS share_with_comm_pct,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY hours_to_first))::numeric, 1) AS median_hours_to_first,
       ROUND(AVG(comm_cnt) FILTER (WHERE comm_cnt > 0), 2) AS avg_comm_per_response,
       ROUND(100.0 * COUNT(*) FILTER (WHERE call_cnt > 0)
             / COUNT(*) FILTER (WHERE comm_cnt > 0), 1) AS share_with_call_pct,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY max_gap_hours))::numeric, 1) AS median_max_gap_hours,
       ROUND(100.0 * COUNT(*) FILTER (WHERE comm_cnt > 0 AND applicant_msgs > 0)
             / COUNT(*) FILTER (WHERE comm_cnt > 0), 1) AS share_applicant_replied_pct
FROM responses_ext
GROUP BY CASE WHEN status = 'invited' THEN 'invited' ELSE 'other' END
ORDER BY grp;


-- Результаты (invited/other):
--   откликов: 92 / 536; из них с коммуникацией: 54 / 328
--   доля с коммуникацией: 58,7% / 61,2%
--   медиана часов до первой коммуникации: 51,1 / 54,7
--   среднее число коммуникаций: 2,78 / 2,88
--   доля откликов со звонком: 27,8% / 26,5%
--   медиана максимальной паузы, ч: 24,1 / 24,5
--   соискатель ответил: 87,0% / 90,5%
--
-- Гипотеза 1 - не подтвердилась. У приглашенных коммуникация бывает даже чуть реже (58,7% против 61,2%),
-- а первая реакция приходит быстрее лишь на 3,6 часа (51,1 против 54,7 ч, то есть примерно на 7%), это
-- совсем незначительная разница. К тому же в группе invited всего 54 отклика с коммуникацией, и такая небольшая
-- разница вполне может быть случайной
-- Гипотеза 2 - не подтвердилась Среднее число коммуникаций у приглашённых даже чуть ниже (2,78 против 2,88),
-- пауза практически такая же (24,1 против 24,5 ч), соискатель отвечает не чаще, а реже (87,0% против 90,5%).
-- Единственная метрика в пользу invited — доля откликов со звонком, но разница всего 1,3 процентного пункта
--
-- Следовательно, отклики со статусом invited по тому, как работодатель общается в первую неделю, 
-- почти не отличаются от остальных. Значит, по этим показателям нельзя заранее сказать, что отклик закончится 
-- приглашением. Решение, скорее всего, зависит от других вещей (насколько кандидат подходит, какая вакансия), 
-- которые не входили в текущий анализ. 


-- ЗАДАНИЕ 8

-- Работодатели обрабатывают отклики неоднородно и в основном письменно: за 7 дней коммуникация была по 382 из 628 откликов 
-- (60,8%), из 1095 действий 988 — сообщения и только 107 — звонки; 246 откликов (39,2%) остались без ответа. Внутри диалога 
-- работодатели отвечают быстро и однородно (медиана 3,9–4,9 ч), а первая реакция на отклик приходит заметно позже (медиана 
-- 31–76 ч у большинства из рейтинга). Различия между работодателями и ролями велики:
-- среди работодателей из рейтинга доля обработанных откликов варьируется от 45,8% до 89,5%, а конверсия в приглашение у 
-- тестировщиков 37,5–41,2% против 10–20% в других ролях; при этом сообщения технически нормальны — непрочитанных 8–10%, 
-- теги согласованы со статусами. С приглашением скорость и количество контактов наблюдаемо не связаны: 58,7% против 61,2% по доле
-- с коммуникацией и 51,1 против 54,7ч по медиане, но это не доказывает отсутствия причинной связи — мешают окно 7 дней, отсутствие 
-- данных о кандидатах и малые группы. Ограничения: вне анализа остались 75 звонков и 886 сообщений, 8 звонков без отклика, 1 error-звонок; 
-- в группе приглашённых только 54 отклика с коммуникацией. Практический вывод: точка роста — не скорость ответов в диалоге,
-- а скорость первой реакции и 39% откликов без ответа. Следующий вопрос: связана ли задержка первой реакции (до/после 24 ч) 
-- с продолжением диалога и статусом — внутри одной пары «роль — работодатель»?
 
 
  