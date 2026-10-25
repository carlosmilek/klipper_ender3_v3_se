# Klipper híbrido para Ender-3 V3 SE

Klipper para a Ender-3 V3 SE combinando três referências:

- **firmware de fábrica da Creality** (`V1.1.0.29`) — engenharia reversa do rootfs MIPS e dos
  módulos Cython fechados (`prtouch_v2_wrapper`, `z_compensate_wrapper`);
- **comunidade** `0xD34D/ender3-v3-se-klipper-config` — pinos, CR-Touch, safe_z_home;
- **fork** `jpcurti/ender3-v3-se-klipper-with-display` — Klipper atual + display original via
  serial bridge no MCU.

## Conteúdo

| pasta | conteúdo |
|---|---|
| `patches/` | patch (1 commit, ver patches/) sobre a tag **1.0.1** do fork jpcurti (`git am`) |
| `config/` | configs validadas (printer, macros, macros da Creality, prtouch, moonraker) |
| `install.sh` | instala em `/opt/klipper-v3se` (Debian/RPi OS) e opcionalmente compila o MCU com HX71X |
| `docs/` | dossiê do firmware, PRTouch v2 × v1, proveniência das configs, guia de contribuição |
| `INSTALL.md` | passo a passo, incluindo Raspberry Pi Zero 2 W |

## Destaques

- **CR-Touch funcionando** no Klipper aberto (o `probe_with_touch_mode: True` do firmware oficial quebra clones).
- **Auto-Z pela célula de carga**: `PRTOUCH_AUTO_Z` mede o contato do bico e aplica `SET_GCODE_OFFSET`.
- **Sanidades do `prtouch_v2`** portadas para o `prtouch.py` aberto, com os mesmos códigos `key5xx`.
- **Firmware do MCU com `CONFIG_WANT_HX71X`** — o binário oficial não lê a célula.
- **`PRINT_START` rápido**: carrega o mesh salvo + purga (sem refazer mesh a cada peça).

## Uso

```sh
git clone https://github.com/<voce>/klipper-v3se-hybrid.git
cd klipper-v3se-hybrid
sudo SERIAL=/dev/serial/by-id/usb-XXXX sh install.sh
```

Calibração inicial: `PID_EXTRUDER`, `PID_BED`, `MESH_CALIBRATE`, `AUTO_Z`. Depois: fatiar → `PRINT_START`.

## Licença

Os patches derivam do Klipper (GPLv3). A documentação é livre.
