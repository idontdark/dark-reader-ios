# Проверка книжных API (7 ноября 2026)

Проверки выполнены с GitHub Actions runner, а не только по документации.
Скрипт: `scripts/check_catalogs.py`.
Workflow: `.github/workflows/catalog-check.yml`.
Для повтора: Actions → Check catalog APIs → Run workflow.

## Флибуста (OPDS 1.x)
- HTTPS: `https://flibusta.is/opds` — 200, XML Atom, OpenSearch-подсказки.
- По названию: `https://flibusta.is/opds/search?searchType=books&searchTerm=...`
- По автору: `https://flibusta.is/opds/search?searchType=authors&searchTerm=...`
- Поиск по автору выдаёт разделы авторов; надо открыть нужного автора, затем книгу.
- Запрос `Дубровский`: HTTP 200, 12 записей, 22 ссылки на EPUB и FB2.
- Проверка `https://flibusta.is/b/253788/epub/opds`: HTTP 206 (Range) с сигнатурой ZIP `PK`. Файл целиком не загружали.
- `https://flub.flibusta.is/opds/search?searchTerm=...` также отвечал 200, но не используется по умолчанию.
- Доступность источника зависит от страны и сети, нет официальной гарантии работоспособности. Не обходить DRM или ограничения правообладателей.

## Project Gutenberg (официальный OPDS)
- `https://www.gutenberg.org/ebooks/search.opds/` — 200, Atom.
- `https://www.gutenberg.org/ebooks/search.opds/?query=austen` — один тест 200 с каталогом книг, другой сетевой сбой.
- Карточка `https://www.gutenberg.org/ebooks/1342.opds` — 200, содержит несколько `application/epub+zip` ссылок, в т. ч. `https://www.gutenberg.org/ebooks/1342.epub.noimages`.
- Для скачивания сначала открывается карточка книги OPDS. Отдельная загрузка EPUB ещё не проверена на iPhone.
- Официальный каталог: https://www.gutenberg.org/ebooks/offline_catalogs.html

## Gutendex (JSON для Gutenberg)
- Документация: https://gutendex.com/
- `https://gutendex.com/books/?search=pride` — HTTP 200, 32 записи, 29 EPUB-ссылок в одном тесте.
- Другие запросы завершились тайм-аутом или HTTP 403. Нестабильный источник; в приложении используется только как дополнительный выбор. Для долгосрочного использования автор рекомендует самостоятельный сервер.
- Прямое скачивание EPUB через Gutendex-кандидат не подтверждено в повторном тесте, поскольку повторный поиск получил 403.

## Open Library
- `https://openlibrary.org/search.json?title=War%20and%20Peace&limit=1` — HTTP 200, одна запись метаданных.
- Нет универсальной бесплатной прямой ссылки EPUB для всех книг. Не включено как источник скачивания.
- Документация: https://openlibrary.org/developers/api

## Standard Ebooks, Литрес
- Standard Ebooks: полный OPDS требует членства; не подключён без аккаунта.
- Литрес: API выдачи файлов доступен авторизованным партнёрам, проверяет права; не подключён без партнёрских реквизитов.

## Архитектура Swift
- `CatalogProviders.swift`: выбирает источник и его параметр поиска.
- `OPDSClient.swift`: читает Atom, книги и вложенные разделы авторов, только HTTPS.
- `BookshelfStore.swift`: сохраняет полученный EPUB в локальную библиотеку.
- Запросы и JSON/XML обработка в рабочем приложении написаны на Swift. Python используется исключительно для внешних интеграционных проверок в CI.

HTTP 200 и сигнатура PK подтверждают транспорт и начало содержимого, но не гарантируют, что файл откроется в Readium: требуется проверка полной загрузки и чтения на устройстве.
