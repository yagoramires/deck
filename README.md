# Deck

Configura o fifine AmpliGame D6 (15 teclas com tela) pela barra de menus do macOS, sem o app oficial da fifine.

## Instalar

Hoje a instalação é por build local (veja **Build local**): rode `scripts/setup-signing.sh` uma vez e depois `scripts/build.sh --run`. Requer macOS 14 ou mais novo.

Instalador `.dmg` e instalação pelo NeyHub chegam na próxima versão.

## Permissões

- **Acessibilidade**: só para as teclas com ação de **Atalho de teclado**, que simulam teclas no Mac. O macOS pede na primeira vez que uma dessas teclas é usada.
- O Deck fala com o D6 direto por USB (HID) e não precisa de mais nenhuma permissão. O app oficial da fifine precisa estar fechado, porque ele segura o deck; o Deck avisa quando ele está aberto e tem o botão **Fechar ele**.

## Como usar

Clique no ícone do Deck na barra de menus. O popover mostra se o D6 está conectado, o controle de brilho das telas, as páginas e a grade de 15 teclas (3 linhas de 5).

- Clique numa tecla pra configurar. Arraste uma tecla pra trocar de lugar, ou solte uma imagem em cima dela pra virar o ícone.
- Ações de cada tecla: **Nada**, **Abrir app**, **Abrir site**, **Atalho de teclado** (grave a combinação), **Tecla de mídia** (volume, mudo, tocar/pausar, próxima e anterior), **alternar saída de áudio** entre dois dispositivos (A e B, cada um com sua imagem) e **próxima/anterior página**.
- Ícone: **Imagem…**, o ícone do app, e o **Estilo neon**.
- Várias páginas: **Nova página** e **Apagar** na barra de páginas.
- **Importar do app da fifine** traz as páginas e teclas que você já tinha configurado lá (troca as páginas daqui pelas dele).
- O Deck reenvia as imagens quando o D6 conecta ou o Mac acorda, e apaga as telas ao dormir.
- Na primeira abertura, o Deck se registra pra abrir ao iniciar a sessão; dá pra mudar em **Abrir ao iniciar**, no rodapé.

A configuração fica em `~/Library/Application Support/Deck/config.json` e o log em `~/Library/Logs/Deck/deck.log`.

## Atalhos

O Deck não tem atalho global. As teclas do próprio D6 disparam as ações configuradas; a ação **Atalho de teclado** simula a combinação que você gravar.

## Modos de exibição

O Deck não tem temas. O brilho das telas do D6 é ajustado no popover (de 10 a 100) e cada tecla pode ter o **Estilo neon** no ícone.

## Atualizações

O Deck ainda não se atualiza sozinho: para atualizar, baixe o código novo e rode o build de novo (veja **Build local**).

## Build local

Precisa só das Command Line Tools (`xcode-select --install`), não do Xcode.

```sh
scripts/setup-signing.sh   # uma vez: certificado local de assinatura
scripts/build.sh --run     # compila, assina e abre build/Deck.app
```

O protocolo do D6, levantado no dispositivo, está em [re/PROTOCOL.md](re/PROTOCOL.md). O RGB não é controlável por software neste firmware.

`build/Deck.app/Contents/MacOS/Deck --selftest` roda as verificações internas.

> O SDK atual transformou `@State` num macro cujo plugin só vem com o Xcode; as telas usam um contorno próprio que faz a mesma coisa.

## Patch notes

Veja o [CHANGELOG](CHANGELOG.md).

## Licença

[MIT](LICENSE)
