# Listening Insights

[README](../README.md) · [Release notes](release-2.2.0.md)

1. In **Settings → Integrations → Last.fm**, configure your API key and public profile username. Do not share keys or passwords in issues. Public reading does not require authorizing a scrobbling session.
2. Open **Listening Insights** below History. Choose an exact 7/30/90/180/365-day window, all time or custom dates.
3. Review Overview, Artists, Albums, Tracks and Reports. Rankings and counts belong to Last.fm, including scrobbles from other apps; local history/counts remain separate.
4. Use **Create playlist** to select most-played, balanced artists or previous-period rediscovery. Set a track count, per-artist limit and optional offline restriction. Review missing and ambiguous tracks against your own library.
5. **Save playlist** saves a manual snapshot without playback. **Play now** starts only a queue. Unresolved items are explicitly excluded; nothing is downloaded from Last.fm.
6. **Export CSV** saves loaded rankings, local daily activity, UTC boundaries and coverage to a file you choose. Reports can be grouped by week, month or year; boundary groups may contain only part of that week/month/year.

The app preserves current results during refresh. Requests can be cancelled; results from old profiles/periods are ignored. Cached reports are reused for 15 minutes and can be read offline; Refresh forces a network update. Up to six derived reports of at most 8 MiB each are retained. Larger results remain in the current session without replacing the saved cache. This derived cache is excluded from backups and discarded by restore/reset.

Up to 250 pages (200 events per page) are read per operation, including the previous comparison period. **Partial coverage** means counts cover loaded data, not the whole period. Use **Load more history** to continue. Comparisons and rediscovery require complete valid coverage; currently-playing entries do not count as scrobbles. Last.fm history may change during reading; no transactional server snapshot is guaranteed.

No PDF export, recurring playlist refresh or smart-playlist rule engine is included. Actual listening hours are not inferred from track length. Live-account verification remains separate from controlled tests. The screenshot contains fictional listening data.

## Português brasileiro

Em **Configurações → Integrações → Last.fm**, informe a chave e o usuário do perfil. Abra **Estatísticas de escuta** abaixo de Histórico, escolha o intervalo e consulte rankings, atividade e relatórios. Os dados são do Last.fm, sem incrementar contagens locais.

**Criar playlist** abre a prévia para ajustar quantidade, limite por artista e faixas disponíveis offline. Revise as pendências: **Salvar playlist** grava uma lista manual; **Reproduzir agora** inicia somente uma fila. CSV exporta os dados carregados com indicação de cobertura. Leituras parciais podem continuar pelo botão de carregar mais histórico. Cache offline, limites de leitura e aceite real seguem as condições acima.