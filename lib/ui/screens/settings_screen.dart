import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/device_config.dart';
import '../../core/formatting.dart';
import '../controller.dart';
import '../layout.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';

const String appVersion = '2.2.1';

class SettingsScreen extends StatelessWidget {
  final AppController c;
  const SettingsScreen({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(isCompactWidth(context) ? 14 : 24, 8, isCompactWidth(context) ? 14 : 24, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Réglages', style: text.headlineSmall),
              const SizedBox(height: 4),
              Text('Version $appVersion', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              _PomodoroSection(c: c),
              _FlowSection(c: c),
              _AppearanceSection(c: c),
              if (isMobilePlatform) _MobileDataSection(c: c) else _DataSection(c: c),
              _WebdavSection(c: c),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  const _Section({required this.title, this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: text.titleMedium),
              if (subtitle != null)
                Text(subtitle!, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
          ),
          Card(
            color: scheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
            ),
          ),
        ],
      ),
    );
  }
}

/// Champ numérique : applique la valeur dès qu'elle est valide, corrige les bornes en quittant le champ.
class _NumField extends StatefulWidget {
  final String label;
  final String suffix;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  const _NumField({
    required this.label,
    required this.suffix,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final TextEditingController _c = TextEditingController(text: '${widget.value}');
  late final FocusNode _focus = FocusNode()..addListener(_onFocus);

  void _onFocus() {
    if (!_focus.hasFocus) {
      final v = (int.tryParse(_c.text) ?? widget.value).clamp(widget.min, widget.max);
      _c.text = '$v';
      widget.onChanged(v);
    }
  }

  @override
  void didUpdateWidget(_NumField old) {
    super.didUpdateWidget(old);
    // Valeur modifiée de l'extérieur (ex. synchro) pendant qu'on ne tape pas.
    if (!_focus.hasFocus && widget.value != int.tryParse(_c.text)) _c.text = '${widget.value}';
  }

  @override
  void dispose() {
    _focus.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Text(widget.label)),
        SizedBox(
          width: 104,
          child: TextField(
            controller: _c,
            focusNode: _focus,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.end,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            decoration: InputDecoration(isDense: true, suffixText: widget.suffix),
            onChanged: (t) {
              final v = int.tryParse(t);
              if (v != null && v >= widget.min && v <= widget.max) widget.onChanged(v);
            },
          ),
        ),
      ]),
    );
  }
}

class _PomodoroSection extends StatelessWidget {
  final AppController c;
  const _PomodoroSection({required this.c});

  @override
  Widget build(BuildContext context) {
    final s = c.store.data.settings;
    return _Section(
      title: 'Pomodoro',
      subtitle: 'Chaque phase démarre manuellement ; le travail continue en dépassement après la durée prévue.',
      children: [
        _NumField(label: 'Bloc de travail', suffix: 'min', value: s.workMin, min: 1, max: 240, onChanged: (v) => c.store.updateSettings((x) => x.workMin = v)),
        _NumField(label: 'Pause courte', suffix: 'min', value: s.shortBreakMin, min: 1, max: 120, onChanged: (v) => c.store.updateSettings((x) => x.shortBreakMin = v)),
        _NumField(label: 'Pause longue', suffix: 'min', value: s.longBreakMin, min: 1, max: 240, onChanged: (v) => c.store.updateSettings((x) => x.longBreakMin = v)),
        _NumField(label: 'Blocs avant la pause longue', suffix: '', value: s.blocksBeforeLongBreak, min: 1, max: 20, onChanged: (v) => c.store.updateSettings((x) => x.blocksBeforeLongBreak = v)),
      ],
    );
  }
}

class _FlowSection extends StatelessWidget {
  final AppController c;
  const _FlowSection({required this.c});

  @override
  Widget build(BuildContext context) {
    final s = c.store.data.settings;
    return _Section(
      title: 'Flow Zone',
      subtitle: 'À l\'arrêt, la pause méritée est un pourcentage du temps travaillé.',
      children: [
        _NumField(label: 'Pause méritée (en % du temps travaillé)', suffix: '%', value: s.flowBreakPercent, min: 1, max: 100, onChanged: (v) => c.store.updateSettings((x) => x.flowBreakPercent = v)),
      ],
    );
  }
}

class _AppearanceSection extends StatelessWidget {
  final AppController c;
  const _AppearanceSection({required this.c});

  @override
  Widget build(BuildContext context) {
    final s = c.store.data.settings;
    final scheme = Theme.of(context).colorScheme;
    return _Section(
      title: 'Apparence',
      subtitle: 'Material You. Ces réglages sont synchronisés entre tes machines.',
      children: [
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'dark', label: Text('Sombre'), icon: Icon(Icons.dark_mode_outlined)),
            ButtonSegment(value: 'light', label: Text('Clair'), icon: Icon(Icons.light_mode_outlined)),
            ButtonSegment(value: 'system', label: Text('Système'), icon: Icon(Icons.brightness_auto_outlined)),
          ],
          selected: {s.themeMode},
          onSelectionChanged: (v) => c.store.updateSettings((x) => x.themeMode = v.first),
        ),
        const SizedBox(height: 16),
        Text('Palette', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in appPalettes)
            ChoiceChip(
              selected: s.palette == p.id,
              avatar: CircleAvatar(backgroundColor: p.monochrome ? scheme.onSurface : p.seed, radius: 8),
              label: Text(p.label),
              onSelected: (_) => c.store.updateSettings((x) => x.palette = p.id),
            ),
        ]),
      ],
    );
  }
}

/// Sur mobile les données restent dans le dossier privé de l'appli ; on les partage via WebDAV.
class _MobileDataSection extends StatelessWidget {
  final AppController c;
  const _MobileDataSection({required this.c});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return _Section(
      title: 'Données',
      subtitle: "Stockées dans l'espace privé de l'appli (invisible pour les autres applications).",
      children: [
        Text(
          'Pour retrouver tes données sur un autre appareil (ordinateur, autre téléphone), '
          'configure la synchronisation WebDAV ci-dessous avec le même serveur et le même fichier.',
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Text(
          "Désinstaller l'appli efface les données locales : garde la synchronisation activée.",
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _DataSection extends StatelessWidget {
  final AppController c;
  const _DataSection({required this.c});

  Future<void> _choose(BuildContext context) async {
    if (c.busy) {
      c.showMessage("Termine d'abord la session en cours.");
      return;
    }
    final dir = await getDirectoryPath(confirmButtonText: 'Utiliser ce dossier');
    if (dir == null) return;
    if (!context.mounted) return;
    final ok = await confirmDialog(
      context,
      title: 'Changer le dossier de données ?',
      message: 'Tes données seront copiées dans :\n$dir\n\nLes fichiers actuels ne sont pas supprimés. '
          "Si ce dossier contient déjà un data.json, c'est celui-là qui sera utilisé.",
      confirmLabel: 'Changer',
    );
    if (ok) c.chooseDataDir(dir);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final custom = c.paths.isCustom(c.store.dataDir);
    final mode = c.paths.isPortable
        ? 'Mode portable : tout reste à côté de l\'exécutable.'
        : (custom ? 'Dossier personnalisé.' : 'Dossier par défaut.');
    return _Section(
      title: 'Emplacement des données',
      subtitle: mode,
      children: [
        Text('Fichier de données', style: text.labelLarge),
        const SizedBox(height: 4),
        SelectableText(c.store.filePath, style: text.bodyMedium?.copyWith(fontFamily: 'monospace')),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(
            onPressed: () => _choose(context),
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: const Text('Choisir un dossier…'),
          ),
          if (custom)
            OutlinedButton.icon(
              onPressed: c.busy ? null : c.resetDataDir,
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('Revenir au dossier par défaut'),
            ),
        ]),
        const SizedBox(height: 8),
        Text(
          'Astuce : choisis un dossier synchronisé (Nextcloud, Syncthing…) pour partager tes données, ou utilise la synchronisation WebDAV ci-dessous.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _WebdavSection extends StatefulWidget {
  final AppController c;
  const _WebdavSection({required this.c});

  @override
  State<_WebdavSection> createState() => _WebdavSectionState();
}

class _WebdavSectionState extends State<_WebdavSection> {
  late final TextEditingController _url;
  late final TextEditingController _user;
  late final TextEditingController _pass;
  late final TextEditingController _path;
  late int _minutes;
  late bool _enabled;
  bool _showPass = false;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  AppController get c => widget.c;

  @override
  void initState() {
    super.initState();
    final w = c.device.webdav;
    _url = TextEditingController(text: w.url);
    _user = TextEditingController(text: w.username);
    _pass = TextEditingController(text: w.password);
    _path = TextEditingController(text: w.remotePath);
    _minutes = w.autoSyncMinutes;
    _enabled = w.enabled;
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    _path.dispose();
    super.dispose();
  }

  WebdavConfig _current() {
    var p = _path.text.trim();
    if (p.isEmpty) p = '/EtudeTimer/data.json';
    if (!p.startsWith('/')) p = '/$p';
    return WebdavConfig(
      enabled: _enabled,
      url: _url.text.trim(),
      username: _user.text.trim(),
      password: _pass.text,
      remotePath: p,
      autoSyncMinutes: _minutes,
    );
  }

  void _save() {
    c.updateWebdav(_current());
    c.showMessage('Réglages WebDAV enregistrés.');
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final err = await c.testWebdav(_current());
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = err == null;
      _testResult = err ?? 'Connexion réussie.';
    });
  }

  Future<void> _syncNow() async {
    c.updateWebdav(_current());
    await c.syncNow();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final last = c.device.lastSyncedAt;
    return _Section(
      title: 'Synchronisation WebDAV',
      subtitle: 'Nextcloud ou tout serveur WebDAV. Un seul fichier JSON est échangé ; la fusion est automatique.',
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Activer la synchronisation'),
          value: _enabled,
          onChanged: (v) {
            setState(() => _enabled = v);
            c.updateWebdav(_current());
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _url,
          decoration: const InputDecoration(
            labelText: 'URL WebDAV',
            hintText: 'https://cloud.exemple.com/remote.php/dav/files/mon-nom',
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _user, decoration: const InputDecoration(labelText: 'Identifiant'))),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _pass,
              obscureText: !_showPass,
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                suffixIcon: IconButton(
                  tooltip: _showPass ? 'Masquer' : 'Afficher',
                  icon: Icon(_showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _showPass = !_showPass),
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _path, decoration: const InputDecoration(labelText: 'Chemin du fichier distant')),
        const SizedBox(height: 12),
        _NumField(
          label: 'Synchroniser automatiquement toutes les (0 = jamais)',
          suffix: 'min',
          value: _minutes,
          min: 0,
          max: 1440,
          onChanged: (v) => _minutes = v,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Le mot de passe est enregistré en clair dans un fichier réservé à cet ordinateur (jamais envoyé sur le serveur). "
                "Utilise de préférence un « mot de passe d'application » Nextcloud (Paramètres › Sécurité), révocable à tout moment.",
                style: text.bodySmall,
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton(onPressed: _save, child: const Text('Enregistrer')),
          OutlinedButton.icon(
            onPressed: _testing ? null : _test,
            icon: _testing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_tethering, size: 18),
            label: const Text('Tester la connexion'),
          ),
          FilledButton.tonalIcon(
            onPressed: c.syncing ? null : _syncNow,
            icon: c.syncing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync, size: 18),
            label: const Text('Synchroniser maintenant'),
          ),
        ]),
        if (_testResult != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            Icon(_testOk ? Icons.check_circle_outline : Icons.error_outline, size: 18, color: _testOk ? scheme.primary : scheme.error),
            const SizedBox(width: 8),
            Expanded(child: Text(_testResult!, style: TextStyle(color: _testOk ? null : scheme.error))),
          ]),
        ],
        const SizedBox(height: 12),
        Text(
          [
            if (last != null) 'Dernière synchronisation : ${relativeDate(last)} à ${timeOfDay(last)}' else 'Jamais synchronisé sur cet ordinateur.',
            if (c.syncMessage != null) c.syncMessage!,
          ].join(' — '),
          style: text.bodySmall?.copyWith(color: c.syncFailed ? scheme.error : scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
