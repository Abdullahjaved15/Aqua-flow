import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import 'admin_portal.dart';

const _navy = Color(0xFF103C4A);
const _teal = Color(0xFF087F8C);
const _pale = Color(0xFFF2F8F8);
const _ink = Color(0xFF18343B);
const _muted = Color(0xFF71858A);

class AquaFlowApp extends StatelessWidget {
  const AquaFlowApp({super.key, this.startupError});

  final Object? startupError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AquaFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _pale,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _teal,
          primary: _teal,
          surface: Colors.white,
        ),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(
            color: _ink,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
          titleLarge: TextStyle(color: _ink, fontWeight: FontWeight.w700),
          bodyMedium: TextStyle(color: _ink, height: 1.4),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _pale,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
        ),
      ),
      home: startupError == null
          ? const _SessionGate()
          : _StartupFailure(error: startupError!),
    );
  }
}

class _SessionGate extends StatelessWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.hasError) {
          return _ErrorPage(message: 'Could not check your sign-in status.');
        }
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingPage();
        }
        final user = authSnapshot.data;
        if (user == null) return const _SignInPage();
        return _ProfileGate(user: user);
      },
    );
  }
}

class _ProfileGate extends StatelessWidget {
  const _ProfileGate({required this.user});
  final User user;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('profiles')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorPage(
            message:
                'Could not load your account. Check your connection '
                'and Firestore access, then try again.',
            onRetry: () => FirebaseAuth.instance.signOut(),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _LoadingPage();
        }
        final profile = snapshot.data?.data();
        if (profile == null) {
          return _AccountNotReady(
            email: user.email ?? '',
            onSignOut: FirebaseAuth.instance.signOut,
          );
        }
        if (profile['suspended'] == true) {
          return _AccountSuspended(onSignOut: FirebaseAuth.instance.signOut);
        }
        return _DashboardShell(user: user, profile: profile);
      },
    );
  }
}

class _SignInPage extends StatefulWidget {
  const _SignInPage();

  @override
  State<_SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<_SignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on FirebaseAuthException catch (error) {
      setState(
        () => _error = switch (error.code) {
          'invalid-credential' ||
          'user-not-found' ||
          'wrong-password' => 'Email or password is incorrect.',
          'network-request-failed' => 'No internet connection. Sign in once while online to use offline mode.',
          'too-many-requests' =>
            'Too many attempts. Please wait a moment and try again.',
          _ => error.message ?? 'Could not sign in. Please try again.',
        },
      );
    } catch (error) {
      setState(() => _error = 'Sign-in failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter your email above to reset your password.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent.')),
        );
      }
    } on FirebaseAuthException catch (error) {
      setState(() => _error = error.message ?? 'Could not send reset email.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _BrandMark(large: true),
                const SizedBox(height: 32),
                Text(
                  'Welcome back',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Sign in to manage your water service.',
                  style: TextStyle(color: _muted),
                ),
                const SizedBox(height: 28),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(
                          labelText: 'Email address',
                          prefixIcon: Icon(Icons.alternate_email_rounded),
                        ),
                        validator: (value) =>
                            value == null ||
                                !RegExp(r'^[^@]+@[^@]+\.[^@]+$')
                                    .hasMatch(value.trim())
                            ? 'Enter a valid email address'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _signIn(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Enter your password'
                            : null,
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _InlineNotice(message: _error!, isError: true),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _resetPassword,
                    child: const Text('Forgot password?'),
                  ),
                ),
                const SizedBox(height: 6),
                FilledButton(
                  onPressed: _busy ? null : _signIn,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 21,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign in'),
                ),
                const SizedBox(height: 22),
                const _OfflineHint(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardShell extends StatefulWidget {
  const _DashboardShell({required this.user, required this.profile});
  final User user;
  final Map<String, dynamic> profile;

  @override
  State<_DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<_DashboardShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final role = (widget.profile['role'] as String? ?? '').toLowerCase();
    final name =
        widget.profile['name'] as String? ??
        widget.user.displayName ??
        widget.user.email?.split('@').first ??
        'there';
    final tabs = switch (role) {
      'supplier' => const ['Today', 'My customers'],
      'customer' => const ['Overview', 'My activity'],
      'admin' => const [
        'Dashboard',
        'Customers',
        'Suppliers',
        'Inventory',
        'Point of sale',
        'Billing',
        'Deliveries',
        'Administrators',
      ],
      _ => const <String>[],
    };
    if (tabs.isEmpty) {
      return _ErrorPage(
        message:
            'Your account role is missing or not supported. '
            'Ask an administrator to check your profile.',
        onRetry: FirebaseAuth.instance.signOut,
      );
    }
    if (_tab >= tabs.length) _tab = 0;
    final content = switch (role) {
      'supplier' => _SupplierPage(user: widget.user, showCustomers: _tab == 1),
      'customer' => _CustomerPage(user: widget.user, showActivity: _tab == 1),
      _ => AdminPortal(user: widget.user, name: name, section: _tab),
    };
    return Scaffold(
      drawer: role == 'admin'
          ? Drawer(
              child: SafeArea(
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 22, 20, 16),
                      child: Row(
                        children: [
                          Icon(Icons.water_drop_rounded, color: _teal),
                          SizedBox(width: 10),
                          Text(
                            'Admin portal',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _navy,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        itemCount: tabs.length,
                        itemBuilder: (context, index) => ListTile(
                          selected: _tab == index,
                          leading: Icon(_navIcon(role, index)),
                          title: Text(tabs[index]),
                          onTap: () {
                            Navigator.pop(context);
                            setState(() => _tab = index);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      appBar: AppBar(
        titleSpacing: 12,
        title: const Text('AquaFlow'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Account menu',
            icon: const CircleAvatar(
              radius: 17,
              backgroundColor: Color(0xFFE0F2F1),
              child: Icon(Icons.person_outline_rounded, color: _teal, size: 19),
            ),
            onSelected: (value) {
              if (value == 'signout') FirebaseAuth.instance.signOut();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Text(widget.user.email ?? ''),
              ),
              const PopupMenuItem(value: 'signout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: content,
          ),
        ),
      ),
      bottomNavigationBar: role == 'admin'
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (index) => setState(() => _tab = index),
              destinations: [
                for (var index = 0; index < tabs.length; index++)
                  NavigationDestination(
                    icon: Icon(_navIcon(role, index)),
                    label: tabs[index],
                  ),
              ],
            ),
    );
  }
}

IconData _navIcon(String role, int index) {
  if (index == 0) return Icons.water_drop_outlined;
  return switch (role) {
    'supplier' => Icons.people_alt_outlined,
    'customer' => Icons.receipt_long_outlined,
    _ => switch (index) {
      1 => Icons.people_outline_rounded,
      2 => Icons.delivery_dining,
      3 => Icons.inventory_2_outlined,
      4 => Icons.point_of_sale_outlined,
      5 => Icons.receipt_long_outlined,
      6 => Icons.route_outlined,
      _ => Icons.admin_panel_settings_outlined,
    },
  };
}

class AdminPage extends StatelessWidget {
  const AdminPage({required this.name, required this.tab, super.key});
  final String name;
  final int tab;

  @override
  Widget build(BuildContext context) {
    if (tab == 1) return const _AdminCollectionPage();
    if (tab == 2) {
      return const _ComingSoonPage(
        title: 'Supplier accounts',
        subtitle:
            'Supplier account provisioning will be connected to a secure '
            'Firebase Admin endpoint.',
        icon: Icons.delivery_dining,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        Text(
          'Good day, $name',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 5),
        const Text(
          'Here is your water plant at a glance.',
          style: TextStyle(color: _muted),
        ),
        const SizedBox(height: 22),
        const _AdminMetrics(),
        const SizedBox(height: 22),
        Text('Operations', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        const _OperationCard(
          icon: Icons.inventory_2_outlined,
          title: 'Bottle inventory & point of sale',
          detail: 'Track mineral water stock and counter sales.',
          status: 'Next module',
        ),
        const SizedBox(height: 10),
        const _OperationCard(
          icon: Icons.route_outlined,
          title: 'Daily delivery operations',
          detail: 'Assign customers and monitor delivery progress.',
          status: 'Supplier app active',
        ),
        const SizedBox(height: 10),
        const _OperationCard(
          icon: Icons.receipt_long_outlined,
          title: 'Monthly billing',
          detail: 'Review customer deliveries, collections and balances.',
          status: 'Live records',
        ),
      ],
    );
  }
}

class _AdminMetrics extends StatelessWidget {
  const _AdminMetrics();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('profiles')
          .where('role', isEqualTo: 'customer')
          .snapshots(),
      builder: (context, customers) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('deliveries')
              .where('deliveryDate', isEqualTo: _todayKey())
              .snapshots(),
          builder: (context, deliveries) {
            final customerProfiles = customers.data?.docs ?? [];
            final activeCustomers = customerProfiles
                .where(
                  (doc) =>
                      doc.data()['suspended'] != true &&
                      doc.data()['deliverySuspended'] != true &&
                      doc.data()['supplierId'] is String,
                )
                .toList();
            final customerCount = activeCustomers.length;
            final deliveredCount =
                deliveries.data?.docs
                    .where((doc) => doc.data()['status'] == 'delivered')
                    .length ??
                0;
            final visitedCustomerIds =
                deliveries.data?.docs
                    .map((doc) => doc.data()['customerId'] as String?)
                    .whereType<String>()
                    .toSet() ??
                <String>{};
            final pendingCount = customers.hasError || deliveries.hasError
                ? null
                : activeCustomers
                      .where(
                        (customer) => !visitedCustomerIds.contains(customer.id),
                      )
                      .length;
            return LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 680 ? 3 : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 10) / columns;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: width,
                      child: _MetricCard(
                        label: 'Active customers',
                        value: '$customerCount',
                        icon: Icons.people_alt_outlined,
                        color: _teal,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _MetricCard(
                        label: 'Delivered today',
                        value: '$deliveredCount',
                        icon: Icons.task_alt_rounded,
                        color: const Color(0xFF27976D),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _MetricCard(
                        label: 'Awaiting delivery',
                        value: pendingCount == null ? '—' : '$pendingCount',
                        icon: Icons.pending_actions_rounded,
                        color: const Color(0xFFE29A30),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _AdminCollectionPage extends StatelessWidget {
  const _AdminCollectionPage();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Text(
            'Customers',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('profiles')
                .where('role', isEqualTo: 'customer')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const _CenteredMessage(
                  'Could not load customers. Check Firestore access.',
                );
              }
              if (!snapshot.hasData) return const _LoadingPage();
              if (snapshot.data!.docs.isEmpty) {
                return const _CenteredMessage(
                  'No customer profiles yet. Add profiles to the profiles '
                  'collection in Firestore to get started.',
                );
              }
              final customers = snapshot.data!.docs
                  .where((doc) => doc.data()['suspended'] != true)
                  .toList();
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                itemCount: customers.length,
                separatorBuilder: (context, index) => const SizedBox(height: 9),
                itemBuilder: (context, index) {
                  final doc = customers[index];
                  final data = doc.data();
                  return _PersonCard(
                    icon: Icons.person_outline_rounded,
                    name: data['name'] as String? ?? 'Customer',
                    subtitle: [
                      data['address'] as String? ?? 'Address not added',
                      if (data['supplierName'] is String)
                        'Supplier: ${data['supplierName']}',
                    ].join(' • '),
                    trailing:
                        '${data['dailyQuantity'] ?? 1} × Rs ${data['bottlePrice'] ?? 0}',
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SupplierPage extends StatelessWidget {
  const _SupplierPage({required this.user, required this.showCustomers});
  final User user;
  final bool showCustomers;

  @override
  Widget build(BuildContext context) {
    final today = _todayKey();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                showCustomers ? 'My customers' : 'Today’s deliveries',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 5),
              Text(
                showCustomers
                    ? 'Your assigned delivery route.'
                    : _displayDate(),
                style: const TextStyle(color: _muted),
              ),
              if (!showCustomers) ...[
                const SizedBox(height: 12),
                const _OfflineHint(),
              ],
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('profiles')
                .where('role', isEqualTo: 'customer')
                .where('supplierId', isEqualTo: user.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const _CenteredMessage(
                  'Could not load your route. Check your connection or '
                  'Firestore access.',
                );
              }
              if (!snapshot.hasData) return const _LoadingPage();
              final customers = snapshot.data!.docs
                  .where((doc) => doc.data()['suspended'] != true)
                  .toList();
              customers.sort(
                (a, b) => (a.data()['name'] as String? ?? '').compareTo(
                  b.data()['name'] as String? ?? '',
                ),
              );
              if (customers.isEmpty) {
                return const _CenteredMessage(
                  'No active customers are assigned to your account yet.',
                );
              }
              return _SupplierCustomerList(
                supplier: user,
                customers: customers,
                dateKey: today,
                showCustomers: showCustomers,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SupplierCustomerList extends StatelessWidget {
  const _SupplierCustomerList({
    required this.supplier,
    required this.customers,
    required this.dateKey,
    required this.showCustomers,
  });

  final User supplier;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> customers;
  final String dateKey;
  final bool showCustomers;

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db
          .collection('deliveries')
          .where('supplierId', isEqualTo: supplier.uid)
          .snapshots(),
      builder: (context, deliveries) =>
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db
                .collection('payments')
                .where('supplierId', isEqualTo: supplier.uid)
                .snapshots(),
            builder: (context, payments) {
              if (deliveries.hasError || payments.hasError) {
                return const _CenteredMessage(
                  'Could not load delivery balances. Check your connection.',
                );
              }
              if (!deliveries.hasData || !payments.hasData) {
                return const _LoadingPage();
              }
              final charges = <String, double>{};
              for (final doc in deliveries.data!.docs) {
                final data = doc.data();
                if (data['status'] != 'delivered') continue;
                final id = data['customerId'] as String?;
                if (id == null) continue;
                charges[id] =
                    (charges[id] ?? 0) +
                    ((data['amount'] as num?)?.toDouble() ?? 0);
              }
              final paid = <String, double>{};
              for (final doc in payments.data!.docs) {
                final data = doc.data();
                final id = data['customerId'] as String?;
                if (id == null) continue;
                paid[id] =
                    (paid[id] ?? 0) +
                    ((data['amount'] as num?)?.toDouble() ?? 0);
              }
              return _buildList({
                for (final customer in customers)
                  customer.id: math
                      .max(
                        0,
                        (charges[customer.id] ?? 0) - (paid[customer.id] ?? 0),
                      )
                      .toDouble(),
              });
            },
          ),
    );
  }

  Widget _buildList(Map<String, double> outstanding) {
    final visibleCustomers = showCustomers
        ? customers
        : customers
              .where((customer) => customer.data()['deliverySuspended'] != true)
              .toList();
    if (visibleCustomers.isEmpty) {
      return const _CenteredMessage(
        'Daily deliveries are paused for all assigned customers.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      itemCount: visibleCustomers.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final customer = visibleCustomers[index];
        final data = customer.data();
        return showCustomers
            ? Column(
                children: [
                  _PersonCard(
                    icon: Icons.person_outline_rounded,
                    name: data['name'] as String? ?? 'Customer',
                    subtitle:
                        '${data['deliverySuspended'] == true ? 'Delivery paused • ' : ''}'
                        '${data['address'] as String? ?? 'Address not added'}',
                    trailing: '${data['dailyQuantity'] ?? 1} bottles/day',
                  ),
                  if ((outstanding[customer.id] ?? 0) > 0)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _recordCustomerPayment(
                          context,
                          supplier: supplier,
                          customerId: customer.id,
                          customer: data,
                          outstanding: outstanding[customer.id]!,
                        ),
                        icon: const Icon(Icons.payments_outlined, size: 18),
                        label: Text(
                          'Collect Rs ${outstanding[customer.id]!.toStringAsFixed(0)}',
                        ),
                      ),
                    ),
                ],
              )
            : _DeliveryCard(
                supplier: supplier,
                customerId: customer.id,
                customer: data,
                dateKey: dateKey,
                outstanding: outstanding[customer.id] ?? 0,
              );
      },
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({
    required this.supplier,
    required this.customerId,
    required this.customer,
    required this.dateKey,
    required this.outstanding,
  });

  final User supplier;
  final String customerId;
  final Map<String, dynamic> customer;
  final String dateKey;
  final double outstanding;

  String get _deliveryId => '${dateKey}_$customerId';

  Future<void> _record(BuildContext context, String status) async {
    final quantity = status == 'delivered'
        ? (customer['dailyQuantity'] as num?)?.toInt() ?? 1
        : 0;
    final price = (customer['bottlePrice'] as num?)?.toDouble() ?? 0;
    try {
      await FirebaseFirestore.instance
          .collection('deliveries')
          .doc(_deliveryId)
          .set({
            'customerId': customerId,
            'customerName': customer['name'] ?? 'Customer',
            'supplierId': supplier.uid,
            'supplierName': supplier.displayName ?? supplier.email ?? '',
            'deliveryDate': dateKey,
            'status': status,
            'quantity': quantity,
            'unitPrice': price,
            'amount': quantity * price,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'delivered'
                  ? 'Delivery saved. It will sync when you’re online.'
                  : 'Visit recorded. You can update it later.',
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save this delivery: $error')),
        );
      }
    }
  }

  Future<void> _collectPayment(BuildContext context) async {
    await _recordCustomerPayment(
      context,
      supplier: supplier,
      customerId: customerId,
      customer: customer,
      outstanding: outstanding,
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = customer['name'] as String? ?? 'Customer';
    final address = customer['address'] as String? ?? 'Address not added';
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('deliveries')
          .doc(_deliveryId)
          .snapshots(),
      builder: (context, snapshot) {
        final record = snapshot.data?.data();
        final status = record?['status'] as String?;
        final done = status == 'delivered';
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _CircleIcon(icon: Icons.person_pin_circle_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          address,
                          style: const TextStyle(color: _muted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  if (status != null) _StatusPill(status: status),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.water_drop_outlined, size: 16, color: _teal),
                  const SizedBox(width: 5),
                  Text(
                    '${customer['dailyQuantity'] ?? 1} × 19L  ·  '
                    'Rs ${customer['bottlePrice'] ?? 0} each',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: _muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (status == 'delivered')
                    Text(
                      'Rs ${record?['amount'] ?? 0}',
                      style: const TextStyle(
                        color: _teal,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
              if (!done) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _record(context, 'delivered'),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Delivered'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _record(context, 'not_home'),
                        icon: const Icon(
                          Icons.door_front_door_outlined,
                          size: 17,
                        ),
                        label: const Text('Not home'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          foregroundColor: _muted,
                          side: const BorderSide(color: Color(0xFFD8E5E5)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (outstanding > 0) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _collectPayment(context),
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: Text(
                      'Collect payment  ·  Rs ${outstanding.toStringAsFixed(0)} due',
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PaymentDetails {
  const _PaymentDetails({
    required this.amount,
    required this.method,
    required this.note,
  });

  final double amount;
  final String method;
  final String note;
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.maximum});
  final double maximum;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _method = 'cash';

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record customer payment'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Outstanding: Rs ${widget.maximum.toStringAsFixed(0)}',
              style: const TextStyle(color: _teal, fontWeight: FontWeight.w700),
            ),
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount received (Rs)',
              ),
              validator: (value) {
                final amount = double.tryParse(value ?? '');
                if (amount == null || amount <= 0) {
                  return 'Enter an amount greater than zero';
                }
                if (amount > widget.maximum) {
                  return 'Cannot exceed the outstanding amount';
                }
                return null;
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Payment method'),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(
                  value: 'bank_transfer',
                  child: Text('Bank transfer'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _method = value);
              },
            ),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Reference / note (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _PaymentDetails(
                amount: double.parse(_amount.text),
                method: _method,
                note: _note.text.trim(),
              ),
            );
          },
          child: const Text('Save payment'),
        ),
      ],
    );
  }
}

Future<void> _recordCustomerPayment(
  BuildContext context, {
  required User supplier,
  required String customerId,
  required Map<String, dynamic> customer,
  required double outstanding,
}) async {
  final payment = await showDialog<_PaymentDetails>(
    context: context,
    builder: (context) => _PaymentDialog(maximum: outstanding),
  );
  if (payment == null || !context.mounted) return;
  try {
    final reference = FirebaseFirestore.instance.collection('payments').doc();
    await reference.set({
      'customerId': customerId,
      'customerName': customer['name'] ?? 'Customer',
      'supplierId': supplier.uid,
      'supplierName': supplier.displayName ?? supplier.email ?? '',
      'amount': payment.amount,
      'method': payment.method,
      'note': payment.note,
      'paymentDate': _todayKey(),
      'recordedAt': FieldValue.serverTimestamp(),
      'status': 'received',
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment recorded and will sync when online.'),
        ),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not record payment: $error')),
      );
    }
  }
}

class _CustomerPage extends StatelessWidget {
  const _CustomerPage({required this.user, required this.showActivity});
  final User user;
  final bool showActivity;

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Text(
            showActivity ? 'My activity' : 'My water service',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db
                .collection('deliveries')
                .where('customerId', isEqualTo: user.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const _CenteredMessage(
                  'Could not load your records. Check Firestore access.',
                );
              }
              if (!snapshot.hasData) return const _LoadingPage();
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: db
                    .collection('payments')
                    .where('customerId', isEqualTo: user.uid)
                    .snapshots(),
                builder: (context, payments) {
                  if (payments.hasError) {
                    return const _CenteredMessage(
                      'Could not load your payments. Check Firestore access.',
                    );
                  }
                  if (!payments.hasData) return const _LoadingPage();
                  return _CustomerRecords(
                    deliveries: snapshot.data!.docs,
                    payments: payments.data!.docs,
                    showActivity: showActivity,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CustomerRecords extends StatelessWidget {
  const _CustomerRecords({
    required this.deliveries,
    required this.payments,
    required this.showActivity,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> deliveries;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> payments;
  final bool showActivity;

  @override
  Widget build(BuildContext context) {
    final deliveryRecords = deliveries.toList()
      ..sort(
        (a, b) => (b.data()['deliveryDate'] as String? ?? '').compareTo(
          a.data()['deliveryDate'] as String? ?? '',
        ),
      );
    final paymentRecords = payments.toList()
      ..sort(
        (a, b) => (b.data()['paymentDate'] as String? ?? '').compareTo(
          a.data()['paymentDate'] as String? ?? '',
        ),
      );
    final delivered = deliveryRecords.where(
      (doc) => doc.data()['status'] == 'delivered',
    );
    final charges = delivered.fold<double>(
      0,
      (total, doc) => total + ((doc.data()['amount'] as num?)?.toDouble() ?? 0),
    );
    final bottlesThisMonth = delivered
        .where(
          (doc) => (doc.data()['deliveryDate'] as String? ?? '').startsWith(
            _todayKey().substring(0, 7),
          ),
        )
        .fold<int>(
          0,
          (total, doc) =>
              total + ((doc.data()['quantity'] as num?)?.toInt() ?? 0),
        );
    final monthCharges = delivered
        .where(
          (doc) => (doc.data()['deliveryDate'] as String? ?? '').startsWith(
            _todayKey().substring(0, 7),
          ),
        )
        .fold<double>(
          0,
          (total, doc) =>
              total + ((doc.data()['amount'] as num?)?.toDouble() ?? 0),
        );
    final totalPaid = paymentRecords.fold<double>(
      0,
      (total, doc) => total + ((doc.data()['amount'] as num?)?.toDouble() ?? 0),
    );
    final outstanding = math.max(0, charges - totalPaid).toDouble();
    if (showActivity) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(
            'Delivery history',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 9),
          if (deliveryRecords.isEmpty)
            const _InlineNotice(
              message: 'Your delivery history will appear here.',
            )
          else
            for (final doc in deliveryRecords)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PersonCard(
                  icon: doc.data()['status'] == 'delivered'
                      ? Icons.water_drop_outlined
                      : Icons.door_front_door_outlined,
                  name: _formatDate(
                    doc.data()['deliveryDate'] as String? ?? '',
                  ),
                  subtitle: doc.data()['status'] == 'delivered'
                      ? '${doc.data()['quantity'] ?? 0} bottles delivered'
                      : 'Delivery attempt — not home',
                  trailing: doc.data()['status'] == 'delivered'
                      ? 'Rs ${doc.data()['amount'] ?? 0}'
                      : '—',
                ),
              ),
          const SizedBox(height: 14),
          Text(
            'Payments received',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 9),
          if (paymentRecords.isEmpty)
            const _InlineNotice(
              message:
                  'Cash and transfer payments recorded by your supplier '
                  'will appear here.',
            )
          else
            for (final doc in paymentRecords)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PersonCard(
                  icon: Icons.payments_outlined,
                  name: _formatDate(doc.data()['paymentDate'] as String? ?? ''),
                  subtitle:
                      '${doc.data()['method'] == 'cash' ? 'Cash' : 'Bank transfer'}'
                      '${(doc.data()['note'] as String? ?? '').isEmpty ? '' : ' • ${doc.data()['note']}'}',
                  trailing: 'Rs ${doc.data()['amount'] ?? 0}',
                ),
              ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        _BalanceCard(
          amount: outstanding,
          subtitle: 'Recorded delivery charges less payments',
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: '19L bottles this month',
                value: '$bottlesThisMonth',
                icon: Icons.water_drop_outlined,
                color: _teal,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                label: 'This month’s bill',
                value: 'Rs ${monthCharges.toStringAsFixed(0)}',
                icon: Icons.receipt_long_outlined,
                color: const Color(0xFF27976D),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _InlineNotice(
          message:
              'Payments recorded: Rs ${totalPaid.toStringAsFixed(0)}. '
              'Open My activity to see payment dates and methods.',
        ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.amount, required this.subtitle});
  final double amount;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [_navy, _teal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Outstanding balance',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Text(
            'Rs ${amount.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CircleIcon(icon: icon, color: color),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.status,
  });
  final IconData icon;
  final String title;
  final String detail;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          _CircleIcon(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                const SizedBox(height: 7),
                Text(
                  status,
                  style: const TextStyle(
                    color: _teal,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: _muted),
        ],
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.icon,
    required this.name,
    required this.subtitle,
    required this.trailing,
  });
  final IconData icon;
  final String name;
  final String subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          _CircleIcon(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            trailing,
            style: const TextStyle(
              color: _teal,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final delivered = status == 'delivered';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: delivered ? const Color(0xFFE5F5EF) : const Color(0xFFFFF3DF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        delivered ? 'Delivered' : 'Not home',
        style: TextStyle(
          color: delivered ? const Color(0xFF21845D) : const Color(0xFFB1761D),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon, this.color = _teal});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color, size: 21),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.large = false});
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: large ? 54 : 38,
          height: large ? 54 : 38,
          decoration: BoxDecoration(
            color: _teal,
            borderRadius: BorderRadius.circular(large ? 18 : 13),
          ),
          child: Icon(
            Icons.water_drop_rounded,
            size: large ? 29 : 21,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'AquaFlow',
          style: TextStyle(
            color: _navy,
            fontSize: large ? 25 : 19,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}

class _OfflineHint extends StatelessWidget {
  const _OfflineHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F4F4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.sync_rounded, color: _teal, size: 17),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline ready — saved delivery updates sync when you reconnect.',
              style: TextStyle(color: _navy, fontSize: 11.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.message, this.isError = false});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? const Color(0xFFB33B32) : _teal;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFFEEEC) : const Color(0xFFEAF5F4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComingSoonPage extends StatelessWidget {
  const _ComingSoonPage({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _CenteredMessage(subtitle, title: title, icon: icon);
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage(this.message, {this.title, this.icon});
  final String message;
  final String? title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              _CircleIcon(icon: icon!, color: _teal),
              const SizedBox(height: 14),
            ],
            if (title != null) ...[
              Text(
                title!,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: _teal)),
    );
  }
}

class _ErrorPage extends StatelessWidget {
  const _ErrorPage({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CenteredMessage(
                message,
                title: 'Something went wrong',
                icon: Icons.cloud_off_outlined,
              ),
              if (onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  child: const Text('Sign out and try again'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _CenteredMessage(
        'Firebase could not start. Check the Firebase configuration for this '
        'platform and restart the app.\n\n$error',
        title: 'AquaFlow could not start',
        icon: Icons.cloud_off_outlined,
      ),
    );
  }
}

class _AccountNotReady extends StatelessWidget {
  const _AccountNotReady({required this.email, required this.onSignOut});
  final String email;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _CenteredMessage(
                'This account has no AquaFlow profile yet. Ask an administrator '
                'to provision your role in the profiles collection.',
                title: 'Account setup required',
                icon: Icons.person_search_outlined,
              ),
              TextButton(
                onPressed: onSignOut,
                child: Text('Sign out of $email'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountSuspended extends StatelessWidget {
  const _AccountSuspended({required this.onSignOut});
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _CenteredMessage(
                'This account has been suspended. Contact the water plant '
                'administrator for help.',
                title: 'Account suspended',
                icon: Icons.pause_circle_outline_rounded,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onSignOut,
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

BoxDecoration _cardDecoration() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(17),
  border: Border.all(color: const Color(0xFFE9F0F0)),
  boxShadow: const [
    BoxShadow(color: Color(0x080C3F46), blurRadius: 16, offset: Offset(0, 5)),
  ],
);

String _todayKey() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

String _displayDate() {
  final now = DateTime.now();
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${now.day} ${months[now.month - 1]} ${now.year}';
}

String _formatDate(String value) {
  final parts = value.split('-');
  if (parts.length != 3) return value;
  return '${parts[2]}/${parts[1]}/${parts[0]}';
}
