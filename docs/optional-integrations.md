# Integrações opcionais e funcionamento local

O Music Time mantém a conexão e a chave Last.fm existentes. ListenBrainz e
MusicBrainz são serviços independentes, desativados por padrão.

## Seleção local

O motor de artistas relacionados consulta o índice persistente do catálogo, sem
abrir arquivos de áudio nem imagens. Gêneros em comum são o sinal principal;
participação nas mesmas playlists é afinidade pessoal. Época e favoritos apenas
ajudam a ordenar candidatos: mesma época, isoladamente, não prova similaridade.
Resultados locais têm prioridade. Sem evidência local, o cache e as consultas
Last.fm permitidas continuam disponíveis. Mixes continuam restritos ao artista;
rádio e os modos existentes de fila/fluxo consomem artistas relacionados.

Até 100 consultas locais ficam em memória. Alterações no índice do catálogo,
nas playlists ou nos favoritos invalidam esse cache através de uma revisão no
SQLite. Não há recálculo por avanço da posição de reprodução.

“Usar apenas dados locais” impede novas consultas de metadados, rankings e
similaridades. Não desativa fontes de áudio na nuvem, letras, nem os envios
explicitamente habilitados. O modo offline geral também bloqueia envios.

## ListenBrainz

Configurações → Integrações contém validação do token e controles independentes
para música atual e reproduções. O token fica no cofre do sistema, nunca nas
preferências comuns. Conectar uma nova conta não habilita uploads.

O app usa o tempo efetivamente ouvido (metade da faixa ou quatro minutos; faixas
de até 30 segundos não são enviadas). Não exporta o histórico anterior. A fila
SQLite usa conta + faixa + início da execução como identidade. Desconectar
preserva pendências; outra conta não pode enviá-las. Reautorizar a conta permite
retomar pendências que exigiam autenticação.

Falhas temporárias ficam pendentes. Respostas incertas, inclusive uma interrupção
durante envio, ficam para revisão sem repetição automática para evitar duplicatas.
O painel apresenta os estados dos últimos 100 registros. Requests compartilham
uma fila limitada a um por segundo, respeitando o intervalo indicado pelo servidor.
Música atual não inclui timestamp e não substitui o registro da reprodução.

## MusicBrainz

Quando habilitado e não há candidatos locais, consulta a identidade do artista e
seus gêneros para procurar candidatos no catálogo. Exige correspondência única
e exata do nome normalizado; nomes ambíguos não são associados automaticamente.
Não escreve tags nos arquivos. Mantém identidade e gêneros em cache por 30 dias,
com consultas limitadas a uma por segundo e identificação do aplicativo.

Esse serviço fornece metadados, não scrobbling nem um ranking global equivalente
ao Last.fm. Histórico, favoritos e reprodução locais não dependem dele.

## Privacidade e backup

As novas preferências de integração entram na seção de provedores do backup;
a sessão ListenBrainz entra somente no backup de credenciais criptografado.
Filas de envio e caches são dados locais descartáveis e não são exportados como
histórico para evitar reenvio ao restaurar. Reset remove a sessão e os caches.

## Referências

- https://listenbrainz.readthedocs.io/en/latest/users/api/core.html
- https://listenbrainz.readthedocs.io/en/latest/users/json.html
- https://musicbrainz.org/doc/MusicBrainz_API

Pano não foi integrado. Envio de favoritos ao ListenBrainz, importação de histórico
antigo e recomendações remotas ListenBrainz ficam fora desta primeira integração.
