import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AccountingDb.instance.init();
  runApp(const SchoolAccountingApp());
}

class SchoolAccountingApp extends StatelessWidget {
  const SchoolAccountingApp({super.key});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF173B72);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'المحاسب المدرسي PRO',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: navy),
        scaffoldBackgroundColor: const Color(0xFFF4F7FC),
        appBarTheme: const AppBarTheme(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          centerTitle: false,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF7F9FD),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8F2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: navy, width: 1.5),
          ),
        ),
      ),
      home: const AccountingHome(),
    );
  }
}

class AccountingDb {
  AccountingDb._();

  static final AccountingDb instance = AccountingDb._();

  Database? _db;
  String? _dbPath;

  Database get database {
    final value = _db;
    if (value == null) {
      throw StateError('قاعدة البيانات لم تجهز بعد');
    }
    return value;
  }

  Future<void> init() async {
    if (_db != null && _db!.isOpen) return;

    final docs = await getApplicationDocumentsDirectory();
    await docs.create(recursive: true);
    _dbPath = p.join(docs.path, 'school_accounting.db');

    _db = await openDatabase(
      _dbPath!,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA busy_timeout = 5000');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE school_years (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            is_active INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE cash_transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            year_id INTEGER NOT NULL,
            type TEXT NOT NULL CHECK(type IN ('receipt','expense')),
            amount REAL NOT NULL CHECK(amount > 0),
            category TEXT NOT NULL,
            party TEXT NOT NULL DEFAULT '',
            note TEXT NOT NULL DEFAULT '',
            date TEXT NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY(year_id) REFERENCES school_years(id)
          )
        ''');

        await db.execute('''
          CREATE TABLE app_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');

        final now = DateTime.now().toIso8601String();

        await db.insert('school_years', {
          'name': '2026 / 2027',
          'is_active': 1,
          'created_at': now,
        });

        await db.insert('app_settings', {
          'key': 'school_name',
          'value': 'اسم المدرسة',
        });

        await db.insert('app_settings', {
          'key': 'currency',
          'value': 'ر.س',
        });
      },
    );

    await _ensureSeedData();
  }

  Future<void> _ensureSeedData() async {
    final years = await database.query('school_years', limit: 1);

    if (years.isEmpty) {
      await database.insert('school_years', {
        'name': '2026 / 2027',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });
    }

    final active = await database.query(
      'school_years',
      where: 'is_active = 1',
      limit: 1,
    );

    if (active.isEmpty) {
      final first = await database.query(
        'school_years',
        orderBy: 'id ASC',
        limit: 1,
      );

      if (first.isNotEmpty) {
        await database.update(
          'school_years',
          {'is_active': 1},
          where: 'id = ?',
          whereArgs: [first.first['id']],
        );
      }
    }
  }

  Future<int> get activeYearId async {
    final rows = await database.query(
      'school_years',
      where: 'is_active = 1',
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('لا يوجد عام دراسي نشط');
    }

    return rows.first['id'] as int;
  }

  Future<Map<String, Object?>> get activeYear async {
    final rows = await database.query(
      'school_years',
      where: 'is_active = 1',
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('لا يوجد عام دراسي نشط');
    }

    return rows.first;
  }

  Future<List<Map<String, Object?>>> years() {
    return database.query('school_years', orderBy: 'id DESC');
  }

  Future<void> addYear(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) {
      throw Exception('اكتب اسم العام الدراسي');
    }

    await database.transaction((txn) async {
      final count = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM school_years'),
          ) ??
          0;

      await txn.insert('school_years', {
        'name': clean,
        'is_active': count == 0 ? 1 : 0,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> activateYear(int id) async {
    await database.transaction((txn) async {
      await txn.update('school_years', {'is_active': 0});
      await txn.update(
        'school_years',
        {'is_active': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> addTransaction({
    required String type,
    required double amount,
    required String category,
    required String party,
    required String note,
    required DateTime date,
  }) async {
    if (amount <= 0) {
      throw Exception('يجب أن يكون المبلغ أكبر من صفر');
    }

    await database.insert('cash_transactions', {
      'year_id': await activeYearId,
      'type': type,
      'amount': amount,
      'category': category.trim().isEmpty
          ? (type == 'receipt' ? 'إيرادات أخرى' : 'مصروفات أخرى')
          : category.trim(),
      'party': party.trim(),
      'note': note.trim(),
      'date': DateFormat('yyyy-MM-dd').format(date),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, Object?>>> transactions({
    int limit = 200,
  }) async {
    final yearId = await activeYearId;

    return database.query(
      'cash_transactions',
      where: 'year_id = ?',
      whereArgs: [yearId],
      orderBy: 'date DESC, id DESC',
      limit: limit,
    );
  }

  Future<Map<String, double>> summary() async {
    final yearId = await activeYearId;

    final rows = await database.rawQuery('''
      SELECT type, COALESCE(SUM(amount), 0) AS total
      FROM cash_transactions
      WHERE year_id = ?
      GROUP BY type
    ''', [yearId]);

    double receipts = 0;
    double expenses = 0;

    for (final row in rows) {
      final amount = (row['total'] as num?)?.toDouble() ?? 0;

      if (row['type'] == 'receipt') receipts = amount;
      if (row['type'] == 'expense') expenses = amount;
    }

    return {
      'receipts': receipts,
      'expenses': expenses,
      'balance': receipts - expenses,
    };
  }

  Future<String> setting(
    String key, {
    String fallback = '',
  }) async {
    final rows = await database.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );

    return rows.isEmpty ? fallback : rows.first['value'] as String;
  }

  Future<void> saveSetting(String key, String value) async {
    await database.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // إنشاء نسخة احتياطية والتحقق من سلامتها.
  Future<File> createBackup() async {
    final path = _dbPath;
    final db = _db;

    if (path == null || db == null || !db.isOpen) {
      throw StateError('قاعدة البيانات غير جاهزة');
    }

    await db.rawQuery('PRAGMA wal_checkpoint(FULL)');

    final source = File(path);
    if (!await source.exists()) {
      throw Exception('ملف قاعدة البيانات غير موجود');
    }

    final docs = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(docs.path, 'backups'));
    await folder.create(recursive: true);

    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final target = File(
      p.join(folder.path, 'school_backup_$stamp.db'),
    );

    await source.copy(target.path);

    try {
      final checkDb = await openDatabase(
        target.path,
        readOnly: true,
      );

      try {
        final integrity =
            await checkDb.rawQuery('PRAGMA integrity_check');

        final okay = integrity.isNotEmpty &&
            integrity.first.values.first.toString().toLowerCase() ==
                'ok';

        if (!okay) {
          throw Exception('فشل التحقق من سلامة النسخة الاحتياطية');
        }

        final tables = await checkDb.rawQuery('''
          SELECT name FROM sqlite_master
          WHERE type = 'table'
          AND name IN (
            'school_years',
            'cash_transactions',
            'app_settings'
          )
        ''');

        if (tables.length != 3) {
          throw Exception('النسخة لا تحتوي على جداول النظام الأساسية');
        }
      } finally {
        await checkDb.close();
      }
    } catch (_) {
      if (await target.exists()) await target.delete();
      rethrow;
    }

    await saveSetting(
      'last_backup',
      DateTime.now().toIso8601String(),
    );

    return target;
  }

  // مشاركة ملف النسخة مع تطبيقات الجهاز.
  Future<void> exportBackup() async {
    final file = await createBackup();

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'نسخة احتياطية من المحاسب المدرسي PRO',
    );
  }

  // التحقق من النسخة قبل استبدال قاعدة البيانات الحالية.
  Future<void> restoreBackup() async {
    final selected = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db', 'sqlite'],
    );

    if (selected == null || selected.files.single.path == null) {
      return;
    }

    final input = File(selected.files.single.path!);
    final path = _dbPath;

    if (path == null || !await input.exists()) {
      throw Exception('ملف النسخة غير موجود');
    }

    if (p.equals(
      p.normalize(input.absolute.path),
      p.normalize(File(path).absolute.path),
    )) {
      throw Exception(
        'اختر ملف نسخة احتياطية مستقلًا، وليس قاعدة البيانات المفتوحة',
      );
    }

    final docs = await getApplicationDocumentsDirectory();
    final staging = File(
      p.join(docs.path, 'restore_validation.db'),
    );
    final emergency = File(
      p.join(docs.path, 'emergency_before_restore.db'),
    );

    try {
      if (await staging.exists()) await staging.delete();
      await input.copy(staging.path);

      final testDb = await openDatabase(
        staging.path,
        readOnly: true,
      );

      try {
        final integrity =
            await testDb.rawQuery('PRAGMA integrity_check');

        final okay = integrity.isNotEmpty &&
            integrity.first.values.first.toString().toLowerCase() ==
                'ok';

        if (!okay) {
          throw Exception('النسخة تالفة؛ لم تتغير البيانات الحالية');
        }

        final tables = await testDb.rawQuery('''
          SELECT name FROM sqlite_master
          WHERE type = 'table'
          AND name IN (
            'school_years',
            'cash_transactions',
            'app_settings'
          )
        ''');

        if (tables.length != 3) {
          throw Exception('الملف ليس نسخة متوافقة مع هذا التطبيق');
        }
      } finally {
        await testDb.close();
      }

      // إنشاء نسخة احتياطية قبل الاستعادة.
      await createBackup();

      final liveDb = _db;
      if (liveDb != null && liveDb.isOpen) {
        await liveDb.close();
      }
      _db = null;

      final wal = File('$path-wal');
      final shm = File('$path-shm');

      if (await wal.exists()) await wal.delete();
      if (await shm.exists()) await shm.delete();
      if (await emergency.exists()) await emergency.delete();

      await File(path).copy(emergency.path);

      try {
        await staging.copy(path);
        await init();
      } catch (_) {
        if (_db != null && _db!.isOpen) {
          await _db!.close();
        }
        _db = null;

        if (await wal.exists()) await wal.delete();
        if (await shm.exists()) await shm.delete();

        if (await emergency.exists()) {
          await emergency.copy(path);
        }

        await init();
        rethrow;
      }
    } finally {
      if (await staging.exists()) await staging.delete();
      if (await emergency.exists()) await emergency.delete();
    }
  }
}

class AccountingHome extends StatefulWidget {
  const AccountingHome({super.key});

  @override
  State<AccountingHome> createState() => _AccountingHomeState();
}

class _AccountingHomeState extends State<AccountingHome>
    with WidgetsBindingObserver {
  int _tab = 0;
  bool _loading = true;
  bool _backupRunning = false;

  Map<String, double> _summary = {
    'receipts': 0,
    'expenses': 0,
    'balance': 0,
  };

  List<Map<String, Object?>> _transactions = [];
  Map<String, Object?> _year = {'name': '2026 / 2027'};
  String _schoolName = 'اسم المدرسة';
  String _currency = 'ر.س';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runDailyBackupIfNeeded();
    }
  }

  Future<void> _runDailyBackupIfNeeded() async {
    if (_backupRunning) return;

    _backupRunning = true;

    try {
      final db = AccountingDb.instance;
      final last = await db.setting('last_backup');
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      if (last.startsWith(today)) return;

      await db.createBackup();

      if (mounted) {
        _message('تم إنشاء النسخة الاحتياطية اليومية');
      }
    } catch (_) {
      // يمكن إنشاء النسخة يدويًا من الإعدادات عند تعذر النسخ التلقائي.
    } finally {
      _backupRunning = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final db = AccountingDb.instance;
      final summary = await db.summary();
      final transactions = await db.transactions();
      final year = await db.activeYear;
      final schoolName =
          await db.setting('school_name', fallback: 'اسم المدرسة');
      final currency = await db.setting('currency', fallback: 'ر.س');

      if (!mounted) return;

      setState(() {
        _summary = summary;
        _transactions = transactions;
        _year = year;
        _schoolName = schoolName;
        _currency = currency;
        _loading = false;
      });

      _runDailyBackupIfNeeded();
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);
      _message('تعذر تحميل البيانات: $e');
    }
  }

  void _message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  String _money(num value) {
    return '${NumberFormat('#,##0.##', 'en').format(value)} $_currency';
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _dashboard(),
      _transactionsPage(),
      _yearsPage(),
      _settingsPage(),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'المحاسب المدرسي PRO',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              Text(
                _schoolName,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: _refresh,
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : IndexedStack(index: _tab, children: pages),
        floatingActionButton: _tab <= 1
            ? FloatingActionButton.extended(
                onPressed: _addTransaction,
                icon: const Icon(Icons.add),
                label: const Text('سند جديد'),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (index) {
            setState(() => _tab = index);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'الرئيسية',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'الحركات',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: 'الأعوام',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'الإعدادات',
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashboard() {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF173B72), Color(0xFF3766AD)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'العام الدراسي النشط',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_year['name'] ?? ''}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'الرصيد الحالي',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Text(
                  _money(_summary['balance'] ?? 0),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _statCard(
                  'إجمالي القبض',
                  _summary['receipts'] ?? 0,
                  Icons.south_west,
                  const Color(0xFF16835D),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statCard(
                  'إجمالي الصرف',
                  _summary['expenses'] ?? 0,
                  Icons.north_east,
                  const Color(0xFFD34D56),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'آخر الحركات',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _tab = 1),
                child: const Text('عرض الكل'),
              ),
            ],
          ),
          if (_transactions.isEmpty)
            const _EmptyState(
              icon: Icons.receipt_long,
              title: 'لا توجد حركات بعد',
              subtitle: 'أضف أول سند قبض أو صرف للبدء',
            )
          else
            ..._transactions.take(5).map(_transactionTile),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _statCard(
    String title,
    double amount,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: .12),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                _money(amount),
                style: TextStyle(
                  fontSize: 17,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _transactionsPage() {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'سجل الحركات المالية',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_transactions.isEmpty)
            const _EmptyState(
              icon: Icons.inbox_outlined,
              title: 'السجل فارغ',
              subtitle: 'ستظهر سندات القبض والصرف هنا',
            )
          else
            ..._transactions.map(_transactionTile),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _transactionTile(Map<String, Object?> item) {
    final receipt = item['type'] == 'receipt';
    final color = receipt
        ? const Color(0xFF16835D)
        : const Color(0xFFD34D56);

    final amount = (item['amount'] as num?)?.toDouble() ?? 0;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .12),
          child: Icon(
            receipt ? Icons.call_received : Icons.call_made,
            color: color,
          ),
        ),
        title: Text(
          (item['category'] ?? '').toString(),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${item['party'] ?? '—'}  •  ${item['date'] ?? ''}\n'
          '${item['note'] ?? ''}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: Text(
          '${receipt ? '+' : '−'}${_money(amount)}',
          textAlign: TextAlign.end,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _yearsPage() {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: AccountingDb.instance.years(),
      builder: (context, snapshot) {
        final years = snapshot.data ?? [];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'إدارة الأعوام الدراسية',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'كل عام دراسي له حركات مالية مستقلة عن الأعوام الأخرى.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _addYear,
              icon: const Icon(Icons.add),
              label: const Text('إضافة عام دراسي'),
            ),
            const SizedBox(height: 12),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Center(child: CircularProgressIndicator()),
            ...years.map((year) {
              final active = (year['is_active'] as int? ?? 0) == 1;

              return Card(
                child: ListTile(
                  leading: Icon(
                    Icons.calendar_month,
                    color: active
                        ? const Color(0xFF16835D)
                        : Colors.blueGrey,
                  ),
                  title: Text(
                    year['name'].toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    active ? 'العام النشط حاليًا' : 'عام غير نشط',
                  ),
                  trailing: active
                      ? const Chip(label: Text('نشط'))
                      : TextButton(
                          onPressed: () async {
                            await AccountingDb.instance.activateYear(
                              year['id'] as int,
                            );
                            await _refresh();
                            if (mounted) setState(() {});
                          },
                          child: const Text('تفعيل'),
                        ),
                ),
              );
            }),
            const SizedBox(height: 80),
          ],
        );
      },
    );
  }

  Widget _settingsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'الإعدادات والنسخ الاحتياطي',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.school_outlined),
            title: const Text('بيانات المدرسة'),
            subtitle: Text(_schoolName),
            trailing: const Icon(Icons.chevron_left),
            onTap: _editSchoolSettings,
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.backup_outlined,
              color: Color(0xFF173B72),
            ),
            title: const Text('إنشاء نسخة احتياطية الآن'),
            subtitle: const Text('حفظ نسخة محلية والتحقق من سلامتها'),
            onTap: _createBackup,
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.share_outlined,
              color: Color(0xFF173B72),
            ),
            title: const Text('تصدير ومشاركة نسخة'),
            subtitle: const Text('مشاركة الملف أو حفظه في مكان آمن'),
            onTap: _shareBackup,
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.restore_outlined,
              color: Color(0xFFD34D56),
            ),
            title: const Text('استعادة نسخة احتياطية'),
            subtitle: const Text('استبدال البيانات بالنسخة التي تختارها'),
            onTap: _restoreBackup,
          ),
        ),
        Card(
          child: const ListTile(
            leading: Icon(Icons.offline_bolt_outlined),
            title: Text('يعمل دون إنترنت'),
            subtitle: Text('تُحفظ البيانات محليًا على هذا الجهاز'),
          ),
        ),
        Card(
          child: const ListTile(
            leading: Icon(Icons.person_outline),
            title: Text('تطوير التطبيق'),
            subtitle: Text('أ. محمد علي حيدره • 785068859'),
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Future<void> _createBackup() async {
    try {
      final file = await AccountingDb.instance.createBackup();

      if (!mounted) return;

      _message('تم إنشاء النسخة بنجاح: ${p.basename(file.path)}');
    } catch (e) {
      if (mounted) _message('تعذر إنشاء النسخة: $e');
    }
  }

  Future<void> _shareBackup() async {
    try {
      await AccountingDb.instance.exportBackup();
    } catch (e) {
      if (mounted) _message('تعذر تصدير النسخة: $e');
    }
  }

  Future<void> _restoreBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد استعادة البيانات'),
        content: const Text(
          'ستُستبدل البيانات الحالية بمحتويات النسخة المختارة. '
          'سيتم إنشاء نسخة احتياطية قبل الاستعادة. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await AccountingDb.instance.restoreBackup();
      await _refresh();

      if (mounted) _message('اكتملت عملية الاستعادة');
    } catch (e) {
      if (mounted) _message('تعذرت الاستعادة: $e');
    }
  }

  Future<void> _addYear() async {
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إضافة عام دراسي'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'اسم العام الدراسي',
            hintText: '2027 / 2028',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (name == null) return;

    try {
      await AccountingDb.instance.addYear(name);

      if (mounted) {
        setState(() {});
        _message('تمت إضافة العام الدراسي');
      }
    } catch (e) {
      if (mounted) _message('تعذرت إضافة العام: $e');
    }
  }

  Future<void> _addTransaction() async {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController();
    final categoryController = TextEditingController();
    final partyController = TextEditingController();
    final noteController = TextEditingController();

    String type = 'receipt';
    DateTime date = DateTime.now();

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            8,
            18,
            MediaQuery.of(context).viewInsets.bottom + 18,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'إضافة سند مالي',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'receipt',
                        label: Text('سند قبض'),
                        icon: Icon(Icons.call_received),
                      ),
                      ButtonSegment(
                        value: 'expense',
                        label: Text('سند صرف'),
                        icon: Icon(Icons.call_made),
                      ),
                    ],
                    selected: {type},
                    onSelectionChanged: (values) {
                      setSheetState(() => type = values.first);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'المبلغ *',
                    ),
                    validator: (v) {
                      final amount = double.tryParse(
                        (v ?? '').replaceAll(',', '').trim(),
                      );

                      if (amount == null || amount <= 0) {
                        return 'أدخل مبلغًا صحيحًا أكبر من صفر';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: categoryController,
                    decoration: InputDecoration(
                      labelText: type == 'receipt'
                          ? 'بند الإيراد'
                          : 'بند المصروف',
                      hintText: type == 'receipt'
                          ? 'رسوم دراسية'
                          : 'مستلزمات مدرسية',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: partyController,
                    decoration: const InputDecoration(
                      labelText: 'اسم المستلم / الدافع',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'البيان / ملاحظات',
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );

                      if (picked != null) {
                        setSheetState(() => date = picked);
                      }
                    },
                    icon: const Icon(Icons.calendar_month),
                    label: Text(
                      'تاريخ السند: ${DateFormat('yyyy-MM-dd').format(date)}',
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () {
                      if (formKey.currentState!.validate()) {
                        Navigator.pop(sheetContext, true);
                      }
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('حفظ السند'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result == true) {
      try {
        await AccountingDb.instance.addTransaction(
          type: type,
          amount: double.parse(
            amountController.text.replaceAll(',', '').trim(),
          ),
          category: categoryController.text,
          party: partyController.text,
          note: noteController.text,
          date: date,
        );

        await _refresh();

        if (mounted) _message('تم حفظ السند بنجاح');
      } catch (e) {
        if (mounted) _message('تعذر حفظ السند: $e');
      }
    }

    amountController.dispose();
    categoryController.dispose();
    partyController.dispose();
    noteController.dispose();
  }

  Future<void> _editSchoolSettings() async {
    final nameController = TextEditingController(text: _schoolName);
    final currencyController = TextEditingController(text: _currency);

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('بيانات المدرسة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'اسم المدرسة',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: currencyController,
              decoration: const InputDecoration(
                labelText: 'رمز العملة',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (result == true) {
      await AccountingDb.instance.saveSetting(
        'school_name',
        nameController.text.trim().isEmpty
            ? 'اسم المدرسة'
            : nameController.text.trim(),
      );

      await AccountingDb.instance.saveSetting(
        'currency',
        currencyController.text.trim().isEmpty
            ? 'ر.س'
            : currencyController.text.trim(),
      );

      await _refresh();

      if (mounted) _message('تم حفظ الإعدادات');
    }

    nameController.dispose();
    currencyController.dispose();
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18),
      child: Column(
        children: [
          Icon(
            icon,
            size: 48,
            color: const Color(0xFF8B9BB3),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}