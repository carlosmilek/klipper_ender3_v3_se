# Contribuição para os forks (`jpcurti/ender3-v3-se-klipper-with-display` e `0xD34D/ender3-v3-se-klipper-config`)

Tudo abaixo foi levantado em bancada numa **Ender-3 V3 SE** real, com o firmware
`e3v3s3_klipper_with_display_v1.0.1`, e validado com impressão.

---

## 1. Bugs encontrados (com patch)

### 1.1 `PRTOUCH_PROBE_ZOFFSET` quebra no fim — `probe_result` virou namedtuple

**Sintoma**
```
TypeError: 'probe_result' object does not support item assignment
Transition to shutdown state: Internal error on command:"PRTOUCH_PROBE_ZOFFSET"
```
O cálculo inteiro roda (mede o trigger do CR-Touch **e** o contato do bico pela célula, imprime
`Nozzle z_offset`/`Calculated z_offset`/`z_adjust`) e só explode na última linha, ao mutar o
`probe_result` devolvido por `probe.run_single_probe()` — que no Klipper atual é `namedtuple`.

**Patch** `0002-prtouch-fix-probe_result-imutavel-Klipper-novo-em-PR.patch`
```python
-        z_probe[2] = homing_origin[2] + z_adjust - start_z_offset
-        self.probe_calibrate_finalize(z_probe)
+        z_probe_final = [z_probe[0], z_probe[1], homing_origin[2] + z_adjust - start_z_offset]
+        self.probe_calibrate_finalize(z_probe_final)
```

### 1.2 Falta um auto-Z utilizável (o equivalente ao `z_compensate` do firmware oficial)

O `prtouch.py` do fork só oferece `PRTOUCH_PROBE_ZOFFSET`, cuja fórmula (`z_offset + start_z_offset`)
produziu `z_adjust = 0.970` numa máquina cujo contato real era 0,16 mm — valor que, aplicado,
afastaria o bico ~1 mm da mesa.

**Feature** `0003`…`0005`: comando `PRTOUCH_AUTO_Z`
```python
def cmd_PRTOUCH_AUTO_Z(self, gcmd):
    self._ck_g28ed()
    if gcmd.get_int('CLEAR_NOZZLE', 0) == 1:
        self.clear_nozzle(...)
    x = sensor_x + random(...); y = sensor_y + random(...)
    self._move([x, y, bed_max_err + 1.], g29_xy_speed)
    z_contact = self.probe_z_offset(x, y)          # contato do bico, medido pela celula
    self.obj.gcode.run_script_from_command('SET_GCODE_OFFSET Z_ADJUST=%f MOVE=1' % z_contact)
```
Semântica: com o offset atual `X`, o bico toca a mesa em `Z=z_contact`; logo a correção é
`Z_ADJUST = +z_contact` (Klipper: `toolhead = gcode + offset`).

**Validação**: contato medido 0,16–0,43 mm (varia com temperatura); após aplicar, o teste do papel
agarra em `Z=0`. Repetibilidade da célula: **range 0,0125 mm / σ 0,0050** com `PRTOUCH_ACCURACY
SAMPLES=5`.

### 1.3 Sanidades do `prtouch_v2` que o v1 não tem

O módulo fechado do firmware oficial (`prtouch_v2_wrapper`, Cython) tem 16 códigos de erro `key520..key535`.
Portamos os que dependem só de dados já disponíveis, **com os mesmos textos/chaves**:

| sanidade | código | comportamento |
|---|---|---|
| valor constante no canal | `key521` | aborta |
| pressão excessiva (`> press_max_factor × max_hold`) | `key525` | aborta |
| ruído (`p2p > pres_noise_max × max_hold`) | `key524` | loga (opcional abortar) |
| intervalo de leitura `> max_read_ms` (11) | `key520` | loga (opcional abortar) |
| perda de passo (`up_all > max_step_ratio × cmd`) | `key526` | loga |

Patch `0001`. Também adiciona `PRTOUCH_SANITY` (mostra limiares e últimas medidas).

### 1.4 `e3v3se_display`: handler de erro do MCU derruba o klippy

Dois problemas no mesmo handler:

```
TypeError: E3v3seDisplay.handle_mcu_error() takes 1 positional argument but 3 were given
Transition to shutdown state: Unhandled exception during run
```

O Klipper chama os handlers de `klippy:notify_mcu_error` com `(msg, details)`, mas a função
foi declarada como `def handle_mcu_error(self)`. Resultado: **um erro recuperável de MCU vira
shutdown do klippy**.

E, quando consegue chamar o popup, aparece:

```
E3V3SE Display: Error in show_popup: 'tuple' object has no attribute 'expandtabs'
```
porque `get_state_message()` devolve tupla no Klipper atual.

Correção (`patches/0002-display-fix.patch`):
```python
def handle_mcu_error(self, *args):
    state_message = self.printer.get_state_message()
    if isinstance(state_message, (tuple, list)):
        state_message = " ".join(str(s) for s in state_message)
    self.show_popup(state_message)
```

---

## 2. Firmware do MCU: o `.config` do CI não habilita a célula de carga

`test/configs/displayv3se.config` (usado por `scripts/edited-ci-build.sh`) **não** tem
`CONFIG_WANT_HX71X`, então o binário publicado **não lê o HX711** — `[hx711s]`/`[prtouch]` falham ao
subir e o strain gauge fica inutilizável.

Build correto (validado, 46.292 B):
```sh
cp test/configs/displayv3se.config .config
printf 'CONFIG_WANT_HX71X=y\n' >> .config   # ou menuconfig -> "Support HX711 and HX717 ADC chips"
make olddefconfig && make
arm-none-eabi-nm out/klipper.elf | grep hx71   # command_config_hx711s, command_query_hx71x, ...
```
Pinos no V3 SE: `sclk=PA4`, `dout=PC6`.

---

## 3. Armadilhas de configuração (não são bugs, mas custam horas)

1. **`probe_with_touch_mode: true` + `stow_on_each_sample: false`** — valores que o firmware oficial usa
   (porque o Z dele é a célula). Em CR-Touch comum com Klipper aberto isso **quebra**: sem retract
   entre amostras aparece `Probe triggered prior to movement` e `No trigger on probe after full
   movement`. Usar `probe_with_touch_mode: False`, `stow_on_each_sample: True`, `speed: 5`.
2. **`homing_retract_dist: 2.0`** (do `0xD34D`) é pouco: o pino não tem curso para re-deployar
   entre a primeira e a segunda passada do homing → o bico desce na mesa. Usar **10**.
3. **`z_offset` não se copia**: o `2.65` do 0xD34D numa máquina cujo real era 0,72…0,92 fez o bico
   afundar ~1,9 mm. Medir (papel, `PROBE_CALIBRATE` ou a célula).
4. **`position_min: 0`** no Z é uma trava útil durante bring-up, mas "camufla" falta de trigger
   (`No trigger on probe after full movement` em vez de afundar). Em produção: `-3`.
5. **`max_extrude_cross_section`** ausente no `[extruder]` → `ADAPTIVE_LINE_PURGE` **pula em
   silêncio**. Definir `max_extrude_cross_section: 5`.
6. **`SAVE_CONFIG`**: o bloco `#*#` tem de ser a **última** coisa do `printer.cfg`. Incluir arquivos
   depois dele faz o `[heater_bed]` "perder" o `control` (`Option 'control' ... must be specified`).
7. **Perfil de mesh não persiste sozinho**: `BED_MESH_PROFILE SAVE=default` + `SAVE_CONFIG` é o que
   grava `#*# [bed_mesh default]`. Sem isso, `BED_MESH_PROFILE LOAD=default` falha com
   `Unknown profile [default]` e um `PRINT_START` que só carrega o mesh aborta.
8. **Incluir macros com `[virtual_sdcard]`/`[respond]`** dentro de arquivos de macro pode
   sobrescrever a seção principal (ex.: `path: /usr/data/...` do firmware oficial) — Moonraker acusa
   `GCode path ... does not match expected location`.
9. **`M118`** exige `[respond]` habilitado.

---

## 4. Como validamos (reprodutível)

- **Firmware/rootfs**: extração do OTA oficial (7z com cabeçalho cifrado; senha derivada
  `md5crypt("<BOARD>C3_7e_bz","cxswfile")`), kernel 4.4.94 MIPS, rootfs Buildroot.
- **Desassembly dos `.so` fechados** (`prtouch_v2_wrapper`, `z_compensate_wrapper`): Ghidra com
  decompilador `linux_arm_64` (a release oficial não traz; é preciso compilar ou usar uma cópia que
  tenha) + `gcompat` em Alpine. 361/362 e 276/276 funções.
- **Introspecção dinâmica** (o que rendeu mais, porque Cython apaga símbolos): importar o `.so` no
  Python 3.8 do próprio firmware sob `qemu-mipsel`, com `config`/`printer` falsos que registram cada
  leitura → daí saíram os 40 parâmetros e os 16 códigos de erro.

---

## 5. O que ainda falta (para quem quiser continuar)

- `bed_mesh_post_proc`: cruza o mesh do CR-Touch com as medidas da célula e corrige/valida
  (`check_bed_mesh_max_err = 0.2`, erro `key533`). Precisa de um stub de MCU (`create_oid`) para
  introspecção dinâmica, ou de mais hops no Ghidra para achar a função no Cython.
- Medição de *gap* bico↔mesa (`z_gap_spd`, `gap_dis_range`) — existe no v2, não no v1.
- `tri_need_cnt` (N janelas concordando antes de triggerar) — reduz falso positivo.

---

## 6. Arquivos

- `patches/0001..0005*.patch` — série pronta para `git am` sobre a tag **1.0.1**.
- `config/` — configs validadas (sem o bloco `#*#`, que é específico de cada máquina).
- `../DOSSIER_OFICIAL.md`, `../ANALISE_PATOUCH_V2.md`, `../CONFIGS_E_ORIGEM.md` — evidências.

10. **Nunca distribua um `printer.cfg` com `control`/`pid_*` comentados.** É exatamente o que o
    `SAVE_CONFIG` faz: ele comenta as linhas originais e move os valores para o bloco `#*#` no fim
    do arquivo. Se alguém empacotar a config "limpa" (sem esse bloco), o `[extruder]`/`[heater_bed]`
    ficam sem `control` e a impressora haltá com:

    ```
    Option 'control' in section 'heater_bed' must be specified
    ```

    Achado num teste de instalação do zero (host novo), não numa atualização — por isso passou
    despercebido antes.

---

## 7. Convenção de sinal do `PRTOUCH_AUTO_Z` (fácil de errar)

`PRTOUCH_AUTO_Z` imprime `contato=z_c` (o `Z` do gcode no instante em que a célula sente o bico na
mesa) e aplica `SET_GCODE_OFFSET Z_ADJUST=z_c`.

Relação com o `z_offset` da config (Klipper: `toolhead = gcode + offset`, e no trigger
`gcode = z_offset` com físico `h`):

```
h = z_offset_config - z_c
```

Exemplo real desta bancada: com `z_offset: 0.72` o `AUTO_Z` mediu `z_c = -0.045` →
verdadeiro offset **h = 0,765**. Gravando `z_offset: 0.765` e rodando `AUTO_Z` de novo,
o resíduo tem de ficar **≈ 0,000** — é o auto-teste de que o valor persistido é o que a
máquina mediu (e não um número ajustado à mão).

Regra prática: **o número final é sempre o que a célula mediu**; o papel serve só para
conferir a ordem de grandeza.
