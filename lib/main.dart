import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const AntiHackerApp());

const _green = Color(0xFF00F58A);
const _background = Color(0xFF080D12);
const _card = Color(0xFF111A22);
const _channel = MethodChannel('anti_hacker/apps');

class AntiHackerApp extends StatelessWidget {
  const AntiHackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Android Anti-Hacker',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _green,
          brightness: Brightness.dark,
          surface: _card,
        ),
        fontFamily: 'sans-serif',
        useMaterial3: true,
      ),
      home: const ScannerHome(),
    );
  }
}

class InstalledApp {
  final String name;
  final String packageName;
  final bool isSystem;
  final List<String> permissions;
  final List<String> riskyPermissions;
  final String risk;
  final String explanation;

  const InstalledApp({
    required this.name,
    required this.packageName,
    required this.isSystem,
    required this.permissions,
    required this.riskyPermissions,
    required this.risk,
    required this.explanation,
  });

  factory InstalledApp.fromMap(Map<dynamic, dynamic> map) {
    return InstalledApp(
      name: map['name']?.toString() ?? 'تطبيق بدون اسم',
      packageName: map['packageName']?.toString() ?? '',
      isSystem: map['isSystem'] == true,
      permissions: (map['permissions'] as List? ?? []).map((e) => e.toString()).toList(),
      riskyPermissions: (map['riskyPermissions'] as List? ?? []).map((e) => e.toString()).toList(),
      risk: map['risk']?.toString() ?? 'unknown',
      explanation: map['explanation']?.toString() ?? '',
    );
  }
}

class ScannerHome extends StatefulWidget {
  const ScannerHome({super.key});

  @override
  State<ScannerHome> createState() => _ScannerHomeState();
}

class _ScannerHomeState extends State<ScannerHome> {
  List<InstalledApp> _apps = [];
  bool _scanning = false;
  String? _error;
  int _filter = 0;

  int get _reviewCount => _apps.where((a) => a.risk == 'review').length;
  int get _highCount => _apps.where((a) => a.risk == 'high').length;

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getInstalledApps');
      final apps = (result ?? [])
          .map((item) => InstalledApp.fromMap(Map<dynamic, dynamic>.from(item as Map)))
          .toList()
        ..sort((a, b) {
          int rank(String risk) => risk == 'high' ? 0 : risk == 'review' ? 1 : 2;
          final byRisk = rank(a.risk).compareTo(rank(b.risk));
          return byRisk != 0 ? byRisk : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      if (!mounted) return;
      setState(() => _apps = apps);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message ?? 'تعذر فحص التطبيقات.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'حدث خطأ أثناء الفحص. تحقق من ملفات Android ثم أعد البناء.');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  List<InstalledApp> get _visibleApps {
    if (_filter == 1) return _apps.where((a) => a.risk == 'high').toList();
    if (_filter == 2) return _apps.where((a) => a.risk == 'review').toList();
    return _apps;
  }

  Future<void> _uninstall(InstalledApp app) async {
    try {
      await _channel.invokeMethod('uninstallApp', {'packageName': app.packageName});
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'تعذر فتح شاشة إزالة التطبيق')),
      );
    }
  }

  void _showDetails(InstalledApp app) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(app.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                const SizedBox(height: 7),
                SelectableText(app.packageName, style: const TextStyle(color: Colors.white54)),
                const SizedBox(height: 14),
                _RiskBadge(risk: app.risk),
                const SizedBox(height: 12),
                Text(app.explanation),
                const SizedBox(height: 14),
                Text('الصلاحيات الحساسة (${app.riskyPermissions.length})',
                    style: const TextStyle(color: _green, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (app.riskyPermissions.isEmpty)
                  const Text('لم تُكتشف صلاحيات حساسة من القائمة التي يفحصها التطبيق.')
                else
                  ...app.riskyPermissions.map((p) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text('• ${_permissionLabel(p)}', textDirection: TextDirection.ltr),
                      )),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: app.isSystem ? null : () {
                    Navigator.pop(context);
                    _uninstall(app);
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: Text(app.isSystem ? 'تطبيق نظام — لا يمكن إزالته من هنا' : 'فتح شاشة إزالة التطبيق'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'ملاحظة: هذه نتيجة فحص أولي للصلاحيات وليست إثباتاً على وجود اختراق. راجع التطبيق قبل إزالته.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _permissionLabel(String permission) {
    final name = permission.split('.').last;
    const labels = {
      'CAMERA': 'الكاميرا',
      'RECORD_AUDIO': 'الميكروفون / تسجيل الصوت',
      'ACCESS_FINE_LOCATION': 'الموقع الدقيق',
      'ACCESS_COARSE_LOCATION': 'الموقع التقريبي',
      'READ_CONTACTS': 'قراءة جهات الاتصال',
      'READ_SMS': 'قراءة الرسائل النصية',
      'SEND_SMS': 'إرسال الرسائل النصية',
      'READ_CALL_LOG': 'قراءة سجل المكالمات',
      'WRITE_CALL_LOG': 'تعديل سجل المكالمات',
      'READ_PHONE_STATE': 'معلومات حالة الهاتف',
      'READ_EXTERNAL_STORAGE': 'قراءة مساحة التخزين',
      'MANAGE_EXTERNAL_STORAGE': 'إدارة جميع الملفات',
      'REQUEST_INSTALL_PACKAGES': 'طلب تثبيت تطبيقات أخرى',
      'SYSTEM_ALERT_WINDOW': 'الظهور فوق التطبيقات الأخرى',
      'BIND_ACCESSIBILITY_SERVICE': 'خدمة إمكانية الوصول',
    };
    return labels[name] ?? name;
  }

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _visibleApps;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _background,
        title: const Row(
          children: [
            Icon(Icons.shield_moon_outlined, color: _green),
            SizedBox(width: 10),
            Text('ANTI-HACKER', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'إعادة الفحص',
            onPressed: _scanning ? null : _scan,
            icon: const Icon(Icons.refresh, color: _green),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _green,
        onRefresh: _scan,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  colors: [Color(0xFF12372C), Color(0xFF10202A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: _green.withOpacity(.28)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.security, size: 48, color: _green),
                  const SizedBox(height: 10),
                  const Text('فحص أمان التطبيقات', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(
                    _scanning ? 'جارٍ تحليل التطبيقات المثبتة...' : 'افحص التطبيقات والصلاحيات الحساسة على جهازك',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _scanning ? null : _scan,
                      icon: _scanning
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.radar),
                      label: Text(_scanning ? 'جارٍ الفحص' : 'ابدأ الفحص الآن', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _StatCard(title: 'تم فحصها', value: '${_apps.length}', icon: Icons.apps, color: Colors.cyanAccent)),
                const SizedBox(width: 10),
                Expanded(child: _StatCard(title: 'تحتاج مراجعة', value: '$_reviewCount', icon: Icons.warning_amber, color: Colors.orangeAccent)),
                const SizedBox(width: 10),
                Expanded(child: _StatCard(title: 'عالية الخطورة', value: '$_highCount', icon: Icons.gpp_bad, color: Colors.redAccent)),
              ],
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red.withOpacity(.12), borderRadius: BorderRadius.circular(12)),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ),
            Row(
              children: [
                const Expanded(child: Text('التطبيقات المثبتة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                Text('${shown.length} تطبيق', style: const TextStyle(color: Colors.white54)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                _FilterChip(label: 'الكل', selected: _filter == 0, onTap: () => setState(() => _filter = 0)),
                _FilterChip(label: 'عالية الخطورة', selected: _filter == 1, onTap: () => setState(() => _filter = 1)),
                _FilterChip(label: 'تحتاج مراجعة', selected: _filter == 2, onTap: () => setState(() => _filter = 2)),
              ],
            ),
            const SizedBox(height: 10),
            if (_scanning && _apps.isEmpty)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator(color: _green)),
              )
            else if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(_apps.isEmpty ? 'لم تظهر التطبيقات بعد. اضغط «ابدأ الفحص».' : 'لا توجد تطبيقات ضمن هذا التصنيف.',
                      style: const TextStyle(color: Colors.white60)),
                ),
              )
            else
              ...shown.map((app) => _AppTile(app: app, onTap: () => _showDetails(app))),
            const SizedBox(height: 18),
            const Text(
              'تنبيه: لا يستطيع تطبيق عادي ضمان كشف كل البرمجيات الخبيثة أو حذفها من جذورها. الفحص هنا يعتمد على بيانات التطبيقات والصلاحيات التي يتيحها أندرويد.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 7),
            Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.white60)),
          ],
        ),
      );
}

class _RiskBadge extends StatelessWidget {
  final String risk;
  const _RiskBadge({required this.risk});

  @override
  Widget build(BuildContext context) {
    final high = risk == 'high';
    final review = risk == 'review';
    final color = high ? Colors.redAccent : review ? Colors.orangeAccent : _green;
    final label = high ? 'مؤشر خطورة مرتفع' : review ? 'يحتاج مراجعة' : 'لم تظهر مؤشرات من الفحص الأولي';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(30)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
    );
  }
}

class _AppTile extends StatelessWidget {
  final InstalledApp app;
  final VoidCallback onTap;
  const _AppTile({required this.app, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = app.risk == 'high' ? Colors.redAccent : app.risk == 'review' ? Colors.orangeAccent : _green;
    return Card(
      color: _card,
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(.13),
          child: Icon(app.risk == 'high' ? Icons.gpp_bad : app.risk == 'review' ? Icons.warning_amber : Icons.android,
              color: color),
        ),
        title: Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${app.isSystem ? 'تطبيق نظام' : 'تطبيق مستخدم'} • ${app.riskyPermissions.length} صلاحية حساسة',
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        trailing: Icon(Icons.chevron_right, color: color),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => ActionChip(
        label: Text(label),
        onPressed: onTap,
        backgroundColor: selected ? _green.withOpacity(.18) : _card,
        side: BorderSide(color: selected ? _green : Colors.white12),
        labelStyle: TextStyle(color: selected ? _green : Colors.white70),
      );
}