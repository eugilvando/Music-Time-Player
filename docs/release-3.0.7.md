# Music Time 3.0.7

## Reprodução e fila

- Nova tela inteira com fundo da capa desfocado, controles integrados e alternância entre Capa e Apenas letras. A barra inferior normal fica encoberta durante essa experiência; Escape ou o botão de sair restauram a janela anterior.
- Apenas letras usa um cabeçalho compacto com capa, título, artista e álbum. As letras ficam centralizadas; atualização e ajustes de sincronização continuam no menu de opções.
- A fila acompanha a faixa atual. Rolar manualmente pausa o acompanhamento; “Ir para a faixa atual” centraliza a faixa e retoma o acompanhamento.
- Cabeçalho com nome da playlist e fechar, barra com faixa atual/repetir/shuffle, e ações de salvar e opções da playlist. Os controles usam o mesmo estado do player.
- Faixa atual com fundo, borda e texto em destaque. Arrastar faixas ou álbuns permite soltar depois da última faixa, inclusive no espaço vazio abaixo da lista.
- Visualização, tamanho e densidade das faixas dentro de um álbum são independentes das miniaturas de álbuns no artista e no catálogo.

- O instalador Windows inclui a dependência Vulkan do motor de áudio, evitando depender da instalação prévia pelos drivers gráficos.

## Configurações

- Espaçamentos internos padronizados nos cards, listas e seções expansíveis das Configurações.
- Fontes locais recolhíveis. Fontes OneDrive com conexão/pasta/ações separadas, resumo da sincronização em blocos e detalhes de metadados recolhíveis.
- Downloads com contagem por grupo, mais espaço nas linhas e estados traduzidos.
- Sobre com identidade visual, versão real, verificação de atualização, links e informações legais recolhíveis.

Esta distribuição também inclui os ajustes 3.0.4–3.0.6: preparação e cache de letras com fallback, correções de backup com capas, dimensionamento de capas e otimizações de atualização do progresso e preparação do Smart Flow. A verificação no Sobre abre as releases públicas; download e instalação permanecem manuais.

## Instalação

Windows x64: `MusicTime-Setup-3.0.7.exe`. Ubuntu Desktop 24.04 amd64: `music-time-preview_3.0.7-0ubuntu1_amd64.deb`, publicado na release Ubuntu separada. O identificador Debian foi preservado para atualização das instalações existentes.

## Validação e limites

Testes usam catálogos fictícios. Consulte os manifestos em `release/` para os resultados e hashes finais de cada pacote. A aceitação em uma VM/partição Linux real, com os dispositivos de áudio do usuário, continua separada da validação automatizada. Os engasgos relatados em faixas reais não foram reproduzidos; esta versão não afirma resolver todos os casos de áudio.
