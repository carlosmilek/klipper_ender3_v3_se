# Configs do Klipper — conteúdo e proveniência de cada dado

Documento de auditoria: mostra **o que está configurado** hoje no Atom e **de onde saiu cada
valor** (arquivo do firmware, arquivo do projeto aberto ou medição).

Legenda de origem:

- **[N]** = firmware oficial Creality firmware oficial (extraído do `firmware_oficial_V1.1.0.29.img`)
- **[C]** = comunidade `0xD34D/ender3-v3-se-klipper-config` (base do jpcurti)
- **[D]** = docs/fork `jpcurti/ender3-v3-se-klipper-with-display`
- **[M]** = `shubham0x13/ender-3-v3-se-klipper` (macros)
- **[X]** = nosso (enxerto/decisão), com justificativa
- **[R]** = engenharia reversa dos `.so` fechados (Ghidra + introspecção dinâmica)

---

## 1. Arquivos de config em uso (Atom: `/opt/klipper-v3se/printer_data/config/`)

| arquivo | origem | papel |
|---|---|---|
| `printer.cfg` | **[C]** + enxertos **[N]/[X]** | config ativa |
| `macros.cfg` | **[M]** | `PRINT_START/END`, `LOAD/UNLOAD_FILAMENT`, `PID_*`, `M109/M190` |
| `prtouch-strain.cfg` | **[N]** (pinos) + **[C]** (valores) + **[R]** (sanidades) | strain gauge — **incluído** desde o rebuild com HX71X |
| `printer.cfg.vendor-bak` | **[N]** + nosso patch | backup da fase qemu (klipper vendor) |
| `printer-base.cfg` | **[C]** | cópia bruta da base, para diff |
| `moonraker.conf` | **[X]** | API/WebSocket, `klippy_uds_address`, trusted clients |

Arquivos de sistema: `/etc/systemd/system/klipper.service` (**[D]**, host nativo) e
`moonraker.service` (**[X]**).

---

## 2. `printer.cfg` — conteúdo atual

```ini
# ── cabeçalho original da base [C] ───────────────────────────────
# This file contains pin mappings for the stock 2022 Creality Ender 3
# V3 SE. ... (comentários do 0xD34D sobre menuconfig/flash)

[stepper_x]                       # [C] pinos; [N] difere em endstop/limites
step_pin: PC2                     # [C]=[N]=PC2
dir_pin: !PB9                     # [C]=[N]
enable_pin: !PC3                  # [C]=[N]
microsteps: 16
rotation_distance: 40
endstop_pin: ~!PA5                # [C] com pull-up (~); [N] usa !PA5
position_endstop: -6              # [C]; [N] usa -11
position_min: -6                  # [C]; [N] usa -15
position_max: 230                 # [C]; [N] usa 220
homing_speed: 80                  # [C]; [N] usa 40

[tmc2208 stepper_x]
uart_pin: PB12                    # [C]=[N]
run_current: 0.60                 # [C]=[N]
sense_resistor: 0.150
interpolate: True

[stepper_y]                       # idem X
step_pin: PB8
dir_pin: PB7
enable_pin: !PC3
microsteps: 16
rotation_distance: 40
endstop_pin: ~!PA6
position_endstop: -14             # [C]; [N] usa -20
position_min: -14
position_max: 230
homing_speed: 80

[tmc2208 stepper_y]
uart_pin: PB13
run_current: 0.60
sense_resistor: 0.150
interpolate: True

[stepper_z]
step_pin: PB6
dir_pin: !PB5
enable_pin: !PC3
microsteps: 16
rotation_distance: 8
endstop_pin: probe:z_virtual_endstop   # [C]=[N]
position_min: -3                  # [C]; [N] usa -5; já testamos 0 (trava) e voltamos
position_max: 250
homing_speed: 4                   # [C]
second_homing_speed: 1            # [C]
homing_retract_dist: 2.0          # [C]

[tmc2208 stepper_z]
uart_pin: PB14
run_current: 0.8                  # [C]; [N] usa 0.6

[extruder]
max_extrude_only_distance: 100.0
step_pin: PB4
dir_pin: PB3
enable_pin: !PC3
microsteps: 16
rotation_distance: 7.53           # ← [N] valor de fábrica (a base [C] tem 7.44)
nozzle_diameter: 0.400
filament_diameter: 1.750
heater_pin: PA1
sensor_type: EPCOS 100K B57560G104F
sensor_pin: PC5
control: pid
pid_Kp: 27.142                    # [C] (não calibrar por cópia; rodar PID_EXTRUDER)
pid_Ki: 1.371
pid_Kd: 134.351
min_temp: 0
max_temp: 260

[heater_bed]
heater_pin: PB2
sensor_type: EPCOS 100K B57560G104F
sensor_pin: PC4
control: pid
pid_kp: 66.371                    # [C]
pid_ki: 0.846
pid_kd: 1301.702
min_temp: 0
max_temp: 100

[heater_fan hotend_fan]           # [C]; [N] chama de [heater_fan nozzle_fan]
pin: PC1

[fan]
pin: PA0

[mcu]                             # [C] + [X] ajustado ao adaptador USB
serial: /dev/serial/by-id/usb-1a86_USB_Serial-if00-port0
restart_method: command           # [C]

[printer]                         # [C] conservador
kinematics: cartesian
max_velocity: 250                 # [N] usa 500
max_accel: 2500                   # [N] usa 5000
max_z_velocity: 5                 # [N] usa 100 (não portado: agressivo)
square_corner_velocity: 5.0
max_z_accel: 100

[bltouch]                         # [C] (restaurado ao original)
sensor_pin: ^PC14                 # [N] sem pull-up; testamos os dois
control_pin: PC13                 # [N]=[C]
x_offset: -23.0                   # [C]; [N] usa -24
y_offset: -14.5                   # [C]; [N] usa -20
z_offset: 2.65                    # [C]; [N] usa 0 (porque o Z do firmware oficial é a célula)
speed: 20                         # [C]; [N] usa 5
pin_move_time: 0.4                # [C]
stow_on_each_sample: False        # [C]=[N]  ← ver §6 (mudança pendente)
probe_with_touch_mode: True       # [C]=[N]  ← ver §6 (mudança pendente)

[safe_z_home]                     # [C]
home_xy_position: 134,123
speed: 150
z_hop: 10
z_hop_speed: 10

[bed_mesh]                        # [C] base
speed: 120                        # [C]; [N] usa 200
horizontal_move_z: 5              # [C]; [N] usa 8
mesh_min: 30,30                   # [C] (dependente do offset do CR-Touch)
mesh_max: 207,215.5               # [C]
probe_count: 5,5                  # [C]=[N]
algorithm: bicubic
fade_start: 1                     # ← [N]
fade_end: 10                      # ← [N]
fade_target: 0                    # ← [N]

[output_pin beeper]               # [C]
pin: PB0

[screws_tilt_adjust]              # [C] (não existe no firmware oficial)
screw1: 54.5, 45.5
screw2: 224.5, 45.5
screw3: 224.5, 215.5
screw4: 54.5, 215.5
horizontal_move_z: 10.
speed: 50.
screw_thread: CCW-M4

# ─── enxertos [X]/[N] ───────────────────────────────────────────
[virtual_sdcard]
path: /opt/klipper-v3se/printer_data/gcodes   # [X] necessário p/ Moonraker/Fluidd

[pause_resume]                    # [X] exigido por PRINT_START (CLEAR_PAUSE)

[input_shaper]                    # [N] valores de fábrica do V3 SE
shaper_type_y: mzv
shaper_freq_y: 35.0

[temperature_sensor mcu_temp]     # [N] (sensor_type: temperature_mcu)
sensor_type: temperature_mcu
min_temp: 0
max_temp: 100

[e3v3se_display]                  # [D] (bridge serial do MCU, USART2)
language: english
logging: False

[include macros.cfg]              # [M]

[delayed_gcode BLTOUCH_INIT]      # [X] reset do BLTouch no boot
initial_duration: 2
gcode:
  BLTOUCH_DEBUG COMMAND=reset
```

### Diferenças vs a base [C] (o que nós mudamos)

```diff
-rotation_distance: 7.44
+rotation_distance: 7.53            # [N] fábrica

 [bed_mesh]
 algorithm: bicubic
+fade_start: 1                      # [N]
+fade_end: 10                       # [N]
+fade_target: 0                    # [N]

+# [X] blocos novos: virtual_sdcard, pause_resume, input_shaper,
+#     temperature_sensor mcu_temp, e3v3se_display, include macros.cfg,
+#     delayed_gcode BLTOUCH_INIT
```

---

## 3. `prtouch-strain.cfg` — strain gauge (incluído após o rebuild HX71X)

```ini
[filter]          # [C] módulos do fork (GPLv3)
[dirzctl]         # [C]
[hx711s]          # [C]
sensor0_clk_pin: PA4      # [N] pres0_clk_pins
sensor0_sdo_pin: PC6      # [N] pres0_sdo_pins

[prtouch]
sensor_x: 32              # [C]
sensor_y: 30              # [C]
clr_noz_start_x: 15       # [C]
clr_noz_start_y: 25       # [C]
clr_noz_len_y: 15         # [C]
s_hot_min_temp: 160       # [C]
s_hot_max_temp: 200       # [C]
s_bed_max_temp: 60        # [C]
show_msg: True
wipe_retract_distance: 2

# ── sanidades portadas do módulo fechado [R] ─────────────────────
ck_sanity: True             # aborta em valor constante (key521) e pressão excessiva (key525)
ck_noise_err: False         # ruído alto (key524): só loga
ck_read_interval_err: False # intervalo > 11 ms (key520): só loga
press_max_factor: 2.0
pres_noise_max: 0.5
max_read_ms: 11
max_step_ratio: 1.5
```

> `prtouch` é **só Z-offset** neste fork; o `endstop_pin: probe:z_virtual_endstop` continua sendo
> o CR-Touch (`[bltouch]`). É diferente do firmware oficial, onde o `prtouch_v2` é um **ProbeEndstopWrapper**
> completo (faz o Z pela célula).

---

## 4. `moonraker.conf` e units

```ini
[server]
host: 0.0.0.0
port: 7125
klippy_uds_address: /opt/klipper-v3se/printer_data/comms/klippy.sock   # [X]

[machine]
provider: systemd_cli                                          # [X] (sem PolKit no Debian)

[authorization]
trusted_clients: 127.0.0.1/32, 10.0.0.0/8, 192.168.0.0/16, 172.16.0.0/12
cors_domains: *
```

`klipper.service` (**[D]**, host nativo):

```ini
ExecStart=/opt/klipper-v3se/klipper-env/bin/python \
  /opt/klipper-v3se/klipper/klippy/klippy.py \
  /opt/klipper-v3se/printer_data/config/printer.cfg \
  -a /opt/klipper-v3se/printer_data/comms/klippy.sock \
  -l /opt/klipper-v3se/printer_data/logs/klippy.log
```

`klipper-vendor.service` = versão antiga (MIPS via qemu, chroot) — **desabilitada**, guardada.

---

## 5. Build do firmware — de onde vieram as opções

| dado | origem |
|---|---|
| base do `.config` | **[D]** `test/configs/displayv3se.config` |
| processo | **[D]** `scripts/edited-ci-build.sh`: `cp TARGET .config && make olddefconfig && make` |
| MCU | `CONFIG_MCU="stm32f103xe"`, `CONFIG_FLASH_APPLICATION_ADDRESS=0x8007000` (28 KiB bootloader) |
| serial host | `CONFIG_SERIAL=y`, `CONFIG_STM32_SERIAL_USART1=y`, `CONFIG_SERIAL_BAUD=250000` |
| display | `CONFIG_SERIAL_BRIDGE=y`, `CONFIG_ENABLE_SERIAL_BRIDGE_USART2=y` |
| **strain gauge** | **`CONFIG_WANT_HX71X=y`** — **não existe** no `.config` oficial; fomos nós |
| verificação | `arm-none-eabi-nm out/klipper.elf \| grep hx71` → `command_config_hx711s`, `command_query_hx71x` |

Artefato: `e3v3se_klipper_hx71x_v1.0.1.bin` (46.292 B, md5 `1cb016d19871024e2ad3363530ba5518`).

---

## 6. Pendência conhecida (probe)

**[C]=[N]** definem `probe_with_touch_mode: true` + `stow_on_each_sample: false`. Nesse modo o
Klipper **não levanta o cabeçote entre amostras** e, em CR-Touch comum, não vê o trigger
(`Probe triggered prior to movement` / `No trigger on probe after full movement`).

Mudança preparada (não aplicada porque o Atom está offline):

```ini
stow_on_each_sample: True
probe_with_touch_mode: False
```

mantendo `speed: 5`, `position_min: -3` e o `BLTOUCH_INIT` (reset no boot).

---

## 7. Tabela geral de proveniência dos dados coletados

| dado | valor | fonte / método |
|---|---|---|
| senha do 7z | `$1$cxswfile$XG7ANbYX3bq2H2xmmwrka.` | fórmula de `SimplyPrint/create.sh` (`md5crypt(BOARD+"C3_7e_bz", "cxswfile")`) + `openssl passwd -1` |
| blobs e tamanhos | xImage / rootfs / zero.bin | `ota_update.in` dentro do 7z |
| MD5 dos blobs | `f8acacd8…`, `ad859dfa…`, `8e852ae9…` | `ota_update.in` + conferência por `md5sum` |
| SoC/arquitetura | Ingenic X2000, MIPS32r2 LE | `readelf -h/-A` dos 721 ELF + `e_flags 0x70001405` |
| kernel | 4.4.94, load `0x80F00000` | header uImage do `xImage` |
| vermagic | `4.4.94 SMP preempt MIPS32_R2 32BIT` | `strings cywdhd.ko` |
| display 480×272 | fbdev + tslib | `/etc/logo/*480x272*`, `get_fb_info.sh`, `ts.conf` |
| strain gauge (pinos) | `clk=PA4`, `sdo=PC6`, swap `PA15` | **[N]** `[prtouch_v2]` e **[C]** `[hx711s]` |
| CR-Touch (pinos) | `control=PC13`, `sensor=PC14` | **[N]** e **[C]**, coincidem |
| serviços do pad | 8 daemons + IPC | `/etc/init.d/S99start_app` |
| cloud | `api.crealitycloud.com`, Aliyun OSS/STS | `strings app-server` |
| OTA por bloco | 1 MiB + md5 encadeado | `ota_md5_rootfs.squashfs.*` + `local_ota_update.sh` |
| API do `prtouch_v2` | 90+ métodos, `PR_VERSION=307` | **[R]** introspecção dinâmica (`dir()` + stubs) |
| 40 parâmetros do `prtouch_v2` | ver §6 do dossiê | **[R]** interceptor de `config.getint/getfloat/get` |
| 16 códigos de erro | `key520..key535` | **[R]** constantes do módulo |
| parâmetros do `z_compensate` | `tri_expand_mm=0.05`, … | **[R]** introspecção |
| algoritmo v1 (aberto) | `min_hold=3000`, `max_hold=50000`, `pi_count=32` | **[D]** `klippy/extras/prtouch.py` |
| desempenho qemu | 14× (C) / 23× (Python) | medição no Atom D525 (benchmarks do dossiê) |
| configs de fábrica do V3 SE | 500/5000, 7.53, fade, mzv 35 Hz | **[N]** `config/firmware oficial/Ender-3 V3 SE/*.cfg` |
| macros | 26 no firmware oficial; usamos as do [M] | **[N]** `gcode_macro.cfg`, **[M]** `macros.cfg` |
| `[e3v3se_display]` | language/logging | **[D]** `e3v3se_docs/configuration.md` |
