# Music Time 3.0.10 — Windows

- Recomendações locais com gêneros, afinidade nas playlists, época e favoritos.
- ListenBrainz opcional: token no cofre, música atual, scrobbles e fila persistente por conta.
- MusicBrainz opcional: identificação e gêneros dos artistas, com cache e limites de consulta, sem modificar arquivos.
- Configurações separadas para consultas externas, envios e uso de dados locais.
- Integração e chave Last.fm existentes preservadas. Novas integrações começam desativadas.

Conectar o ListenBrainz não exporta histórico anterior nem ativa uploads automaticamente.
Respostas de envio incertas não são repetidas automaticamente para evitar duplicatas.
Pano não foi integrado. Serviços externos são opcionais e dependem da disponibilidade dos provedores.

Testes de integração usam contas e respostas simuladas; não comprovam autorização de uma conta real.
Resultados de compilação, testes e instalação constam no manifesto de validação desta release.

- Last.fm agrupado em um único box, com divisões internas.
- Validação ListenBrainz com mensagens específicas, tratamento de falha do cofre e limpeza de espaços invisíveis/prefixo Token ao colar a credencial.
- Rejeição do token pelo serviço não é contornada; conexão somente após validação positiva.

- Insights com escolha entre Last.fm e ListenBrainz conectados, além do histórico local. Rankings, comparação de períodos, CSV e criação de playlists usam a fonte selecionada. ListenBrainz consulta períodos de até 365 dias; não varre todo o histórico.
