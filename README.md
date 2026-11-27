# 🚀 Gemini Freedom — Psiphon + Watchdog + Telegram-бот для 3X-UI

[![YouTube](https://img.shields.io/badge/YouTube-Видеоинструкция-red?style=for-the-badge&logo=youtube)](https://youtu.be/6tdGM5b-u-U)
[![Telegram](https://img.shields.io/badge/Telegram-Link_Of_Freedom-2CA5E0?style=for-the-badge&logo=telegram)](https://t.me/linkoffreedom_channel)
[![Portal](https://img.shields.io/badge/Портал-linkoffreedom.stream-111827?style=for-the-badge&logo=cloudflare)](https://linkoffreedom.stream)

Автоматизированное решение для доступа к **Google Gemini**, **Google AI Studio** и **NotebookLM** с любого VPS — даже если Google пометил IP вашего сервера как `RU`, а Cloudflare WARP душит капчами.

Скрипт поднимает локальный SOCKS5-прокси на базе нативного `psiphon-tunnel-core` (`127.0.0.1:8086`), следит за его доступностью через **Watchdog** и позволяет менять локации прямо из **Telegram**.

---

## ✨ Возможности

* **Без Docker:** нативная работа через `systemd`, потребление ~25 МБ ОЗУ, не затрагивает существующие инбаунды VLESS и 3X-UI.
* **Умный Watchdog:** автоматически проверяет доступность Gemini (`HTTP 200`) и переключает ноду при сбое или высокой задержке.
* **Опциональный Telegram-бот:** просмотр статуса, текущей страны/IP и ручная смена локации в один клик с телефона (шаг можно пропустить при установке).
* **Разделение трафика в 3X-UI:** YouTube и Google Диск продолжают идти напрямую через ваш VPS (`direct`), а через Psiphon уходят только нейросети Google.

---

## ⚡ Быстрая установка (1 команда)

Подключитесь к VPS по SSH (Ubuntu / Debian) и выполните:

```bash
bash <(curl -fsSL [https://raw.githubusercontent.com/linkoffreedom/gemini_freedom/main/install.sh](https://raw.githubusercontent.com/linkoffreedom/gemini_freedom/main/install.sh))
