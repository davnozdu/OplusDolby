# Oplus Dolby (stock)

Тонкий модуль для KernelSU/Magisk: держит на месте **штатный** эффект Dolby/HoloAudio,
который телефон уже несёт в прошивке. Своего DSP в модуле нет, настроек нет, батарею он
не ест — он ничего не обрабатывает, а только проверяет и при необходимости возвращает
стоковые куски на место.

> **Только для этого телефона.** Библиотеки `libOplusAudioxAidl.so` и
> `libOplusSpatializerAidl.so` — фирменные файлы Oplus из прошивки. В репозитории их нет и
> они никуда не выкладываются: модуль работает только с тем, что уже лежит в `/odm` на
> устройстве, и ничего не копирует наружу. На другой модели/прошивке путей и UUID может не
> быть — тогда модуль просто ничего не делает и пишет об этом в лог.

## Что это за эффект

OnePlus/Oplus отдаёт свой Dolby как обычный AIDL-эффект аудио:

| что | где |
|---|---|
| библиотека | `/odm/lib64/soundfx/libOplusAudioxAidl.so` |
| пространственный | `/odm/lib64/soundfx/libOplusSpatializerAidl.so` |
| объявление | `/odm/etc/audio_effects_config.xml` |
| имя в конфиге | библиотека `oplus_audiox_sw`, эффект `oplusaudiox` |
| UUID | `41f6c0f4-5d8f-11ec-bf63-0242ac130002` |

Аудиополитика создаёт его на session 0, поэтому он обрабатывает всё, что идёт на динамики.
Работает ровно до тех пор, пока на месте эта библиотека и строка в конфиге. Любой
«Dolby-мод», который подменяет `libOplusAudioxAidl.so` своим бинарником, гасит штатный
эффект — снаружи это выглядит как «Dolby пропал».

## Что делает модуль

1. При первой загрузке запоминает текущие стоковые библиотеки как эталон
   (`/data/adb/oplusdolby/stock/`).
2. На каждой загрузке сверяет md5: если файл заменён или удалён — возвращает эталон
   (bind-mount, с откатом на обычное копирование).
3. Проверяет, что в `/odm/etc/audio_effects_config.xml` объявлены библиотека и эффект;
   если кто-то переписал файл — возвращает объявление.
4. Если что-то починил — один раз перезапускает `audioserver`, чтобы эффект снова попал в
   цепочку. Если всё на месте, не трогает ничего.

Лог: `/data/adb/oplusdolby/log.txt`.

## Настройки эффекта

Вендорное приложение настроек (`com.oplus.audio.effectcenter`) на этом SKU выключено, поэтому
переключатели HoloAudio правятся напрямую. Значения запоминаются в
`/data/adb/oplusdolby/settings.conf` и повторно применяются при каждой загрузке — иначе OTA
или сброс настроек звука их теряет.

```
su -c 'sh /data/adb/modules/oplusdolby/bin/oplusdolby.sh status'   # что сейчас
su -c 'sh /data/adb/modules/oplusdolby/bin/oplusdolby.sh on'       # holo_audio_switch=1
su -c 'sh /data/adb/modules/oplusdolby/bin/oplusdolby.sh off'      # holo_audio_switch=0
su -c 'sh /data/adb/modules/oplusdolby/bin/oplusdolby.sh mode 1'   # holo_audio_mode
su -c 'sh /data/adb/modules/oplusdolby/bin/oplusdolby.sh device 1' # holo_audio_device_type
su -c 'sh /data/adb/modules/oplusdolby/bin/oplusdolby.sh rate 3750 -1'  # dynamic enter/exit
su -c 'sh /data/adb/modules/oplusdolby/bin/oplusdolby.sh keep holo_audio_mode'  # перестать форсить
```

Кнопка «Действие» в менеджере модулей печатает то же, что `status`.

Что означают значения (`holo_audio_mode`, `device_type`, `dolby_dynamic_*`) — это внутренние
константы Oplus, документации к ним нет: `mode` — целое число профиля, `device_type` —
тип вывода, `rate` — пороги включения динамической обработки в миллисекундах (−1 = выкл).
Ставь по одному значению и слушай, что меняется; `keep` возвращает системе управление ключом.

## Установка

Ставить **на стоковом звуке** — эталон снимается с того, что стоит на телефоне в момент
первой загрузки с модулем.

```
su 0 ksud module install /data/local/tmp/OplusDolby.zip
```

Скачать: [последний релиз](https://github.com/davnozdu/OplusDolby/releases/latest/download/OplusDolby.zip).

## Выключить

```
su 0 touch /data/adb/oplusdolby/disable
```

## Проверка, что эффект в цепочке

```
adb shell su 0 dumpsys media.audio_flinger | grep -A2 "OplusAudioX"
```

Должно быть `1 effects for session 0` и `name: OplusAudioX`.

## Сборка

GitHub Actions: каждый push проверяет синтаксис скриптов и собирает `OplusDolby.zip`
артефактом; тег `v*` публикует релиз.
