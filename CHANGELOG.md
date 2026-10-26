# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [0.2.0] - 2026-10-25

### Adicionado
- Instalação pelo NeyHub (`Deck-0.2.0.neyplugin`): o Deck roda dentro dele, com a mesma configuração e os mesmos ícones, e a Acessibilidade é a do NeyHub.
- Instalador `.dmg` e atualização automática no avulso: baixa sozinho e troca o app quando você fecha o Deck (ou em **Reiniciar agora**), com a janela **Novidades** na abertura seguinte.
- Tela do Deck (modo Janela no avulso e tela dentro do NeyHub): o D6 com as 15 teclas na posição real, páginas em abas e o editor da tecla sempre aberto ao lado.
- Configurações (em **Configurações…**, no rodapé do popover): onde o Deck aparece (janela com ícone no Dock, barra de menus ou os dois, sem reiniciar) e o estado da Acessibilidade.

### Alterado
- Ícone novo no padrão do NeyHub: o mesmo desenho, em fundo grafite com detalhe verde-limão.
- Visual no tema Grafite (escuro, acento verde-limão), com a mesma navegação de antes.
- Se o NeyHub já roda o Deck, o avulso avisa, sai dos itens de login e fecha.
- Ao fechar (ou desinstalar no NeyHub), o Deck apaga as telas e solta o D6, pra outro app poder abrir.
- O build exige o certificado "Aero Local Signing" (sem assinatura ad-hoc).
- Menu **Editar** do avulso: desfazer, recortar, copiar, colar e selecionar tudo (`⌘Z`, `⌘X`, `⌘C`, `⌘V`, `⌘A`) nos campos de texto.

## [0.1.0] - 2026-10-25

### Adicionado
- Primeira versão: configura o fifine AmpliGame D6 (15 teclas com tela) pela barra de menus.
- Ações por tecla: abrir app, abrir site, atalho de teclado, tecla de mídia, alternar saída de áudio e trocar de página.
- Ícone de cada tecla por imagem ou ícone do app, com estilo neon.
- Várias páginas, brilho das telas e troca de teclas por arraste.
- Importa a configuração do app da fifine.
- Abre ao iniciar a sessão.
