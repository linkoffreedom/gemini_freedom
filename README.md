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
```

Во время установки скрипт предложит:
1. Выбрать стартовую страну (по умолчанию — **Швейцария** `CH`) и локальный порт (`8086`).
2. Подключить Telegram-бота (по желанию — нажмите `Enter`, чтобы пропустить):
   * Токен бота берётся в `@BotFather`.
   * Ваш `CHAT_ID` можно узнать в `@getmyid_bot` или `@userinfobot`.
   * *Важно:* перед запуском бота обязательно нажмите **Start** в диалоге со своим новым ботом.

---

## 🛠 Управление из терминала (`psiphon-ctl`)

| Команда | Описание |
| :--- | :--- |
| `psiphon-ctl status` | Проверить статус службы, Watchdog, текущую страну и задержку |
| `psiphon-ctl rotate` | Принудительно сменить ноду / переподключиться |
| `psiphon-ctl tg-setup` | Настроить или перепривязать Telegram-бота |
| `psiphon-ctl uninstall` | Полностью удалить скрипт, службы `systemd` и файлы Psiphon (3X-UI не затрагивается) |

---

## ⚙️ Краткая настройка 3X-UI

1. **Sniffing:** в настройках вашего инбаунда VLESS убедитесь, что включён Sniffing (`http`, `tls`, `quic`).
2. **Исходящее (Outbound):** добавьте новый outbound с тегом `psiphon-out` на протокол `socks` (`127.0.0.1`, порт `8086`).
3. **Правила маршрутизации (строго сверху вниз):**
   * **Google Direct** (`direct`) — домены YouTube и Google Drive, чтобы тяжёлый трафик шёл напрямую через VPS.
   * **Block QUIC** (`block`, сеть `UDP`, порт `443`) — запрещает Gemini рваться в UDP, так как Psiphon работает по TCP.
   * **Gemini Out** (`psiphon-out`, сеть `TCP`) — домены Gemini, AI Studio, NotebookLM и сопутствующие домены Google.

---

## 📦 Инструкции и видео

* 📄 **Полная текстовая инструкция (JSON, правила 3X-UI, списки доменов для OpenWrt / Keenetic):** [Открыть на Google Диске](https://drive.google.com/file/d/1wOLb8E1GP_L71e6VnVvVguR4RZWiqitm/view?usp=sharing)
* 🎬 **Видеоинструкция к этому скрипту:** [Смотреть на YouTube](https://youtu.be/6tdGM5b-u-U)
* 🎬 **Базовая настройка 3X-UI, VLESS и сертификатов:** [Смотреть на YouTube](https://youtu.be/BnHqu_6tm6M)

---

## 🔥 Лучший VPS для твоего VPN (VLESS / Amnezia)

**1 Гбит/с, 2GB RAM, CPU 3.5Ghz** за **200₽** вместо 499₽ за 1-й месяц по промокоду `FREEDOM` (3X-UI можно выбрать для автоустановки прямо при заказе):
👉 [Оформить сервер на AdminVPS](https://my.adminvps.ru/aff.php?aff=29301)

* `FREEDOM` — скидка **60%** при оплате за 1 месяц
* `FREEDOM3` (20% на 3 мес.) | `FREEDOM6` (15% на 6 мес.) | `FREEDOM12` (5% на год)

*(Промокоды действуют только для новых пользователей!)*

---

## 🎁 Не хочешь настраивать свой VPS?

Готовая VPN-подписка с **XHTTP** для быстрой вставки в **Podkop, Forkop, Tachyon, Happ** на смартфоне или ПК (**день теста бесплатно!**):
👉 [Перейти в Telegram-бот](https://t.me/ctrlzvpn_bot?start=ref_7210eeb7)

---

## ⭐ Полезные ресурсы и связь

* 📢 **Телеграм-канал Link Of Freedom — подпишись:** [t.me/linkoffreedom_channel](https://t.me/linkoffreedom_channel)
* 🌐 **Наш портал и ценные ссылки:** [linkoffreedom.stream](https://linkoffreedom.stream) *(доступ из РФ через proxy/vpn)*
* ✍ **Telegram для предложений и личных консультаций (помощь в настройке):** [t.me/linkoffreedom](https://t.me/linkoffreedom)

---

## 🙌 Поддержать канал Link Of Freedom

* 💳 **Быстро с карты / СБП (с сообщением):** [dalink.to/linkoffreedom](https://dalink.to/linkoffreedom)
* 💎 **Криптокошелёк в сети TON (TON, USDT, GRAM):**

```text
UQCSnH-C7l00Si8wUz59jXyOA7x9y6jSnODIyxdoAQAacMns
```
