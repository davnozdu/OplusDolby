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
все переключатели правятся напрямую. Значения запоминаются в `/data/adb/oplusdolby/settings.conf`
и повторно применяются при каждой загрузке — иначе OTA или сброс настроек звука их теряет.

```
sh /data/adb/modules/oplusdolby/bin/oplusdolby.sh status

sh .../oplusdolby.sh on | off              # holo_audio_switch (secure)
sh .../oplusdolby.sh dolby on | off        # system_dolby — главный выключатель (system)
sh .../oplusdolby.sh geq on | off          # system_dolby_geq_state — эквалайзер вкл/выкл
sh .../oplusdolby.sh eq                    # показать 10 полос
sh .../oplusdolby.sh eq 3 -4               # 3-я полоса в −4 дБ
sh .../oplusdolby.sh eq flat               # все полосы в 0
sh .../oplusdolby.sh mode 1                # holo_audio_mode
sh .../oplusdolby.sh device 1              # holo_audio_device_type
sh .../oplusdolby.sh rate 3750 -1          # динамика: порог вкл / выкл, мс (−1 = выкл)
sh .../oplusdolby.sh set <key> <value>     # любой ключ из таблицы
sh .../oplusdolby.sh keep <key>            # перестать форсить ключ
```

Под root: `su -c 'sh /data/adb/modules/oplusdolby/bin/oplusdolby.sh status'`.
Кнопка «Действие» в менеджере модулей печатает то же самое.

| ключ | namespace | что делает |
|---|---|---|
| `holo_audio_switch` | secure | основной переключатель HoloAudio |
| `holo_audio_mode` | secure | профиль (целое, значения внутренние для Oplus) |
| `holo_audio_device_type` | secure | тип вывода |
| `dolby_dynamic_enter_rate` | secure | порог включения динамической обработки, мс |
| `dolby_dynamic_exit_rate` | secure | порог выключения, мс (−1 = никогда) |
| `oplus_camera_record_dolby` | secure | Dolby в записи видео с камеры |
| `system_dolby` | system | главный выключатель Dolby |
| `system_dolby_geq_state` | system | включён ли графический эквалайзер |
| `system_dolby_music_geq` | system | 10 полос эквалайзера, dB через запятую |
| `sound_effects_enabled` | system | общий тумблер системных эффектов |

Про `mode` и `device_type` документации нет: это внутренние константы Oplus. Меняй по одному
значению и слушай. `keep` возвращает ключ системе, `status` показывает, что форсится сейчас.

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
