# Instalação em outro host (inclusive Raspberry Pi Zero 2 W)

Este pacote reproduz **exatamente** a configuração validada numa Ender-3 V3 SE com o firmware
`jpcurti` 1.0.1 (+ patches) e a célula de carga habilitada.

## O que é instalado

| peça | caminho |
|---|---|
| Klipper (fork `jpcurti`, tag 1.0.1 + patch (1 commit, ver patches/)) | `/opt/klipper-v3se/klipper` (venv em `klipper-env`) |
| Moonraker | `/opt/klipper-v3se/moonraker` (venv em `moonraker-env`) |
| Fluidd (nginx :80) | `/var/www/fluidd` |
| Dados | `/opt/klipper-v3se/printer_data/{config,logs,gcodes,comms}` |
| Units | `klipper.service`, `moonraker.service` |

Não usa qemu nem binário MIPS: o Klipper roda **nativo** na arquitetura do host.

## 1. Preparar o host

### Raspberry Pi Zero 2 W (recomendado para você)
1. Grave **Raspberry Pi OS Lite 64-bit** (Bookworm) no cartão.
2. Na primeira partição (`bootfs`), crie um arquivo vazio `ssh` e um `wpa_supplicant.conf` se for Wi-Fi.
3. Boot, descubra o IP, entre por SSH (`ssh pi@<ip>`).

Superfície mínima: ~1,5 GB livres (Klipper + venvs + Fluidd). RAM de 512 MB é suficiente —
Klipper nativo + Moonraker + nginx ficam em ~180 MB.

### x86 / outros ARM
Debian 12/13 (ou Ubuntu 22.04+) com SSH. Mesmos passos.

## 2. Copiar e executar

Do seu micro, envie o pacote:
```sh
scp -r KLIPPER-V3SE-hibrido-portable pi@<ip>:/tmp/
ssh pi@<ip> 'sudo sh /tmp/KLIPPER-V3SE-hibrido-portable/install.sh'
```

Se quiser já fixar a serial da impressora e compilar o firmware com HX71X:
```sh
sudo SERIAL=/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0 \
     sh /tmp/KLIPPER-V3SE-hibrido-portable/install.sh --build-firmware
```

O instalador termina imprimindo a URL do Fluidd.

## 3. Calibração (uma vez, 10 min)

No Fluidd ou por console:

| passo | comando | observação |
|---|---|---|
| 1 | `G28` | confirme o CR-Touch triggerando |
| 2 | `PID_EXTRUDER TARGET=210` | salva sozinho (`SAVE_CONFIG` reinicia) |
| 3 | `PID_BED TARGET=70` | idem |
| 4 | `MESH_CALIBRATE` | refaz 5×5 e **persiste** o perfil `default` |
| 5 | `AUTO_Z` | mede o contato pela célula e aplica o offset (guarde o valor; ele é a base do `z_offset`) |
| 6 | imprimir | `PRINT_START` carrega o mesh salvo e faz a purga |

Depois disso, o fluxo por peça é só `PRINT_START BED=.. EXTRUDER=..` → mesh carregado → imprime.
Refaça `MESH_CALIBRATE`/`AUTO_Z` apenas quando trocar bico, placa ou mexer na mesa.

O `AUTO_Z` é **sob demanda** de propósito (início de impressão rápido, ~40 s a menos por peça).
Para medir de novo antes de uma peça específica: `PRINT_START BED=.. EXTRUDER=.. AUTO_Z=1`.

O `pressure_advance: 0.03` já vem no `printer.cfg` (direct drive + PLA). Ele é um
**valor de partida**, não medido: valide nos cantos de um cubo e ajuste entre 0,02 e 0,04.
Se o material mudar (PETG), reavalie.

## 4. Fatiador (Orca)

**Start G-code**
```gcode
PRINT_START BED=[first_layer_bed_temperature] EXTRUDER=[first_layer_temperature]
```
**End G-code**
```gcode
PRINT_END
```
Não inclua `G28`/`G29`/`BED_MESH_CALIBRATE` no start — o `PRINT_START` já cuida.
Área 220×220, origem no canto frontal-esquerdo.

## 5. Firmware do MCU (se ainda não tiver HX71X)

O binário oficial 1.0.1 **não** lê a célula (falta `CONFIG_WANT_HX71X`). Para gerar o seu:
```sh
sudo sh install.sh --build-firmware
# gera /opt/klipper-v3se/e3v3se_klipper_hx71x.bin
```
Copie o `.bin` para a raiz de um microSD (FAT32), **com nome diferente do último gravado**, insira
na impressora desligada e ligue. A tela fica no logo ~30 s e reinicia.

Conferir se entrou: `mcu_version` no Fluidd deve mudar, e `hx711s`/`prtouch` devem existir.

## 6. Notas específicas do Zero 2 W

- Use **fonte 5 V / 2,5 A** dedicada; o Zero 2 W alimentando o CH340 da impressora pela USB é o
  cenário normal, mas evite hubs sem alimentação.
- A câmera RTSP que você vai usar depois roda fora do Klipper (Moonraker só aponta a URL em
  `[webcam]`) — não consome CPU do host.
- Se quiser refazer o mesh com mais frequência, reduza `probe_count` para `4,4` (11 pontos) — o
  `MESH_CALIBRATE` com 5×5 leva ~2 min por causa do retract de 10 mm entre pontos.

## 7. Rollback

- Configs antigas: `backups/` (gerado na máquina original) ou `*.bak-*` na pasta de config.
- Firmware oficial: `rollback_v1.0.1.bin` (mesmo processo de SD).
