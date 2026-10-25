# Dossiê — Creality firmware de fabrica `V1.1.0.29`

Consolidação de tudo que foi coletado do firmware do firmware oficial (engenharia reversa do `.img`, do
rootfs MIPS e dos módulos Cython) e da comparação com o Klipper aberto (`jpcurti`/`0xD34D`).

Data: 2026-10-25

---

## 0. Resumo executivo

| | |
|---|---|
| Produto | Creality **firmware de fabrica** (N-Pad01), tela 480×272, kit do Ender-3 V3 SE |
| SoC | **Ingenic X2000 / XBurst2** — MIPS32r2 LE, dual-core 1.2 GHz |
| Kernel | **Linux 4.4.94** (uImage, load `0x80F00000`) |
| Rootfs | **Buildroot 2020.02.1**, squashfs 4.0 + overlayfs sobre ext4 |
| Pacote | 7z com cabeçalho cifrado (`-mhe=on`, AES-256), 118.688.874 bytes |
| Senha | derivada: `md5crypt("OFICIALC3_7e_bz", salt="cxswfile")` |
| Conteúdo | kernel `xImage` + `rootfs.squashfs` + `zero.bin` ("rtos", 424 KB de zeros) |
| Achado principal | o Z-offset automático do firmware oficial está em **2 módulos Cython fechados** (`prtouch_v2_wrapper`, `z_compensate_wrapper`), sem símbolos, sem fonte |
| O que foi feito | descompilação (361/362 e 276/276 funções), **introspecção dinâmica** no Python 3.8 do próprio firmware, API/parâmetros/códigos de erro recuperados, e sanidades portadas para o `prtouch.py` aberto |

---

## 1. Artefato e cadeia de custódia

```
arquivo : firmware_oficial_V1.1.0.29.img
tamanho : 118.688.874 bytes
sha256  : e776c94ea6c9cd24ee74005e3542fed32d862d221191769ab9f28303b017cd2e
md5     : 53bdfd55125a6542901c9b94de47678d
```

Formato real: **7z**, assinatura `37 7A BC AF 27 1C 00 04`.

Cabeçalho 7z (parse manual, offset `0x0712FEB0 + 32` = 118.681.296, 3.424 bytes):

```
17                 kEncodedHeader
06 e7 b0 fe 12 01  kPackInfo: packPos=0x0712FEB0, 1 stream
09 8d 60           kSize = 0xD60
07 0b 01 00 02     kUnpackInfo: 1 folder, 2 coders
   24 06 F1 07 01     -> AES-256 (7zAES), 2^19 ciclos SHA-256
   23 03 01 01 05 5D 00 80 00 00 -> LZMA
```

Ou seja `-mhe=on`: nomes de arquivo e dados cifrados. Senha:

```sh
openssl passwd -1 -salt cxswfile "OFICIALC3_7e_bz"
# $1$cxswfile$XG7ANbYX3bq2H2xmmwrka.
```

> A senha pública que circula (`$1$cxswfile$QP7ykUgkVP7cD6.6x6qTL.`) é de **outro** modelo
> (`<BOARD>C3_7e_bz` com outro BOARD). Para o OFICIAL vale a derivada acima.

Conteúdo (121 arquivos, 2 diretórios):

| blob | tamanho | md5 |
|---|---|---|
| `xImage` (4 partes) | 4.087.872 | `f8acacd8e4041c4fa7ffd6b23fb0013b` |
| `rootfs.squashfs` (110 partes) | 115.249.152 | `ad859dfa0587aa2e8b7f2a6f61657520` |
| `zero.bin` (1 parte) | 424.264 | `8e852ae9b8f5b78f3818e4236c3e8f1d` |

Montagem: `cat xImage.* > xImage` (ordem lexicográfica) e idem para os demais.
Os MD5 batem com o `ota_update.in`.

---

## 2. Hardware alvo

| item | evidência |
|---|---|
| SoC | ELF32 LE `EM_MIPS`, `e_flags 0x70001405` (`mips32r2`, o32, NAN2008), `.MIPS.abiflags` CPR1=64 |
| Kernel | uImage `27 05 19 56`, nome `Linux-4.4.94`, load/entry `0x80F00000`, `comp=none` |
| Módulos | vermagic `4.4.94 SMP preempt mod_unload MIPS32_R2 32BIT` |
| Wi-Fi | `cywdhd.ko` (Cypress/Infineon) + fw `/lib/firmware/wifi_bcm` |
| BT | `hci_uart_h5_kernel_4_4_94.ko` + BSA + fw `/lib/firmware/bt_bcm` |
| Display | `lcd_general_480x272.ko`, fbdev `/dev/fb0`, tslib (`/etc/ts.conf`, `pointercal`) |
| Áudio | ALSA (AIC Ingenic), `ffmpeg` 4.2.2 com `h264_v4l2m2m` (VPU) |
| Câmera | USB UVC: `cam_app`, `mjpg_streamer`, `/tmp/uvc_fifo`, fw `/usr/share/uvc/fw` |
| IMU | `gsensor_test` em `/dev/spidev2.0`; ADXL345 exposto ao Klipper |
| Identidade | partição label `sn_mac`: `sn;mac;model;board;pcba_test;machine_sn;structure;…` |
| MCU impressora | UART `/dev/ttyS1` @230400, GD32F303RET6 nos Ender |
| Registradores | `devmem 0x13012038 32 0x884040c0` (prio CPU), `0x1301202c` (prio DPU/LCD) |
| Gravação MCU | `/sys/devices/platform/swd/swd_update` + `cat update_progress` |

Strain gauge (célula de carga): HX711 em **`clk=PA4`, `sdo=PC6`**, pino de sincronismo `PA15`.
CR-Touch: **`control=PC13`, `sensor=PC14`**.

---

## 3. Layout do OTA e atualização

```
firmware_oficial_V1.1.0.29/
├── ota_config.in                       current_version=1.1.0.29
└── ota_v1.1.0.29/
    ├── ota_update.in                   kernel/rootfs/rtos (nome, tamanho, md5)
    ├── ota_md5_*.…                     md5 encadeado por bloco
    ├── rootfs.squashfs.NNNN.<md5>      blocos de 1 MiB
    ├── xImage.NNNN.<md5>
    └── ota_v1.1.0.29.ok
```

`ota_update.in`:
```
ota_version=1.1.0.29
img_type=kernel  img_name=xImage        img_size=4087872   img_md5=f8acacd8…
img_type=rootfs  img_name=rootfs.squashfs img_size=115249152 img_md5=ad859dfa…
img_type=rtos    img_name=zero.bin      img_size=424264    img_md5=8e852ae9…
```

Fluxo no pad (`/etc/ota_bin/*.sh` + `upgrade-server`):
1. abre o 7z (mesma senha derivada);
2. escreve **direto na partição por label** (`/dev/mmcblk0pN`, `/etc/ota_bin/ota_update_rootfs_squashfs.sh`);
3. verifica MD5 por bloco (`ota_md5_*`), grava `.failed`/`.ok`;
4. `rootfs` é escrito cru (não monta), kernel também.

O pad também **empacota logs** com o mesmo esquema: `7z a -mmt1 -mx=1 -mhe=on -p'%s' …`
(confirmado no decompilado do `upgrade-server`).

---

## 4. Software do pad

Boot (`/etc/init.d`, busybox init): syslogd → ubusd → device_manager → splash → udev → ext4 → dbus →
rede → BT/BSA → Wi-Fi → ifplugd → NTP → dropbear → **klipper** → **klipper_mcu** →
**cx_ai_middleware** → webrtc → mdns → **S99start_app**.

Daemons proprietários (todos MIPS ELF, IPC por unix sockets + protobuf-c + ubus):

| binário | papel |
|---|---|
| `master-server` | barramento IPC |
| `app-server` | regra de negócio; cloud Creality (`api.crealitycloud.com`, `api.crealitycloud.cn`), MQTT (paho), Aliyun OSS/STS, QR code, curl |
| `display-server` | UI 480×272 em fbdev + tslib + freetype + jpeg/png (sem Qt/GL/DRM) |
| `web-server` | HTTP/WS (libhv) servindo SPA Vue em `/usr/share/frontend` |
| `audio-server`, `wifi-server`, `upgrade-server`, `Monitor` | áudio, Wi-Fi, OTA, watchdog |
| `cam_app`, `mjpg_streamer` | câmera UVC (portas 8080/8081) |
| `cx_ai_middleware` + `libncnn_yolov5.so` + `yolov5n*.bin` | IA embarcada (ncnn) |
| `klipper` + `klipper_mcu` | impressão (Python 3.8 + linux MCU) |

Endpoints da cloud observados em `app-server`:
`/api/cxy/v2/device/{registerDevice,user/getAliyunSts,user/localPrint,reportAiNotice,submitLogFile,…}`,
`/api/cxy/firmware/list`.

Usuário `root` desta build: hash `$5$…` (SHA-256 crypt) — **não** é `creality`.

---

## 5. Klipper do firmware oficial

Fork próprio (base ~2021: tem `motion_report`, `z_thermal_adjust`, `input_shaper`; não tem
`axis_twist_compensation` nem `probe_eddy_current`). 139 `.py` + `chelper` em C (GPLv3), mas:

- `prtouch_v2_wrapper.cpython-38-mipsel-linux-gnu.so` (883 KB)
- `z_compensate_wrapper.cpython-38-mipsel-linux-gnu.so` (187 KB)

são **Cython fechado** — sem fonte, sem símbolos.

Perfis em `config/firmware oficial/`: Ender-3, 3 Neo, 3 Pro, 3 V2, 3 V2 Neo, 3 S1, 3 S1 Pro, 3 Max Neo, 3 V3 SE.
Só o **V3 SE** usa `[prtouch_v2]` + `[z_compensate]`; os demais usam `[bltouch]` + `[bl24c16f]`
(EEPROM no i2c.2 do pad) + ADXL345 no `spidev2.0` do pad.

### Config do V3 SE — valores de fábrica

| item | valor |
|---|---|
| `[printer]` | max_velocity **500**, max_accel **5000**, max_z_velocity 100, max_z_accel 500 |
| extrusor | `rotation_distance: 7.53`, PID 20.584/1.737/60.981, `max_temp: 320` |
| cama | PID 70.652/1.798/694.157, `max_temp: 130` |
| X/Y | `position_endstop: -11 / -20`, `position_max: 220`, `homing_speed: 40`, retract 0 |
| Z | `position_min: -5`, `position_max: 250`, `endstop_pin: probe:z_virtual_endstop` |
| TMC2208 | X/Y 0.6 A, Z **0.6 A** |
| `[bltouch]` | `sensor_pin:PC14`, `control_pin: PC13`, offsets **-24/-20**, `z_offset: 0`, `speed:5`, `lift_speed:20`, `probe_with_touch_mode: true`, `stow_on_each_sample: false` |
| `[bed_mesh]` | speed 200, 5,10 → 190,200, 5×5, `fade_start 1`, `fade_end 10` |
| `[input_shaper]` | `mzv`, `freq_y 35.0` |
| `[prtouch_v2]` | `pres_cnt 1`, `pres0_clk_pins PA4`, `pres0_sdo_pins PC6`, `step_swap_pin PA15`, `pres_swap_pin PA15`, `step_base 2`, `tri_min_hold 1000`, `tri_max_hold 1500`, `speed 1` |
| `[z_compensate]` | `tri_min_hold 1400`, `tri_max_hold 2000`, `tri_expand_mm 0.07`, `speed 5`, `hot_start_temp 180`, `hot_rub_temp 200`, `hot_end_temp 140`, `bed_add_temp 60`, área de limpeza `clr_noz_*`, `bl_offset -24,-20` |
| `[idle_timeout]` | 99999999 |

Macros (26): `PAUSE`, `RESUME`, `CANCEL_PRINT`, `PRINT_CALIBRATION`, `FIRST_FLOOR_PAUSE/POSITION/RESUME`,
`M600`, `LOAD_MATERIAL`, `QUIT_MATERIAL`, `M900`, `M204`, `M205`, `G29`, `INPUTSHAPER(_X/_Y)`,
`AUTOTUNE_SHAPERS`, `Z_OFFSET_TEST`, `Z_COMPENSATE_TEST`, `ZZ_OFFSET_TEST`, `M106`, `M107`,
`FINISH_INIT`, `PRINTER_PARAM`, `STRUCTURE_PARAM`.

`printer_params.cfg` → `[custom_macro]`: `default_bed_temp 60`, `default_extruder_temp 220`,
`g28_ext_temp 140`, `temp_diff 40`, `calibration_zoffset_flags 0`.

---

## 6. Desassembly dos `.so`

### 6.1 Método

- **Estático**: Ghidra do próprio REA (`/opencode/meus_projetos/.rea-tools/tools/ghidra_12.1.4_PUBLIC`),
  que é a única distribuição com o decompilador **`linux_arm_64`** já compilado
  (`Ghidra/Features/Decompiler/os/linux_arm_64/decompile`). Em Alpine é preciso `apk add gcompat`
  para o binário glibc rodar; JDK 21.
  A release oficial do Ghidra **não** traz esse binário — foi o motivo da primeira falha.
- **Dinâmico (o que rendeu mais)**: o `.so` importa no **Python 3.8 do próprio firmware** rodando em
  `qemu-mipsel`, com `config`/`printer` falsos que registram cada leitura
  (`re/dynharness/`, harness `probe2.py`).
- Limitação: Cython não deixa símbolos nem literais no C gerado (5,2 MB e 2,0 MB de pseudo-C sem
  nomes). Por isso a API/parâmetros/códigos de erro vieram do dinâmico.

Comandos:

```sh
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
/opencode/meus_projetos/.rea-tools/tools/ghidra_12.1.4_PUBLIC/support/analyzeHeadless \
  /tmp/ghproj p -import prtouch_v2.so -scriptPath /opt/ghiscripts \
  -postScript DumpDecomp.java -deleteProject

# dinâmico (rootfs do firmware)
PYTHONPATH=/tmp/opencode/dyn qemu-mipsel -L rootfs rootfs/usr/bin/python3 \
  probe2.py extras.prtouch_v2_wrapper
```

Resultados: `prtouch_v2` **361/362** funções, `z_compensate` **276/276**.

### 6.2 `prtouch_v2_wrapper` — API e constantes

```
PR_VERSION = 307
MAX_PRES_CNT = 4    MAX_STEP_CNT = 4    MAX_BUF_LEN = 32
```

Classe única `PRTouchEndstopWrapper` — é um **endstop/probe completo** (faz G28/G29 pela célula),
não só offset. Métodos (recuperados por introspecção):

```
_build_pres_config, _build_step_config, _handle_pres_debug_prtouch,
_handle_result_read_pres_prtouch, _handle_result_run_pres_prtouch,
_handle_result_run_step_prtouch, _handle_step_debug_prtouch,
add_stepper, bed_mesh_post_proc, cal_tri_data, check_bed_mesh,
ck_and_manual_get_pres, ck_and_manual_get_step, ck_and_raise_error, ck_g28ed,
clear_nozzle, delay_s, disable_steps, enable_steps, env_self_check,
get_best_rdy_z, get_linear2, get_mcu, get_mm_per_step, get_position_endstop,
get_step_cnts, get_steppers, get_valid_ch, home_start, home_wait, move,
multi_probe_begin, multi_probe_end, print_ary, print_msg, print_res,
probe_finish, probe_prepare, probe_ready, query_endstop, report_run_dis,
run_G28_Z, run_G29_Z, run_gap_prtouch, run_re_g29s, run_step_prtouch,
run_to_next, safe_move_z, send_wave_tri, set_bed_temps, set_fan_speed,
set_hot_temps, set_step_par, shake_motor
+ comandos: PRTOUCH_READY, PRTOUCH_MOVE, READ_PRES, START_STEP_PRTOUCH,
  GET_STEP_CNTS, MAX_STEP_CNT, DEAL_AVGS, CHECK_BED_MESH, SAFE_DOWN_Z,
  SAFE_MOVE_Z, COARSE_HOME_Z, NOZZLE_CLEAR, TRIG_TEST, TEST_PRTH, TEST_SWAP,
  SELF_CHECK_PRTOUCH
```

Parâmetros de config (nome → default real):

```
use_adc=False            tri_acq_ms=12           tri_send_ms=10
tri_need_cnt=1           tri_hftr_cut=2          cal_hftr_cut=10
tri_lftr_k1=0.7          cal_lftr_k1=0.85        tri_min_hold=2000
tri_max_hold=6000        show_msg=False          tri_wave_ip=None
shake_cnt=8              shake_range=0.5         hot_min_temp=140
hot_max_temp=200         bed_max_temp=60         pa_clr_dis_mm=30
pa_clr_down_mm=-0.15     clr_noz_start_x=0       clr_noz_start_y=0
clr_noz_len_x=0          clr_noz_len_y=0         clr_xy_spd=2.0
speed=2.5                lift_speed=5.0          rdy_xy_spd=200
rdy_z_spd=5.0            acc_ctl_mm=0.25         low_spd_nul=5
send_step_duty=16        run_max_velocity=500    run_max_accel=500
run_max_z_velocity=20    run_max_z_accel=200     z_gap_spd=0.6
need_measure_gap=False   gap_dis_range=0.6       check_bed_mesh_max_err=0.2
```

Códigos de erro (texto literal, chaves `key520..key535`):

| código | chave | significado |
|---|---|---|
| `PR_ERR_CODE_PRES_READ_DATA_TIMEOUT` | key520 | intervalo de leitura > **11 ms** |
| `PR_ERR_CODE_PRES_VAL_IS_CONSTANT` | key521 | valor constante no canal (sensor morto) |
| `PR_ERR_CODE_PRES_NOT_BE_SENSED` | key522 | canal não sente pressão |
| `PR_ERR_CODE_PRES_LOST_RUN_DATA` | key523 | dados perdidos após o probe |
| `PR_ERR_CODE_PRES_NOISE_TOO_BIG` | key524 | ruído grande no canal |
| `PR_ERR_CODE_PRESS_TOO_LARGE` | key525 | pressão excessiva (bico raspando a mesa) |
| `PR_ERR_CODE_HAVE_LOST_STEP` | key526 | perda de passo no Z |
| `PR_ERR_CODE_STEP_LOST_RUN_DATA` | key527 | dados de passo perdidos |
| `PR_ERR_CODE_FATESTART_TO_LOW` | key528 | `fade_start` ≤ 0 no bed_mesh |
| `PR_ERR_CODE_G28_Z_DETECTION_TIMEOUT` | key529 | G28 Z estourou tentativas |
| `PR_ERR_CODE_G28_Z_DETECTION_ERROR` | key530 | erro de probe no G28 Z |
| `PR_ERR_CODE_G29_Z_DETECTION_TIMEOUT` | key531 | G29 Z estourou tempo |
| `PR_ERR_CODE_SWAP_PIN_DETECTI` | key532 | teste do pino de sincronismo falhou |
| `PR_ERR_CODE_CK_BED_MESH_OUT_RANGE` | key533 | mesh divergente da célula |
| `PR_ERR_CODE_CAL_DATA_ERROR` | key534 | erro no cálculo dos dados |
| `PR_ERR_CODE_CAL_ERR_POINT` | key535 | múltiplos pontos anômalos |

### 6.3 `z_compensate_wrapper`

```
ZCompensateInitWrapper:
  cmd_Z_OFFSET_AUTO, cmd_Z_OFFSET_CALIBRATION, cmd_CR10SE_NOZZLE_CLEAR,
  cr10se_clear_nozzle, set_step_par, set_hot_temps, set_bed_temps,
  delay_s, move, get_status, pnt_msg, print_msg, TEST_SWAP
```

Parâmetros: `tri_expand_mm=0.05`, `g29_down_min_z=25`, `z_offset_cex_axis=3`,
`vs_start_z_pos=3`, `show_msg=False`, `tri_wave_ip=None`.

Erros: `key401` (`CAL_DATA_ERROR`, `Z_OFFSET_CALIBRATION` → *"Ceramic pressure sensitive
mistrigger"*) e `key402` (`SSAP_TEST_ERROR` — linha de sincronismo sem comunicação).

Emite `SET_GCODE_OFFSET Z_ADJUST=%f MOVE=1` — é assim que o auto-Z chega ao Klipper.

### 6.4 PRTouch v1 (aberto, para comparação)

`klippy/extras/prtouch.py` (478 linhas) + `hx711s.py` (213) + `dirzctl.py` + `filter.py`.
Parâmetros: `base_count=40`, `pi_count=32`, `min_hold=3000`, `max_hold=50000`,
`sensor_random_offset=5`, `check_bed_mesh_max_err=0.2` (+ limpeza de bico e `[hx711s]` PA4/PC6).

Algoritmo do trigger (`_check_trigger`): dispara se 3 amostras acima de `max_hold`; senão
retifica picos, normaliza, rotaciona por `atan` para achar o índice de mínimo, aplica
`filter.lft_k1_oft`, exige monotonicidade nas 3 últimas amostras e razão de subida ≥ 0.8.
`_probe_times` faz 2 sondagens e exige `|o_mm0 - o_mm1| <= max_z_err`.

### 6.5 Comparação e o que foi portado

| capacidade | v2 (firmware oficial) | v1 (aberto) | portado? |
|---|---|---|---|
| papel | endstop/probe completo | só Z-offset (precisa probe externo) | não |
| filtros | 2 (trigger 2 Hz / calibração 10 Hz) | 1 | não |
| confirmação | `tri_need_cnt` janelas | 1 janela | não |
| shake | 8 pulsos × 0.5 mm | não | não |
| gap bico↔mesa | `z_gap_spd`, `gap_dis_range` | não | não |
| **sanidades** | 16 códigos | quase nenhuma | **sim** |
| `bed_mesh_post_proc` | sim | não | não |
| auto Z (`z_compensate`) | sim | não | não |

Portado para `klippy/extras/prtouch.py` (branch `klipper-v3se-hybrid`, commit `6e4bbad5`):

| sanidade | código | comportamento |
|---|---|---|
| valor constante | `key521` | aborta |
| pressão excessiva (`> press_max_factor × max_hold`, default 2×) | `key525` | aborta |
| ruído (`p2p > pres_noise_max × max_hold`, default 50%) | `key524` | loga; `ck_noise_err: True` aborta |
| intervalo de leitura (`> max_read_ms`, default 11) | `key520` | loga; `ck_read_interval_err: True` aborta |
| perda de passo (`up_all > 1.5 × comandado`) | `key526` | loga |

Comando novo: `PRTOUCH_SANITY` (imprime limiares e últimas medidas).
Config de exemplo sem os pinos do pad: `printer_data/config/prtouch-strain.cfg`.

---

## 7. Portabilidade e desempenho medido

Userland MIPS roda sem recompilar sob `qemu-mipsel` (testado com o rootfs do firmware):
`busybox`, `upgrade-server`, `display-server`, `ffmpeg -version` — todos OK.

No Atom D525 (x86_64, Debian 13), via chroot + binfmt:

| carga | nativo | qemu-mipsel | fator |
|---|---|---|---|
| Python (300k iterações) | 0,32 s | 7,41 s | **23×** |
| C (`sha256sum` 1 MiB) | 0,022 s | 0,315 s | **14×** |
| startup do klippy vendor | ~2–3 s | ~10 s | ~4× |
| klippy idle | — | ~3 % de um core | ok |

Conclusão: emulação serve para UI/ferramentas; para impressão real o caminho é host nativo.

---

## 8. Status final da máquina (2026-10-25)

Configuração validada em bancada (sem filamento ainda):

| item | valor | origem |
|---|---|---|
| `[bltouch] z_offset` | **0.92** | medido com papel (2.65 era de outra máquina e afundava 1,9 mm) |
| `probe_with_touch_mode` / `stow_on_each_sample` | **False / True** | corrige o CR-Touch no Klipper aberto |
| `[bltouch] speed` | **5** | valor de fábrica (20 perdia o trigger) |
| `homing_retract_dist` (Z) | **10** | 2,0 não dava curso para o pino re-deployar |
| `sample_retract_dist` / `horizontal_move_z` | **10 / 10** | folga entre amostras e pontos |
| `position_min` (Z) | **-3** | o 0 mascarava falta de trigger |
| `[prtouch] min_hold / max_hold` | **1000 / 1500** | valores da Creality para o V3 SE |
| `press_max_factor` | **10.0** | com max_hold 1500, o 2× abortava na rampa de contato |
| PID extrusor | **19.508 / 1.885 / 50.476** | `PID_CALIBRATE` (SAVE_CONFIG) |
| PID mesa | **64.441 / 0.756 / 1372.584** | `PID_CALIBRATE` (SAVE_CONFIG) |
| mesh 5×5 | amplitude **0,242 mm**, perfil `default` salvo | `BED_MESH_CALIBRATE` |
| repetibilidade da célula | range **0,0125 mm**, σ **0,0050 mm** | `PRTOUCH_ACCURACY SAMPLES=5` |
| auto-Z | contato **0,161 mm** → `SET_GCODE_OFFSET` aplicado, papel agarra em Z=0 | `PRTOUCH_AUTO_Z` |

Automação ativa no `PRINT_START`:

```
M190 S{BED} → G28 → PRTOUCH_AUTO_Z CLEAR_NOZZLE=1 → BED_MESH_CALIBRATE ADAPTIVE=1 → purge
```

Backups: `/opt/klipper-v3se/backups/<data>/` (configs + units + commits) e
`printer-*.cfg` gerados pelo próprio `SAVE_CONFIG`.

Pendente: primeiro cubo (sem filamento) e, opcionalmente, portar `bed_mesh_post_proc`
do `prtouch_v2`.

## 9. Lições e armadilhas (importante para quem repetir)

1. **Senha do 7z é derivada**, não fixa: `md5crypt(<BOARD>C3_7e_bz)`. A string `$1$cxswfile$QP7y…`
   que circula é de outro modelo.
2. **Binário oficial 1.0.1 do jpcurti NÃO tem HX71X** (`CONFIG_WANT_HX71X` ausente em
   `test/configs/displayv3se.config`) → strain gauge não funciona sem rebuild. O build com HX71X
   ficou em `e3v3se_klipper_hx71x_v1.0.1.bin` (46.292 bytes).
3. O CI oficial compila exatamente com `cp test/configs/displayv3se.config .config && make olddefconfig && make`
   — é o processo a reproduzir.
4. **`probe_with_touch_mode: true` + `stow_on_each_sample: false`** (valores do firmware oficial, copiados pelo
   0xD34D) fazem o Klipper **não levantar o cabeçote entre amostras** e, em clones de CR-Touch,
   resultam em `Probe triggered prior to movement` ou `No trigger on probe after full movement`.
   Para CR-Touch comum: `probe_with_touch_mode: False` + `stow_on_each_sample: True` + `speed: 5`.
5. **`position_min: 0` no Z** é uma trava útil, mas faz o probe abortar em `No trigger` em vez de
   descer além — bom para segurança, ruim para diagnosticar probe.
6. O firmware oficial usa a **célula de carga** como referência de Z (`prtouch_v2`), com `z_offset: 0` no
   `[bltouch]`; a config da comunidade usa o **CR-Touch** com `z_offset: 2.65`. Misturar as duas
   sem calibrar gera exatamente o sintoma de "afunda/ignora".
7. A release oficial do Ghidra não traz decompilador ARM64 → use a cópia do REA
   (`.rea-tools/tools/ghidra_12.1.4_PUBLIC`) + `gcompat`.
8. Cython preserva nomes de métodos e mensagens, mas não strings na tabela → introspecção dinâmica
   vale mais que o decompilado.

---

## 10. Reprodução

```sh
# 1) abrir o pacote
openssl passwd -1 -salt cxswfile "OFICIALC3_7e_bz"        # gera a senha
7z x -p'<senha>' -oextract firmware_oficial_V1.1.0.29.img

# 2) remontar
cd extract/firmware_oficial_V1.1.0.29/ota_v1.1.0.29
cat xImage.* > ../../xImage
cat rootfs.squashfs.* > ../../rootfs.squashfs
unsquashfs -d ../../rootfs ../../rootfs.squashfs

# 3) rodar um binário do firmware
qemu-mipsel -L rootfs rootfs/usr/bin/ffmpeg -version

# 4) introspecção dos .so fechados
cd /tmp/opencode/dyn
PYTHONPATH=. qemu-mipsel -L rootfs rootfs/usr/bin/python3 probe2.py extras.prtouch_v2_wrapper

# 5) descompilar
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
/opencode/meus_projetos/.rea-tools/tools/ghidra_12.1.4_PUBLIC/support/analyzeHeadless \
  /tmp/ghproj p -import prtouch_v2.so -scriptPath /opt/ghiscripts \
  -postScript DumpDecomp.java -deleteProject
```

---

## 11. Inventário de arquivos

| arquivo | conteúdo |
|---|---|
| `firmware_oficial_V1.1.0.29.img` | artefato original (118.688.874 B) |
| `extract/…/re/rootfs/` | rootfs extraído (315 MB, 9.657 arquivos, 721 ELF MIPS) |
| `re/prtouch_v2.so.c` | 5,2 MB — pseudo-C das 361 funções |
| `re/z_compensate.so.c` | 2,0 MB — pseudo-C das 276 funções |
| `re/dynharness/` | `extras/` com os `.so` + stubs para introspecção |
| `e3v3se_klipper_hx71x_v1.0.1.bin` | firmware MCU com HX71X (46.292 B, md5 `1cb016d1…`) |
| `ANALISE_FIRMWARE_OFICIAL.md` | análise do pacote/rootfs/hardware |
| `ANALISE_PATOUCH_V2.md` | comparação v1 × v2 e sanidades |
| `DOSSIER_OFICIAL.md` | este documento |
