# Engenharia reversa do PRTouch v2 (firmware oficial) × PRTouch v1 (projeto aberto)

Fonte analisada: `firmware_oficial_V1.1.0.29` (Creality, build 2025-03-19)
- `usr/share/klipper/klippy/extras/prtouch_v2_wrapper.cpython-38-mipsel-linux-gnu.so` (883 KB, Cython, MIPS32r2)
- `usr/share/klipper/klippy/extras/z_compensate_wrapper.cpython-38-mipsel-linux-gnu.so` (187 KB, Cython)

Comparado com: `jpcurti/ender3-v3-se-klipper-with-display` → `klippy/extras/prtouch.py` (478 linhas, aberto) + `hx711s.py`.

## Como foi feito

1. **Descompilação**: Ghidra 12.1.4 do próprio REA (`/opencode/meus_projetos/.rea-tools/tools/`), que é o único com o decompilador `linux_arm_64` já compilado (`apk add gcompat` resolve a camada glibc).
   - `z_compensate_wrapper`: 276/276 funções → `re/z_compensate.so.c`
   - `prtouch_v2_wrapper`: 361/362 funções → `re/prtouch_v2.so.c`
   - Limitação: Cython não deixa símbolos nem literais no C gerado → o estático sozinho rende pouco.
2. **Introspecção dinâmica** (o que realmente entregou): o `.so` importa no Python 3.8 do próprio firmware rodando sob `qemu-mipsel`, com `config`/`printer` falsos que registram cada leitura. Harness em `re/dynharness/`.
   - `PR_VERSION = 307`
   - `MAX_PRES_CNT = 4`, `MAX_STEP_CNT = 4`, `MAX_BUF_LEN = 32`

## Superfície de configuração (defaults reais do código)

### prtouch_v2 (fechado) — 40 parâmetros
| grupo | parâmetros |
|---|---|
| aquisição | `tri_acq_ms=12`, `tri_send_ms=10`, `tri_need_cnt=1`, `use_adc=False` |
| filtros | `tri_hftr_cut=2`, `cal_hftr_cut=10`, `tri_lftr_k1=0.7`, `cal_lftr_k1=0.85` |
| trigger | `tri_min_hold=2000`, `tri_max_hold=6000` |
| shake | `shake_cnt=8`, `shake_range=0.5` |
| movimento | `speed=2.5`, `lift_speed=5.0`, `rdy_xy_spd=200`, `rdy_z_spd=5.0`, `acc_ctl_mm=0.25`, `low_spd_nul=5`, `send_step_duty=16` |
| limites do probe | `run_max_velocity=500`, `run_max_accel=500`, `run_max_z_velocity=20`, `run_max_z_accel=200` |
| gap | `z_gap_spd=0.6`, `need_measure_gap=False`, `gap_dis_range=0.6` |
| limpeza | `hot_min_temp=140`, `hot_max_temp=200`, `bed_max_temp=60`, `pa_clr_dis_mm=30`, `pa_clr_down_mm=-0.15`, `clr_noz_*`, `clr_xy_spd=2.0` |
| mesh | `check_bed_mesh_max_err=0.2` |

### prtouch v1 (aberto) — só 6 parâmetros de trigger
`base_count=40`, `pi_count=32`, `min_hold=3000`, `max_hold=50000`, `sensor_random_offset=5`, `check_bed_mesh_max_err=0.2`

### z_compensate (fechado)
`tri_expand_mm=0.05`, `g29_down_min_z=25`, `z_offset_cex_axis=3`, `vs_start_z_pos=3`, `show_msg`.

## Diferenças que importam

| Capacidade | v2 (firmware oficial) | v1 (aberto) | Ganho de portar |
|---|---|---|---|
| Papel | **ProbeEndstopWrapper completo** (Z endstop pela célula) | só Z-offset/limpeza, exige probe externo | dispensa CR-Touch para homing |
| Sanidade do sinal | 6 códigos de erro dedicados: ruído alto, valor constante, intervalo de leitura > **11 ms**, perda de dados, pressão excessiva, teste de pino trocado | só regra de monotonicidade/razão de subida | evita cravar o bico |
| Lost step | `PR_ERR_CODE_HAVE_LOST_STEP` + `get_step_cnts`/`send_step_duty` | usa `dirzctl`, sem código de erro específico | segurança do Z |
| Filtragem | dois filtros (trigger 2 Hz-cut/k1 0.7 e calibração 10 Hz/k1 0.85) | um (`filter.lft_k1_oft`) | trigger mais estável |
| Confirmação | `tri_need_cnt` janelas consecutivas | 1 janela | menos falso positivo |
| Shake | 8 pulsos de 0.5 mm antes de medir | não tem | reduz histerese |
| Gap nozzle↔mesa | `z_gap_spd`/`gap_dis_range` | não mede | detecção de sujeira/erro |
| Corrigir o mesh | **`bed_mesh_post_proc`** + `CK_BED_MESH_OUT_RANGE` + `FATESTART_TO_LOW` | **não existe** | corrige erro CR-Touch × bico |
| Auto Z-offset | `z_compensate` (`Z_OFFSET_AUTO`) com compensação térmica `tri_expand_mm` | **não existe** | acaba o ajuste manual |

## Implementado na v1 híbrida (código)

Branch `klipper-v3se-hybrid` em `/opt/klipper-v3se/klipper` (commit `6e4bbad5`), arquivo `klippy/extras/prtouch.py`:

| Sanidade | Origem (v2) | Comportamento |
|---|---|---|
| valor constante | `key521` | **aborta** (sempre ativo com `ck_sanity`) |
| pressão excessiva | `key525` | **aborta** se `max > press_max_factor × max_hold` |
| ruído alto | `key524` | loga por padrão; `ck_noise_err: True` aborta |
| intervalo de leitura | `key520` | loga por padrão; `ck_read_interval_err: True` aborta |
| perda de passo | `key526` | loga (`up_all > max_step_ratio × comandado`) |

Comando novo: `PRTOUCH_SANITY` (mostra limiares e últimas medidas).
Config de exemplo: `printer_data/config/prtouch-strain.cfg` (não incluído ainda — depende de firmware com `CONFIG_WANT_HX71X`).

## Backlog derivado (ordem de risco/benefício)

1. **Checagens de sanidade** no `prtouch.py` (ruído, valor constante, intervalo de leitura, pino trocado) — baixo risco, ganho imediato de segurança.
2. **Filtros separados** trigger/calibração + `tri_need_cnt` — médio risco, melhora repetibilidade.
3. **shake + gap** — baixo risco.
4. **`bed_mesh_post_proc`** — médio/alto; precisa entender a matemática (está no `.so`, sem símbolos).
5. **Auto Z-offset (`z_compensate`)** — alto risco (encosta o bico), só depois de 1–4 estáveis.

## Reprodução

```sh
# estático
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
/opencode/meus_projetos/.rea-tools/tools/ghidra_12.1.4_PUBLIC/support/analyzeHeadless \
  /tmp/ghproj x -import prtouch_v2.so -scriptPath /opt/ghiscripts -postScript DumpDecomp.java -deleteProject

# dinâmico (dentro do rootfs do firmware, qemu)
PYTHONPATH=/tmp/opencode/dyn qemu-mipsel -L rootfs rootfs/usr/bin/python3 probe2.py extras.prtouch_v2_wrapper
```
