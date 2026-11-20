# OplusDolby — состояние на 20.11.2026

## Что это

Модуль управляет **штатным** Dolby-эффектом телефона (`OplusAudioX`, `libOplusAudioxAidl.so`), который живёт
на session 0 и всегда был в прошивке. Своего DSP в модуле нет: только сохранение стоковых библиотек, dex-клиент
к протоколу эффекта и WebUI.

## Рабочая конфигурация (проверено на устройстве)

```
эффект:   OplusAudioX, UUID 41f6c0f4-5d8f-11ec-bf63-0242ac130002, session 0
состояние: 00000 003  Registered y  Enabled y     (003 = обрабатывает звук)
режимы:   dolby (профиль 2) | dolby_soft (профиль 5) | eq (профиль 0) | off
дефолт:   dolby — Dolby максимум, эквалайзер выключен
```

Профили взаимоисключающие, потому что GEQ существует только в профиле 0, а в нём выключена обработка Dolby:

```
профиль 0   Geq=1  SysEQHp=1   Fddrc=0 DE=0   только эквалайзер
профиль 1   Geq=1  SysEQ=1                    эквалайзер + системный EQ
профиль 2   Geq=0  Fddrc=1 DE=4               Dolby по максимуму
профиль 5   Geq=0  DE=1                       Dolby мягче
```

## Протокол эффекта

```
PROFILE     0x100100bb   int 0..14
EQ_GAINS    0x100100bc   48 байт: volIdx, 10, 10 x int(dB * 2^22)
VOLUME_IDX  0x100100be   int
ATTEN_DB    0x100100c2   float
SOUNDX      0x100100c5   int 1/0
EQ_ENABLE   0x100100c9   int 1/0
```

Порядок, который работает: `PROFILE 0` → `EQ_ENABLE 1` → `EQ_GAINS volIdx …`. Без профиля 0 gains принимаются
с кодом 0 и выбрасываются. `volIdx` — это индекс громкости медиапотока, поделённый на 10, если максимум шкалы
больше 100 (здесь max 160, громкость 80 → volIdx 8). Кривая хранится по бакетам громкости, поэтому отправлять её
нужно с текущим бакетом.

## Команды

```
sh /data/adb/modules/oplusdolby/bin/oplusdolby.sh ui        одна строка состояния (для WebUI)
sh … status                                                полный отчёт
sh … dolby on | soft | off                                 режимы Dolby
sh … eq on | off | set <10 дБ> | flat                      свой эквалайзер
sh … profile <n>                                           профиль напрямую (для экспериментов)
```

Выбор хранится в `/data/adb/oplusdolby/state.conf`, кривая — в `eq.txt`, всё восстанавливается в `service.sh`
при каждой загрузке (эффект пересоздаётся audioserver'ом и сам ничего не помнит).

## Известные ограничения

- **Кнопки режимов в WebUI не срабатывают**: показ состояния и ползунки работают, но тап по строке режима не
  доходит до скрипта (в `ui.log` нет соответствующей команды, состояние не меняется). Переключение режимов
  работает из CLI и из кнопки «Действие» модуля.
- Мост KernelSU отдаёт странице **только последнюю строку stdout**, поэтому все ответы для панели печатаются
  одной строкой.
- WebView на Android 17 игнорирует `-webkit-appearance: slider-vertical`; ползунки сделаны через
  `writing-mode: vertical-lr` + `direction: rtl`.
- Настройки `system_dolby*`, `holo_audio_*` — декоративные флаги для выключенного вендорского приложения;
  звук меняет только `setParameter` эффекта.

## Проверка

```
adb shell su 0 sh /data/adb/modules/oplusdolby/bin/oplusdolby.sh ui
adb shell su 0 dumpsys media.audio_flinger | grep -A3 "Effect ID" | grep 00000
adb shell su 0 tail -3 /data/adb/oplusdolby/log.txt
adb shell su 0 cat /data/adb/oplusdolby/ui.log
```
