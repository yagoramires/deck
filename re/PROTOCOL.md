# fifine AmpliGame D6 — protocolo (MiraBox/StreamDock)

Verificado no dispositivo em 2026-10-23 (firmware `V2.D6.00.002`), salvo onde marcado *estático*.

## Dispositivo
- USB VID `0x3142`, PID `0x0007`, serial `XXXXXXXXXXXX`.
- Uma interface HID, usage page `0xFFA0`, usage 1 (coleção interna usage 2 — mesma interface).
- Input e output de 512 bytes, sem report ID, sem feature report.
- Pode ser aberto sem exclusividade; o app oficial precisa estar fechado (ele segura o device).

## Saída (Mac → deck)
Todo pacote é preenchido com zeros até 512 bytes. `.` = 0x00.

| Comando | Bytes | Status |
|---|---|---|
| Acordar tela | `CRT..DIS` | verificado |
| Brilho das telas | `CRT..LIG..` + `[10]=0–100` | verificado (escrita) |
| Limpar tecla | `CRT..CLE...` + `[11]=slot` (`0xff` = todas) | verificado |
| Imagem | `CRT..BAT` + tamanho JPEG (4 bytes big-endian) + slot; depois o JPEG em pedaços de 512; depois `CRT..STP` | verificado |
| Modo | `CRT..MOD..` + `[10]='2'` conectado / `'1'` desconectado (degradê padrão) | `'1'`: estático; `'2'`+limpar: verificado |
| Desligar tela | `CRT..HAN` | estático |
| Heartbeat | `CRT..CONNECT` | estático |
| Versão | `CRT..VER` (sem resposta via input report) | estático |

Imagens: JPEG 112×112, **giradas 180°**.

Ao assumir o deck (igual ao `refreshDisplay` oficial): `MOD '2'` + `CLE 0xff` antes de desenhar, senão fica o degradê de "desconectado" atrás das teclas. O app oficial manda `MOD '1'` ao fechar.
Abrir app/site: o oficial usa `/usr/bin/open -a`; NSWorkspace num app de barra inativo não traz app já aberto pra frente.

### Mapa de slots (imagem ≠ entrada)
- Entrada: tecla `k` = linha `(k-1)/5` de cima pra baixo, coluna `(k-1)%5`.
- Slot de imagem pra mesma tecla física: `(2 - linha) * 5 + coluna + 1` (as linhas são invertidas).

## Entrada (deck → Mac)
`ACK..OK..` + `[9]=tecla 1–15` + `[10]=1 apertou / 0 soltou`.

## RGB — NÃO funciona por software neste firmware
Testados sem efeito (a luz continua laranja; o botão físico do deck controla):
- `[65,100,18, R,G,B ×18]` cru, com prefixo `CRT`, `CRT..` e `CRT..SETLB` (formato real do app: `SDDeviceDisplayWidget::addLampControlCommand_SETLB`).
- `CRT..QUCMD` + `0x11` (ligar) / `0xff` (desligar).
- `CRT..CONNECT` antes.

O botão físico de RGB (separado, 9 modos, toque longo liga/desliga) troca o modo mas **não gera nenhum input report** (60s escutando).
Indício forte de que o anel RGB tem controlador próprio, fora do caminho USB do MCU principal.
Firmware do D6 não é publicado: manifestos `cdn1.key123.vip/.../firmware-version-*.json` não têm D6; o bucket OSS nega listagem.

Fonte do formato: plugin oficial `com.mirabox.streamdock.lampControlD6` (cdn.key123.vip/plugin/Utilities/…), 18 LEDs, efeitos calculados no host a 10 fps.
O app oficial não lista o D6 entre os dispositivos com RGB (`LightSpripColor::supportedDeviceVpids`).
