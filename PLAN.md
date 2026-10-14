# active_model.cr — порт ActiveModel 8.1.4 + рефакторинг компонентов

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

Оригинал: гем `activemodel 8.1.4` (локально: `~/.rvm/gems/ruby-3.4.5/gems/
activemodel-8.1.4`, исходники и test-suite доступны). Это единственный из 11
гемов rails/rails, у которого в CRails нет порта: его функциональность сейчас
вшита в `active_record.cr`, а «модельный слой без БД» (form objects) не
существует вовсе.

## Цель

1. `ActiveModel` 1:1 к 8.1.4: неймспейс, модули, API.
2. Высвободить из `active_record.cr` общеслойный код (валидации, Errors,
   dirty, callbacks-машина) в `active_model.cr`; AR включает AM, как в
   оригинале (activerecord зависит от activemodel, не содержит его).
3. Интегрировать AM в компоненты, где оригинал на него опирается:
   devise, active_storage, action_text, action_view (form objects).
4. Публичный API AR/компонентов НЕ меняется (контракты!): все существующие
   оракул-спеки остаются зелёными без правок.

## Правило (AGENTS.md): oracle-first

Любое переписывание 1:1 начинается с интеграционных кейсов:

- [x] `oracle/cases.rb` — синтетические кейсы на настоящем activemodel
      8.1.4 (ruby 3.4.5): Naming/Conversion/Translation, Model,
      AttributeAssignment, Validations (все builtin-валидаторы + контексты
      + EachValidator), Errors (агрегация, details, nested), Dirty,
      Callbacks, Serialization (JSON), SecurePassword, Type (registry +
      кастинг), ForbiddenAttributesProtection, Access.
      Формат `case_id\tvalue` → `expected.yml` — снято, 127 кейсов,
      детерминизм подтверждён двумя прогонами; API-сигнатуры сверены
      пробой (quirks зафиксированы в шапке cases.rb).
- [x] test-suite гема вендорен: `oracle/rails-tests/activemodel/` —
      18 файлов с тега rails/rails v8.1.4 (naming/model/validations/
      errors/error/nested_error/dirty/callbacks/secure_password/
      serialization/type/lint/attribute/attributes/access/api/
      attribute_assignment/conversion + helper.rb; гем lib-only).
      Исходники гема: `oracle/vendor/activemodel-8.1.4/` (508K).
      Портирование кейсов в Crystal-спеки — итерации 1–2; обе версии
      проходят одни и те же кейсы без изменения тестов.
- [ ] Реверс-проверки `oracle/verify_*.rb` (Process.run из спека —
      паттерн active_support.cr/spec/crypto_oracle_spec.cr) — добавить
      при написании спеки (итерация 1).

## Что переносится (маппа модулей gem → шард)

| Гем 8.1.4 | В CRails сейчас | Куда |
|---|---|---|
| `Validations` + `validations/*.rb` + `validator.rb` (EachValidator) | `active_record.cr/src/validations.cr` (макросы `validates`/`validate`, `__run_validations`, i18n-рендер) | `AM::Validations` — перенос + генерализация |
| `UniquenessValidator` | внутри AR-валидаций | **остаётся в AR** (в Rails это ActiveRecord::Validations::UniquenessValidator — нужен запрос к БД) |
| `Errors` + `error.rb`/`nested_error.rb` | `class ActiveRecord::Errors` (persistence.cr:478) | `AM::Errors` (lazy/nested — по возможностям оригинала, сверяем oracle'ом) |
| `Dirty` (attribute_mutation_tracker) | размазан по base.cr/persistence.cr/associations.cr | `AM::Dirty`; AR включает и расширяет (saved_changes — AR-специфика, остаётся в AR) |
| `Callbacks` (машина define_callbacks) | callbacks.cr — AR-специфичные `__run_before_save` и т.д. | `AM::Callbacks` —通用 машина; AR-макросы (`before_save`…) остаются в AR, но собираются поверх |
| `Naming` / `Conversion` / `Translation` | нет нигде | новые `AM::Naming` (model_name/param_key/i18n_scope), `AM::Conversion` (to_key/to_param), `AM::Translation` (human_attribute_name) |
| `Model` / `API` | нет (form objects взять неоткуда) | `AM::Model` + `AM::API`: include-набор для класса без БД |
| `Attributes` + `Type` (+ registry) | атрибуты — от схемы БД (schema.cr) | `AM::Attributes`/`AM::Type`: декларативные `attribute` + кастинг для не-DB моделей; AR свою схему сохраняет |
| `SecurePassword` | нет (devise варит свой bcrypt) | `AM::SecurePassword` (`has_secure_password`, bcrypt-шард) |
| `Serialization` / `Serializers::JSON` | нет | `AM::Serialization` (as_json/readwrite-минимум 1:1) |
| `ForbiddenAttributesProteсtion` | strong params в action_pack | `AM::ForbiddenAttributesProtection` (контракт sanitize_for_mass_assignment) |
| `Access` (`#attributes`-хэш протокол) | `attributes` в AR от схемы | `AM::Access` для не-DB моделей |
| `Lint` (контрактные тесты) | нет | `AM::Lint::Tests` — спека-проверка контракта (наш принцип «модуль-интерфейс») |

Не переносим (out of scope): `activemodel-serializers-xml` (устаревший
отдельный гем), ActiveModel::Serializers (AMS — отдельный гем), railtie
(в Crystal не нужен), deprecator.

## Рефакторинг active_record.cr (главный объём)

1. `shard.yml`: + зависимость `active_model_cr: path: ../active_model.cr`.
2. `ActiveRecord::Base` включает `ActiveModel::Model`-набор (Naming,
   Conversion, Translation, Validations, Dirty, Callbacks, Errors,
   Access) — как `ActiveRecord::Base < ActiveRecord::Model` в оригинале
   схемно (в Crystal — include, не наследование: наш стандарт).
3. Перенос `validations.cr` → AM: макросы генерят те же скрытые методы
   (`validation__<col>__<n>`, диспетчер `__run_validations`); AR-часть —
   только uniqueness/associated + вызовы из persistence (`save(valid:)`).
4. `Errors` переезжает в AM с сохранением текущего wire-формата
   (details/messages/full_messages) — оракулы devise (145/145) и AR
   (283/283+) это тут же проверят.
5. Dirty: общая часть (изменения атрибутов) в AM; `saved_changes`,
   transaction-перенос — в AR.
6. `has_secure_token` остаётся в AR (в Rails это ActiveRecord::SecureToken).

Критерий: ни один существующий спек AR/devise не меняется и остаётся зелёным.

## Интеграция в компоненты

### devise.cr (фаза после AR-рефакторинга)
- `models.cr:163–191` (рукописные `errors.add(:too_short/…)` внутри
  макроса `devise`) → модуль `validatable` поверх AM-валидаторов
  (`validates_presence_of :email`, `validates_confirmation_of`, length…),
  как в гем-оригинале. Uniqueness-валидатор devise (запрос к БД) остаётся
  devise-шным, но в терминах контракта.
- Реопен `class ActiveRecord::Base` (models.cr:20, models_p1.cr,
  omniauth.cr) → макрос `devise` на классе модели; ORM-агностичность
  (в оригинале devise работает с любым ActiveModel-совместимым классом)
  — P2: требует контракта orm-адаптера, фиксируем как цель, не делаем.
- `Encryptor` НЕ трогаем — это честный 1:1 порт модуля самого гема.

### active_storage.cr / action_text.cr
- `attached.cr` / `rich_text.cr` реопенят `ActiveRecord::Base`; в
  оригинале оба гема зависят от activemodel. Минимальный шаг: у записей
  используются `AM::Naming` (полиморфные `record_gid`/`to_key`), модельная
  часть (Blob/RichText) — через AM-слой AR. Без изменения API.

### action_view.cr
- FormBuilder: сейчас заточен под AR. Добавить поддержку любых моделей с
  контрактом AM (`model_name`, `to_param`, `errors` поверх AM::Errors) —
  form objects (`include ActiveModel::Model`) начинают работать в
  `form_with`. Новая фича — отдельный oracle-набор кейсов с настоящим
  actionview 8.1.4 + AM 8.1.4.

### action_pack.cr
- `ForbiddenAttributesProtection`: связка strong params ↔ mass-assignment
  через AM-контракт (в оригинале `ActiveModel::ForbiddenAttributesProtected`).
  Проверить текущую реализацию permit — при необходимости свести к
  контракту, не меняя поведение.

## Порядок работ

- **Итерация 0** — оракул (по AGENTS.md, до кода): cases.rb + выборка
  test-suite гема → expected.yml; критерий — прогоняемость на Ruby.
  ✅ Сделано (127 кейсов, детерминизм 2 прогонами).
- **Итерация 1** — ядро: Naming, Conversion, Translation, Access,
  AttributeAssignment, Errors, Validations (перенос из AR), Model/API,
  SecurePassword. Спек = оракул 1:1. ✅ Сделано.
- **Итерация 2** — Dirty, Callbacks (машина), Serialization, Type/
  Attributes (минимум для form objects), Lint. ✅ Сделано (кроме Lint —
  перенесён в итерацию 2' вместе с реверс-проверками; спека
  `spec/oracle_spec.cr` 127/127 зелёная).
- **Итерация 3** — рефакторинг active_record.cr на AM; все сюиты AR
  зелёные; devise 145/145 зелёный.
- **Итерация 4** — devise.cr validatable на AM; attached/rich_text на
  AM-контракт; form objects в action_view (oracle-actionview).
- **Итерация 5** — README (сравнение фич с activemodel 8.1.4, англ.),
  репозиторий по конвенции myshards (initial commit + push), симлинк в
  rails.cr, обновление таблицы в корневом README.

## Архитектура DSL (итог итераций 1–2; проверено репро и оракулом)

`macro finished` в Crystal 1.21 НЕ срабатывает для включающих классов —
вся генерация per-class построена на previous_def-цепочках:

- **Посадка баз** — first-use guard в каждом DSL-макросе
  (`{% unless @type.methods.any? { |m| m.name.stringify == "..." } %}`)
  вызывает посадочный макрос (`__plant_attribute_bases`,
  `__plant_validation_base`); для DSL-less моделей те же базы сажает
  `macro included` в API/Model (он же сажает `self.model_name`/
  `self.human_attribute_name`; вложенные include хуки не ре-файрят,
  поэтому хук продублирован в API и Model).
- **Цепочки** — каждый DSL-вызов генерирует def с `previous_def` первым
  (порядок объявления = порядок выполнения): `__attribute_names`/
  `__attribute?`/`__write_attribute`/`__attribute_default`,
  `__run_validations`, `__serializable_extra`, `run_callbacks`.
- **Around-колбэки** — previous_def запрещён в proc-литералах, поэтому
  runtime-реестр: класс-переменная `@@__cb_around_<kind>` с
  `Proc(self, Proc(Nil), Nil)`, рекурсивный `__cb_around_step_<kind>`
  (первый зарегистрированный around = внешний); before/after — цепочки.
- **Dirty** — класс-цепочки затеняют модульные методы, поэтому Dirty не
  переопределяет `__write_attribute`, а даёт `__dirty_track_write`,
  вызываемый из writer-цепочки attribute-макроса, когда Dirty в
  ancestors (там же генерируются `<attr>_was/_changed?/…`).

## Риски / Crystal-специфика (проверенные факты 1.21)

- **`macro finished` не срабатывает для включающих классов** — главный
  факт, определивший архитектуру (см. выше).
- **`previous_def` не видит методы модулей** — только предыдущие def в
  том же классе; предыдущий вызов должен повторять аргументы и блок:
  `previous_def(kind, &block)`.
- **Нетипизированный captured-block всегда возвращает Nil** (`&b` +
  `b.call`) — в спеках использовать `yield` (оракул-зеркало вычисляет
  кейсы eagerly через `yield`, как case_run в Ruby).
- **`{{sym.stringify}}` на SymbolLiteral даёт ":name" с двоеточием** —
  в строковых позициях всегда `{{x.id.stringify}}`; интерполяция
  SymbolLiteral в `:"{{...}}"` тоже даёт лишнее двоеточие — брать
  `{{x.id}}`.
- **Динамические Symbol из строк не существуют** — Errors хранит
  `attribute : String` + `attribute_sym : Symbol?`; symbol-ключевые
  `details`/`attribute_names`/`as_json` пропускают string-added ошибки.
- **Рекурсивный алиас `Value` не унифицируется со своим расширением** —
  литералы `[x, y]`/`{"k" => v}` выводятся во flattened-union и не
  совпадают с `Array(Value)`/`Hash(String, Value)`: собирать через
  `Array(Value).new` + `<<`, `of String => ActiveModel::Value`; Tuple
  с элементом-алиасом нельзя деструктурировать в блоке.
- **`initialize` из косвенно включённого модуля не попадает в overloads
  `new`** — дублируется в API и Model.
- **Макросы включённых модулей не резолвятся на внешних вызовах
  инстанса** (`obj.slice(...)` из Access) — обычные методы поверх
  `attributes`.
- **Внутри `module Type` имя `String` резолвится в `Type::String`** — в
  case-ветвлениях кастов использовать `::String`.
- `Float64#truncate` → `trunc`; `Hash#sort_by` отсутствует — `to_a`+sort;
  голый вызов `it id { ... }` парсит блок прилипшим к `id` — писать
  `it(id) { ... }`.
- Методы класса не наследуются через include → `self.model_name` сажается
  хуками API/Model; класс-переменные per-type (у сабкласса своя копия).
- ForbiddenAttributesProtection включать ПОСЛЕ AttributeAssignment
  (last include wins; его `__sanitize`-перегрузки заменяют generic
  fallback из AA — задокументировано в spec-модели Prot).
- Остальное как раньше: i18n-рендер поверх I18n из active_support.cr;
  циклозависимости только AM→AS и AR→AM(+AS); bcrypt уже в devise.cr.
- Захваченный блок (`&block`) — только `block.call`, не `yield` (но def
  с `&inner` может `yield`).

## Открытые вопросы (решить на итерации 0)

- Объём переноса test-suite гема (полный vs выборка) — по времени прогона.
- Форма контракта orm-агностичности для devise (P2) — зафиксировать
  интерфейс, реализацию отложить.
