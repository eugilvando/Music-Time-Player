import '../domain/ports.dart';

import 'package:flutter/material.dart';

import '../sources/additional_sources.dart';
import '../sources/microsoft_auth.dart';
import 'ui_language.dart';

Future<void> addAdditionalSource(
  BuildContext context,
  AdditionalSources sources,
  String type,
  VoidCallback onChanged, {
  SourceConnection? connection,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _SourceForm(
    sources: sources,
    type: type,
    onChanged: onChanged,
    connection: connection,
  ),
);

class _SourceForm extends StatefulWidget {
  const _SourceForm({
    required this.sources,
    required this.type,
    required this.onChanged,
    this.connection,
  });
  final AdditionalSources sources;
  final String type;
  final VoidCallback onChanged;
  final SourceConnection? connection;
  @override
  State<_SourceForm> createState() => _SourceFormState();
}

class _SourceFormState extends State<_SourceForm> {
  final label = TextEditingController(),
      address = TextEditingController(),
      folder = TextEditingController(),
      user = TextEditingController(),
      password = TextEditingController(),
      client = TextEditingController(),
      secret = TextEditingController();
  bool busy = false, allowHttp = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final s = widget.connection;
    if (s != null) {
      label.text = s.label;
      address.text = s.address;
      folder.text = s.folder;
      user.text = s.username;
      client.text = s.clientId;
      allowHttp = s.allowHttp;
    }
  }

  @override
  void dispose() {
    for (final field in [
      label,
      address,
      folder,
      user,
      password,
      client,
      secret,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final source =
          widget.connection ??
          SourceConnection(
            id: secureRandomString(),
            type: widget.type,
            label: label.text.trim().isEmpty
                ? additionalSourceTypes[widget.type]!
                : label.text.trim(),
            address: address.text.trim(),
            folder: folder.text.trim(),
            username: user.text.trim(),
            clientId: client.text.trim(),
            allowHttp: allowHttp,
          );
      await widget.sources.add(
        source,
        password: password.text,
        clientSecret: secret.text.trim(),
        reconnect: widget.connection != null,
      );
      if (!mounted) return;
      widget.onChanged();
      Navigator.pop(context);
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is MediaSourceFailure ? failure.message : 'Could not connect. Check the address, credentials and provider registration, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(
    TextEditingController controller,
    String name, {
    String? hint,
    bool obscure = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: controller,
      enabled: !busy,
      readOnly: widget.connection != null && !obscure,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: !obscure,
      decoration: InputDecoration(
        labelText: ui(context, name),
        helperText: hint == null ? null : ui(context, hint),
        helperMaxLines: 4,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      '${ui(context, widget.connection == null ? 'Adicionar' : 'Reconnect')} ${additionalSourceTypes[widget.type]}',
    ),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            field(label, 'Source name'),
            if (widget.type == 'google') ...[
              const UiText(
                'Register an OAuth desktop application in Google Cloud, enable the Drive API and allow your account on the consent screen. Music Time requests read-only access through your browser.',
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => openSystemBrowser(
                        Uri.parse(
                          'https://developers.google.com/identity/protocols/oauth2/native-app',
                        ),
                      ),
                child: const UiText('Google desktop OAuth setup'),
              ),
              field(client, 'Desktop OAuth client ID'),
              field(
                secret,
                'Desktop client secret (if required by Google)',
                obscure: true,
              ),
              field(
                folder,
                'Music folder ID (optional)',
                hint: 'Leave empty for My Drive. A folder ID is the final part of its Google Drive URL. Subfolders are included.',
              ),
            ] else ...[
              field(
                address,
                widget.type == 'smb'
                    ? 'UNC music folder'
                    : 'Server / music folder URL',
                hint: widget.type == 'smb'
                    ? r'Example: \\server\share\Music. Use Windows Credential Manager for authentication.'
                    : widget.type == 'webdav'
                    ? 'Enter the full WebDAV music folder URL, including any server path.'
                    : 'Include the server base path when applicable, for example https://server/emby/.',
              ),
              if (widget.type != 'smb') ...[
                field(user, 'Username'),
                field(password, 'Password', obscure: true),
                if (widget.type != 'webdav')
                  field(
                    folder,
                    'Library folder ID (optional)',
                    hint: 'Leave empty to include the audio library accessible to this user.',
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const UiText('Allow HTTP for this server'),
                  subtitle: const UiText(
                    'HTTP sends credentials and audio without encryption. Use only on a trusted network.',
                  ),
                  value: allowHttp,
                  onChanged: busy || widget.connection != null
                      ? null
                      : (v) => setState(() => allowHttp = v),
                ),
              ],
            ],
            const UiText(
              'Credentials are stored in the system vault and excluded from backups. Synchronization reads the source without modifying your music files.',
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
            if (error != null)
              UiText(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const UiText('Cancelar'),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: Text(
          widget.type == 'google' ? 'Connect in browser' : 'Save connection',
        ),
      ),
    ],
  );
}

class AdditionalSourceSettings extends StatelessWidget {
  const AdditionalSourceSettings({
    super.key,
    required this.sources,
    required this.onChanged,
  });
  final AdditionalSources sources;
  final VoidCallback onChanged;
  Future<void> run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
      onChanged();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: UiText('Source unavailable. Check its status and retry.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: sources,
    builder: (context, _) => Column(
      children: [
        for (final source in sources.connections)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    source.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(additionalSourceTypes[source.type]!),
                  if (sources.busy.contains(source.id))
                    const LinearProgressIndicator(),
                  UiText(
                    !source.connected
                        ? 'Disconnected. Reconnect to restore access to your library and playlists.'
                        : sources.messages[source.id] ?? 'Ready. Synchronize to check this connection and update the catalog.',
                  ),
                  Wrap(
                    spacing: 12,
                    children: [
                      TextButton.icon(
                        onPressed: !source.connected
                            ? null
                            : () => sources.busy.contains(source.id)
                                  ? sources.cancel(source.id)
                                  : run(context, () => sources.sync(source)),
                        icon: Icon(
                          sources.busy.contains(source.id)
                              ? Icons.stop
                              : Icons.sync,
                        ),
                        label: UiText(
                          sources.busy.contains(source.id)
                              ? 'Cancel'
                              : 'Synchronize',
                        ),
                      ),
                      TextButton.icon(
                        onPressed:
                            sources.busy.contains(source.id) ||
                                !source.connected
                            ? null
                            : () => run(
                                context,
                                () =>
                                    sources.setVisible(source, !source.visible),
                              ),
                        icon: Icon(
                          source.visible
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        label: UiText(
                          source.visible ? 'Hide library' : 'Show library',
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.login),
                        label: const UiText('Reconnect'),
                        onPressed: sources.busy.contains(source.id)
                            ? null
                            : () => addAdditionalSource(
                                context,
                                sources,
                                source.type,
                                onChanged,
                                connection: source,
                              ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.link_off),
                        label: const UiText('Disconnect'),
                        onPressed:
                            sources.busy.contains(source.id) ||
                                !source.connected
                            ? null
                            : () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const UiText(
                                      'Disconnect this source?',
                                    ),
                                    content: const UiText(
                                      'Credentials will be removed and the catalog hidden. The connection definition is kept so Reconnect can restore the same track IDs and playlists. Original music files are preserved.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const UiText('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const UiText('Disconnect'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true && context.mounted) {
                                  await run(
                                    context,
                                    () => sources.disconnect(source),
                                  );
                                }
                              },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
