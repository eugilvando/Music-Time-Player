# Connect your music sources

[Back to README](../README.md)

Music Time 2.0.0 does not ship a shared Google or Microsoft application registration. **Each user must register an application and enter its Client ID** before connecting Google Drive or OneDrive. Local files, WebDAV, Jellyfin, Emby and Windows SMB do not require a Google/Microsoft registration.

A Client ID identifies an OAuth application; it is not your account password, an API access token or a one-time login code. Enter provider passwords only on the provider's website, and server credentials only in the app. Do not paste passwords, tokens or client secrets into issues.

## OneDrive personal

1. Open [Microsoft Entra app registrations](https://entra.microsoft.com/) with an account permitted to create a registration. The portal may require access to an Entra directory; having OneDrive alone does not guarantee that your account can create applications.
2. Create an application registration for **personal Microsoft accounts**. Music Time uses the `consumers` authority; work/school accounts are not an advertised target.
3. In Authentication, add the **Mobile and desktop applications** platform. Register exactly:

   ```text
   http://localhost:42813/oauth
   ```

4. Enable the appropriate public-client setting if required for your registration. The current interface uses Authorization Code + PKCE and a system browser; it does not use a client secret or device-code login.
5. Add Microsoft Graph **delegated** `Files.Read` permission. Music Time requests `https://graph.microsoft.com/Files.Read offline_access` to read files and renew the session. Do not substitute application-only permissions or an organizational tenant ID.
6. Copy the **Application (client) ID** from Overview. Do not copy the Object ID, Directory/tenant ID or another application's Client ID.
7. Open Music Time → **Settings → Music sources → OneDrive**. Enter/save the Client ID in the connection configuration and connect in your browser. The installed app accepts this configuration without recompilation.
8. Sign in with the personal account, consent, return to the app, choose a music folder and synchronize. Connection, folder selection and catalog synchronization are separate steps.
9. Use connection/folder/sample verification, then check playback, seeking and reopening with your account.

If port 42813 is occupied or a registration/redirect is incorrect, the callback can fail. `Files.Read` is read permission for the account's accessible files; choosing one folder constrains the app's scan rather than the provider permission itself. Revocation, account restrictions, consent settings and service quotas can still block access. There is no supported way to bypass them by borrowing someone else's Client ID.

Official references: [desktop registration](https://learn.microsoft.com/en-us/entra/identity-platform/scenario-desktop-app-registration), [redirect URI rules](https://learn.microsoft.com/en-us/entra/identity-platform/reply-url), [authorization code and PKCE](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow), [Graph drive access](https://learn.microsoft.com/en-us/graph/api/drive-get).

## Google Drive

1. Create/select a project in [Google Cloud Console](https://console.cloud.google.com/) and enable the **Google Drive API**.
2. Configure the OAuth consent screen/Google Auth Platform branding, audience and data access. For a personal testing project, add your own Google account as a test user.
3. Create OAuth credentials with application type **Desktop app**. A web, Android or service-account credential is not interchangeable with this connector.
4. Copy the Client ID ending in `.apps.googleusercontent.com`. Keep the desktop client secret available if Google requires it for your credential; do not publish the downloaded credential JSON.
5. Open **Settings → Music sources → Add source → Google Drive**. Enter a source name, **Desktop OAuth client ID**, optional required desktop secret, and optionally the music folder ID.
6. After connecting, use **Select music folder** to browse My Drive and choose a folder explicitly. The browser lists folders with pagination and includes subfolders when scanning. A folder ID can also be entered in advanced configuration.
7. Authorize in the system browser and return to the app. The app uses Authorization Code + PKCE and an ephemeral loopback callback shaped like `http://127.0.0.1:<port>/oauth`; do not configure it as a fixed web-server callback.
8. Synchronize and test a small authorized music folder, then playback/seeking and renewal.

Music Time requests:

```text
https://www.googleapis.com/auth/drive.readonly
```

This is a **restricted** scope permitting viewing/downloading accessible Drive files, not a per-file `drive.file` grant. Folder selection controls indexing, not the OAuth scope. Google can require verification for public distribution, restrict unverified clients and display warnings. Creating a private Client ID does not make an app Google-verified or exempt it from policy.

For an external app in **Testing** using this scope, refresh tokens can expire after **seven days**, so reconnection may be necessary. Test-user allowlists, account/Workspace administrator restrictions, revocation and quotas can also prevent access. Changing the publishing status is not a guarantee of approval or permanent tokens. Follow Google instructions; do not bypass browser or account safety checks.

Official references: [desktop OAuth setup and loopback](https://developers.google.com/identity/protocols/oauth2/native-app), [Drive scopes and restricted access](https://developers.google.com/workspace/drive/api/guides/api-specific-auth), [refresh-token expiry](https://developers.google.com/identity/protocols/oauth2), [restricted-scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification).

## WebDAV, Jellyfin, Emby and SMB

Use **Settings → Music sources → Add source**.

| Source | Configuration |
| --- | --- |
| WebDAV | Full HTTPS music-folder URL, including server base path, username and password. |
| Jellyfin / Emby | Server URL including any `/jellyfin/` or `/emby/` base path, username/password and optional library folder ID. Empty ID includes audio accessible to that user. Direct audio is required; no transcoding is negotiated. |
| SMB | Windows UNC path such as `\\server\share\Music`. First establish access through Windows/network credentials. The app does not store a separate SMB password. |

HTTP is disabled by default for server connectors. Enabling it explicitly sends credentials/audio without TLS; use HTTPS wherever possible. Server TLS, share permissions, reachability and authentication must already be configured. No port forwarding, server deployment or NAS account creation is performed by Music Time.

## Optional Last.fm and online metadata

Last.fm requires your [own API configuration](https://www.last.fm/api/account/create), and scrobbling requires browser authorization. Public profile reads need the API key and username; API secret/session are used for the authorization flow. The outbox does not promise exactly-once delivery after an unknown server response.

Artist portraits/biographies, similar artists and optional LRCLIB lyrics contact external providers. Their metadata availability and name matching are not guaranteed. See [privacy and data](privacy-and-data.md) for the information these features use.

## Folder selection and reconnecting

Google Drive now provides a paginated visual folder browser. Select the folder explicitly before scanning. OneDrive personal hexadecimal drive identifiers are normalized when reconnecting, preserving existing item identity. Disconnecting retains a source definition for reconnection; **Remove source** confirms deletion of its exclusive catalog records and managed downloads/cache, preserving original music and tracks shared with another source.
