# Deck

Configura o fifine AmpliGame D6 (15 teclas com tela) pela barra de menus do macOS, sem o app oficial da fifine.

[Baixar a última versão](https://github.com/yagoramires/deck/releases/latest) · [Reportar problema](https://github.com/yagoramires/deck/issues/new)

## Instalar

1. Baixe o `Deck-x.y.z.dmg` (ou o `.zip`) na [página de releases](https://github.com/yagoramires/deck/releases/latest) e arraste o **Deck.app** pra pasta **Aplicativos**.
2. Abra o Deck. Como ele não é assinado com um certificado pago da Apple, na primeira vez o macOS avisa que não conseguiu verificar o desenvolvedor. Vá em **Ajustes do Sistema → Privacidade e Segurança**, role até o fim e clique em **Abrir Mesmo Assim**. No macOS 14 também dá para clicar com o botão direito no app → **Abrir** (a partir do macOS 15 esse atalho não libera mais o app). Pelo Terminal também resolve: `xattr -dr com.apple.quarantine /Applications/Deck.app`
3. Feche o app oficial da fifine (ele segura o deck). Na primeira abertura, o Deck importa a configuração dele e entra nos itens de início.

Requer macOS 14 ou mais novo. Roda nativo em Apple Silicon e Intel. Também dá pra compilar do código (veja **Build local**).

### Pelo NeyHub

Quem usa o [NeyHub](https://github.com/yagoramires/neyhub) pode instalar o Deck pela Loja dele (o `Deck-x.y.z.neyplugin` do release). Aí o Deck roda dentro do NeyHub, com a mesma configuração do avulso (`config.json` e `icons/`): o ícone e o popover da barra são os mesmos, a **tela do Deck** aparece na janela do NeyHub, a Acessibilidade é a do NeyHub (pela tela **Permissões**), o NeyHub cuida do login, das atualizações e de mostrar ou esconder o ícone, e o popover não tem **Abrir ao iniciar**, **Configurações…**, **Sair** nem a linha **Atualização pronta**. Feche o Deck avulso antes: se o NeyHub já roda o Deck, o avulso avisa (um aviso só), sai dos itens de login e fecha. Desinstalar pelo NeyHub apaga as telas do D6 e solta o dispositivo na hora, pro avulso (ou o app da fifine) poder abrir de novo.

### Desinstalar

1. No popover, desligue **Abrir ao iniciar** e clique em **Sair**.
2. Apague o **Deck.app** de Aplicativos. Pelo NeyHub, é só desinstalar no card do Deck.
3. A configuração continua em `~/Library/Application Support/Deck/`. Pra apagar tudo (sem volta): `rm -rf ~/Library/Application\ Support/Deck ~/Library/Logs/Deck; defaults delete local.deck`

## Permissões

- **Acessibilidade**: só para as teclas de **Atalho de teclado** e **Tecla de mídia**, que simulam teclas no Mac. No avulso, o macOS pede na primeira vez que uma dessas teclas é usada. Dentro do NeyHub a permissão é do NeyHub e o Deck nunca pede ao sistema: com uma dessas teclas configurada e sem a permissão, o popover e a tela mostram **Precisa de Acessibilidade** com **Conceder**, que abre a tela **Permissões** do NeyHub.
- O Deck fala com o D6 direto por USB (HID) e não precisa de mais nenhuma permissão. O app oficial da fifine precisa estar fechado, porque ele segura o deck; o Deck avisa quando ele está aberto e tem o botão **Fechar o app da fifine**.

### Privacidade

A configuração e os ícones ficam só no seu Mac, em `~/Library/Application Support/Deck/`. A única conexão de rede é a consulta à API pública do GitHub (`api.github.com`) pra saber se tem versão nova, e o download dela. O log de depuração (`~/Library/Logs/Deck/deck.log`) também fica só no seu Mac.

## Como usar

Clique no ícone do Deck na barra de menus. O popover mostra se o D6 está conectado, o controle de brilho das telas, as páginas e a grade de 15 teclas (3 linhas de 5).

- Clique numa tecla pra configurar. Arraste uma tecla pra trocar de lugar, ou solte uma imagem em cima dela pra virar o ícone.
- Ações de cada tecla: **Nada**, **Abrir app**, **Abrir site**, **Atalho de teclado** (grave a combinação), **Tecla de mídia** (volume, mudo, tocar/pausar, próxima e anterior), **Alternar saída de áudio** entre dois dispositivos (A e B, cada um com sua imagem) e **Próxima/Página anterior**.
- Ícone: **Imagem…**, o ícone do app, e o **Estilo neon**.
- Várias páginas: **Nova página** e a lixeira na barra de páginas.
- **Importar do app da fifine** traz as páginas e teclas que você já tinha configurado lá (troca as páginas daqui pelas dele).
- **Tela do Deck** (modo **Janela**, ou a tela do Deck dentro do NeyHub): o mesmo do popover, em tamanho grande. O D6 desenhado com as 15 teclas na posição real e o número de cada uma, as páginas em abas no topo (`‹ Página 1 2 3 › +`), o brilho, e o editor da tecla escolhida sempre aberto ao lado: a lista de ações, os campos da ação, o ícone (clique pra escolher ou solte uma imagem), o rótulo, o **Estilo neon** e **Limpar tecla**. Embaixo da grade, **Importar do app da fifine…**, **Apagar página** e o lembrete de arrastar. Com o D6 desconectado a grade continua editável; as teclas vão pro D6 quando ele voltar. Numa janela estreita, o editor vai pra baixo da grade.
- O Deck reenvia as imagens quando o D6 conecta ou o Mac acorda, e apaga as telas ao dormir e ao fechar.
- Na primeira abertura, o Deck se registra pra abrir ao iniciar a sessão; dá pra mudar em **Abrir ao iniciar**, no rodapé do popover.
- Quando uma versão nova já foi baixada, o popover mostra **Atualização pronta — entra ao sair**, com **Reiniciar agora**.

A configuração fica em `~/Library/Application Support/Deck/config.json` (com os ícones em `icons/`, o mesmo lugar no avulso e no NeyHub) e o log em `~/Library/Logs/Deck/deck.log`. O import lê, sem mudar nada, o perfil do app da fifine em `~/Library/Application Support/HotSpot/StreamDock/profiles`.

## Atalhos

O Deck não tem atalho global. As teclas do próprio D6 disparam as ações configuradas; a ação **Atalho de teclado** simula a combinação que você gravar. No modo **Janela**, `⌘,` abre as configurações e `⌘Q` fecha o Deck; nos campos de texto valem os atalhos de edição de sempre (`⌘Z`, `⇧⌘Z`, `⌘X`, `⌘C`, `⌘V`, `⌘A`), pelo menu **Editar**.

## Modos de exibição

O visual é o tema Grafite (escuro, com acento verde-limão), o mesmo do NeyHub. O brilho das telas do D6 é ajustado no popover e na tela (de 10 a 100) e cada tecla pode ter o **Estilo neon** no ícone.

Em **Configurações…** (no rodapé do popover) você escolhe onde o Deck aparece, e a troca vale na hora:

- **Barra de menus** (o padrão, como na 0.1.0): só o ícone com o popover.
- **Janela**: ícone no Dock e a tela do Deck. Clicar no ícone do Dock traz a janela de volta; o menu **Deck → Configurações…** (`⌘,`) abre as configurações.
- **Os dois**.

Desligar os dois não vale: o outro volta a ligar. O D6 funciona em qualquer modo, enquanto o Deck estiver aberto. Dentro do NeyHub o modo é escolhido no card do Deck, na Loja; sem escolha salva, lá o padrão é **Os dois**. Avulso e NeyHub guardam o modo no mesmo lugar.

## Atualizações

Desde a 0.2.0, o Deck confere 5 s depois de abrir e a cada 6 h se tem versão nova, baixa sozinho e só troca o app quando você fecha o Deck (ou clica em **Reiniciar agora**, no popover): nunca reinicia sozinho no meio do uso. Na próxima abertura, mostra uma vez a janela **Novidades** com o que mudou. A versão baixada só é instalada se tiver sido assinada pelo mesmo certificado do app em uso, então a Acessibilidade continua valendo. Dentro do NeyHub, quem atualiza é o NeyHub.

Quem está na 0.1.0 precisa instalar a 0.2.0 uma vez à mão (ela ainda não tinha atualização automática). A configuração e os ícones ficam onde estão.

## Build local

### Compilar

Só precisa das Command Line Tools (`xcode-select --install`), não do Xcode.

```sh
git clone https://github.com/yagoramires/deck.git && cd deck
scripts/setup-signing.sh   # uma vez: certificado local de assinatura (veja abaixo)
scripts/build.sh --run     # gera build/Deck.app e abre (fecha o Deck aberto antes)
scripts/selftest.sh        # testes; imprime "selftest ok"
```

O NeyKit (tema Grafite, `@ViewState`, contrato de plugin) e o NeyKitApp (atualização, novidades) vêm do checkout do
[neyhub](https://github.com/yagoramires/neyhub) ao lado (`../neyhub`); para outro lugar, defina `NEYHUB_PATH`.

O `setup-signing.sh` cria um certificado de assinatura local ("Aero Local Signing", o mesmo do Aero) no seu Chaveiro. A Acessibilidade e o item de login ficam presos à assinatura do app: com assinatura ad-hoc ela muda a cada build e o macOS para de confiar no app. Sem o certificado o build falha: o NeyHub só carrega plugins e as atualizações só entram com essa assinatura.

`build/Deck.app/Contents/MacOS/Deck --snapshots <pasta>` desenha o popover, a tela e as configurações em PNG com teclas de exemplo (numa pasta temporária, sem abrir o D6 nem tocar na configuração de verdade). `Deck --icon <entrada> <saída>` aplica o estilo neon numa imagem.

O protocolo do D6, levantado no dispositivo, está em [re/PROTOCOL.md](re/PROTOCOL.md) (a pasta `re/` fica fora do build). O RGB não é controlável por software neste firmware.

> O SDK atual transformou `@State` num macro cujo plugin só vem com o Xcode; as telas usam o `@ViewState` do NeyKit, que faz a mesma coisa.

### Como funciona

O miolo fica em `Sources/DeckCore` e é o mesmo no app avulso e no plugin do NeyHub:

| Arquivo | Papel |
| --- | --- |
| `DeckApp.swift` | Ícone e popover da barra, modos de exibição, configurações e `stop()` (desinstalar no NeyHub: grava, apaga as telas e solta o D6). Recebe os `UserDefaults`, se está hospedado e a versão. |
| `D6.swift` | O D6 por HID: abre, recebe as teclas e manda as imagens numa fila própria. O IOKit fica atrás do `HIDPort`, que o selftest troca por um falso. |
| `Model.swift` | Teclas e páginas em `config.json`, ícones em `icons/` e o import do app da fifine. |
| `Actions.swift` | O que cada tecla faz (apps, sites, atalhos, mídia, saída de áudio). Dentro do NeyHub só confere a Acessibilidade, nunca pede. |
| `Render.swift` | A imagem de cada tecla e o estilo neon. |
| `Views/` | O popover (`Root.swift`), as teclas e o editor (`Keys.swift`) e a tela de app (`ScreenView.swift`, que reaproveita os dois), em SwiftUI no tema Grafite do NeyKit. |
| `SettingsView.swift` | Configurações (janela do avulso e card no NeyHub). |
| `SelfTest.swift` | `--selftest` (rode com `scripts/selftest.sh`). Usa pasta temporária e um D6 falso. |
| `Snapshots.swift` | `Deck --snapshots <pasta>`. |

As cascas: `Sources/Deck` (app avulso: confere se o NeyHub já roda o Deck, atualização e novidades do NeyKitApp, e os modos `--selftest`, `--icon` e `--snapshots`) e `Sources/DeckPlugin` (o `libDeckPlugin.dylib` que o NeyHub carrega; linka só o NeyKit). O `Info.plist` declara `NeyHubAware = true` porque o avulso chama `HubCheck.leaveForHub` ao abrir: com essa chave o NeyHub não mostra o alerta dele quando o avulso abre.

### Publicar uma versão

1. Suba a versão em `Resources/Info.plist` (`CFBundleShortVersionString` e `CFBundleVersion`) e escreva a seção `## [x.y.z]` do `CHANGELOG.md` (vira a nota do release e a janela Novidades).
2. `scripts/release.sh` gera em `dist/` o `Deck-x.y.z.dmg`, o `Deck-x.y.z.zip` (o app, que a atualização automática baixa) e o `Deck-x.y.z.neyplugin` (o plugin do NeyHub). Só empacota.
3. Commit, push e `NEYHUB_CONFIRM_PUBLISH=yes scripts/release.sh --publish` para criar o release.

O release **precisa ser assinado com o mesmo certificado** das versões anteriores, senão os apps já instalados recusam a atualização automática.

## Patch notes

Veja o [CHANGELOG](CHANGELOG.md).

## Licença

[MIT](LICENSE)
