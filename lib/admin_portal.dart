import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'firebase_options.dart';

const _adminTeal = Color(0xFF087F8C);
const _adminNavy = Color(0xFF103C4A);
const _adminMuted = Color(0xFF71858A);

class AdminPortal extends StatelessWidget {
  const AdminPortal({
    required this.user,
    required this.name,
    required this.section,
    super.key,
  });

  final User user;
  final String name;
  final int section;

  @override
  Widget build(BuildContext context) {
    return switch (section) {
      1 => _AccountsPage(
        role: 'customer',
        currentUid: user.uid,
        currentEmail: user.email ?? '',
      ),
      2 => _AccountsPage(
        role: 'supplier',
        currentUid: user.uid,
        currentEmail: user.email ?? '',
      ),
      3 => const _InventoryPage(),
      4 => const _PointOfSalePage(),
      5 => const _BillingPage(),
      6 => const _DeliveryOverviewPage(),
      7 => _AccountsPage(
        role: 'admin',
        currentUid: user.uid,
        currentEmail: user.email ?? '',
      ),
      _ => _AdminOverview(name: name),
    };
  }
}

class _AdminOverview extends StatelessWidget {
  const _AdminOverview({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Good day, $name',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        const Text(
          'Manage your plant from one place.',
          style: TextStyle(color: _adminMuted),
        ),
        const SizedBox(height: 20),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db
              .collection('profiles')
              .where('role', isEqualTo: 'customer')
              .snapshots(),
          builder: (context, customers) =>
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: db
                    .collection('profiles')
                    .where('role', isEqualTo: 'supplier')
                    .snapshots(),
                builder: (context, suppliers) =>
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: db
                          .collection('deliveries')
                          .where('deliveryDate', isEqualTo: _adminToday())
                          .snapshots(),
                      builder: (context, deliveries) =>
                          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: db.collection('products').snapshots(),
                            builder: (context, products) {
                              final activeCustomers =
                                  customers.data?.docs
                                      .where(
                                        (d) =>
                                            d.data()['suspended'] != true &&
                                            d.data()['deliverySuspended'] !=
                                                true,
                                      )
                                      .length ??
                                  0;
                              final activeSuppliers =
                                  suppliers.data?.docs
                                      .where(
                                        (d) => d.data()['suspended'] != true,
                                      )
                                      .length ??
                                  0;
                              final delivered =
                                  deliveries.data?.docs
                                      .where(
                                        (d) =>
                                            d.data()['status'] == 'delivered',
                                      )
                                      .length ??
                                  0;
                              final stockWarnings =
                                  products.data?.docs.where((d) {
                                    final data = d.data();
                                    return data['active'] != false &&
                                        (data['stock'] as num? ?? 0) <=
                                            (data['lowStockAt'] as num? ?? 0);
                                  }).length ??
                                  0;
                              return LayoutBuilder(
                                builder: (context, constraints) {
                                  final columns = constraints.maxWidth > 680
                                      ? 4
                                      : 2;
                                  final width =
                                      (constraints.maxWidth -
                                          (columns - 1) * 10) /
                                      columns;
                                  final metrics = [
                                    _MetricTile(
                                      label: 'Customers',
                                      value: '$activeCustomers',
                                      icon: Icons.people_outline,
                                    ),
                                    _MetricTile(
                                      label: 'Suppliers',
                                      value: '$activeSuppliers',
                                      icon: Icons.delivery_dining,
                                    ),
                                    _MetricTile(
                                      label: 'Delivered today',
                                      value: '$delivered',
                                      icon: Icons.task_alt,
                                    ),
                                    _MetricTile(
                                      label: 'Low stock items',
                                      value: '$stockWarnings',
                                      icon: Icons.warning_amber_outlined,
                                    ),
                                  ];
                                  return Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      for (final metric in metrics)
                                        SizedBox(width: width, child: metric),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                    ),
              ),
        ),
        const SizedBox(height: 22),
        Text('Daily operations', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        const _PortalHint(
          icon: Icons.sync_rounded,
          text:
              'Supplier delivery and payment entries are saved to Firestore '
              'and sync when a device reconnects.',
        ),
        const SizedBox(height: 10),
        const _PortalHint(
          icon: Icons.print_outlined,
          text:
              'Point-of-sale stock is checked and decremented transactionally. '
              'Receipts are formatted for 80 mm paper.',
        ),
      ],
    );
  }
}

class _AccountsPage extends StatelessWidget {
  const _AccountsPage({
    required this.role,
    required this.currentUid,
    required this.currentEmail,
  });
  final String role;
  final String currentUid;
  final String currentEmail;

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final usersQuery = db.collection('profiles').where('role', isEqualTo: role);
    final suppliersQuery = db
        .collection('profiles')
        .where('role', isEqualTo: 'supplier');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: role == 'customer' ? suppliersQuery.snapshots() : null,
      builder: (context, suppliers) {
        final supplierOptions =
            suppliers.data?.docs
                .map(
                  (doc) => _SupplierOption(
                    id: doc.id,
                    name:
                        '${doc.data()['name'] as String? ?? 'Supplier'}'
                        '${doc.data()['suspended'] == true ? ' (suspended)' : ''}',
                  ),
                )
                .toList() ??
            <_SupplierOption>[];
        return Column(
          children: [
            _PageHeader(
              title: switch (role) {
                'customer' => 'Customers',
                'supplier' => 'Suppliers',
                _ => 'Administrators',
              },
              actionLabel: switch (role) {
                'customer' => 'Add customer',
                'supplier' => 'Add supplier',
                _ => 'Add administrator',
              },
              onAction: () =>
                  _editAccount(context, role: role, suppliers: supplierOptions),
            ),
            if (role == 'customer' && suppliers.hasError)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: _PortalHint(
                  icon: Icons.error_outline,
                  text: 'Supplier list could not be loaded. Check Firestore access.',
                  error: true,
                ),
              ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: usersQuery.snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const _EmptyPortal(
                      'Could not load accounts. Check Firestore access.',
                    );
                  }
                  if (!snapshot.hasData) return const _PortalLoading();
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) {
                    return _EmptyPortal(switch (role) {
                      'customer' => 'No customers yet. Add the first customer to start a route.',
                      'supplier' => 'No suppliers yet. Add suppliers before assigning delivery routes.',
                      _ => 'No administrators yet.',
                    });
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: docs.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data();
                      final disabled = data['suspended'] == true;
                      final email =
                          data['email'] as String? ??
                          (doc.id == currentUid ? currentEmail : '');
                      final subtitle = role == 'customer'
                          ? '${data['address'] ?? 'No address'}  •  '
                                '${data['dailyQuantity'] ?? 1} × 19L at '
                                'Rs ${data['bottlePrice'] ?? 0}'
                          : '$email'
                                '${(data['phone'] as String? ?? '').isEmpty ? '' : '  •  ${data['phone']}'}';
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: disabled
                                ? const Color(0xFFFFECEA)
                                : const Color(0xFFE4F3F2),
                            child: Icon(switch (role) {
                              'customer' => Icons.person_outline,
                              'supplier' => Icons.delivery_dining,
                              _ => Icons.admin_panel_settings_outlined,
                            }, color: disabled ? Colors.red : _adminTeal),
                          ),
                          title: Text(data['name'] as String? ?? 'Unnamed'),
                          subtitle: Text(
                            disabled ? 'Suspended account' : subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) async {
                              if (action == 'edit') {
                                await _editAccount(
                                  context,
                                  role: role,
                                  suppliers: supplierOptions,
                                  uid: doc.id,
                                  profile: {
                                    ...data,
                                    if (data['email'] == null &&
                                        doc.id == currentUid)
                                      'email': currentEmail,
                                  },
                                );
                              } else if (action == 'suspend') {
                                await _setSuspended(
                                  context,
                                  uid: doc.id,
                                  suspended: !disabled,
                                );
                              } else if (action == 'delivery') {
                                await _setDeliverySuspended(
                                  context,
                                  uid: doc.id,
                                  suspended: data['deliverySuspended'] != true,
                                );
                              } else if (action == 'delete') {
                                await _deleteAccount(context, doc.id);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit details'),
                              ),
                              if (role != 'admin' || doc.id != currentUid)
                                PopupMenuItem(
                                  value: 'suspend',
                                  child: Text(
                                    disabled ? 'Reactivate' : 'Suspend',
                                  ),
                                ),
                              if (role == 'customer')
                                PopupMenuItem(
                                  value: 'delivery',
                                  child: Text(
                                    data['deliverySuspended'] == true
                                        ? 'Resume daily delivery'
                                        : 'Pause daily delivery',
                                  ),
                                ),
                              if (role != 'admin' || doc.id != currentUid)
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete account'),
                                ),
                            ],
                          ),
                          isThreeLine: role == 'customer',
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SupplierOption {
  const _SupplierOption({required this.id, required this.name});
  final String id;
  final String name;
}

Future<void> _editAccount(
  BuildContext context, {
  required String role,
  required List<_SupplierOption> suppliers,
  String? uid,
  Map<String, dynamic>? profile,
}) async {
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) =>
        _AccountDialog(role: role, suppliers: suppliers, profile: profile),
  );
  if (result == null || !context.mounted) return;
  try {
    if (uid == null) {
      await _createAccountWithSecondaryAuth(result);
    } else {
      final password = result.remove('password');
      await FirebaseFunctions.instance.httpsCallable('updateManagedUser').call({
        'uid': uid,
        'profile': {
          ...result,
          if (password is String && password.isNotEmpty) 'password': password,
        },
      });
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(uid == null ? 'Account created.' : 'Account updated.'),
        ),
      );
    }
  } on FirebaseFunctionsException catch (error) {
    if (context.mounted) {
      _showError(context, error.message ?? 'Could not save this account.');
    }
  } catch (error) {
    if (context.mounted) {
      _showError(context, 'Could not save this account: $error');
    }
  }
}

Future<void> _createAccountWithSecondaryAuth(
  Map<String, dynamic> input,
) async {
  const appName = 'aquaflowAccountCreation';
  final FirebaseApp accountApp = Firebase.apps.any(
    (app) => app.name == appName,
  )
      ? Firebase.app(appName)
      : await Firebase.initializeApp(
          name: appName,
          options: DefaultFirebaseOptions.currentPlatform,
        );
  final accountAuth = FirebaseAuth.instanceFor(app: accountApp);
  User? newUser;
  try {
    final credential = await accountAuth.createUserWithEmailAndPassword(
      email: (input['email'] as String).trim().toLowerCase(),
      password: input['password'] as String,
    );
    newUser = credential.user;
    if (newUser == null) {
      throw StateError('Firebase did not return the new account.');
    }
    await newUser.updateDisplayName(input['name'] as String);

    final role = input['role'] as String;
    final profile = <String, dynamic>{
      'email': (input['email'] as String).trim().toLowerCase(),
      'name': (input['name'] as String).trim(),
      'role': role,
      'phone': (input['phone'] as String? ?? '').trim(),
      'suspended': false,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (role == 'supplier') {
      profile['address'] = (input['address'] as String? ?? '').trim();
    } else if (role == 'customer') {
      final supplierId = input['supplierId'] as String;
      final supplier = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(supplierId)
          .get();
      if (supplier.data()?['role'] != 'supplier' ||
          supplier.data()?['suspended'] == true) {
        throw StateError('Choose an active supplier account.');
      }
      profile.addAll({
        'address': (input['address'] as String).trim(),
        'supplierId': supplierId,
        'supplierName': (input['supplierName'] as String? ?? '').trim(),
        'dailyQuantity': input['dailyQuantity'],
        'bottlePrice': input['bottlePrice'],
        'deliverySuspended': input['deliverySuspended'] == true,
      });
    } else {
      throw StateError('Only supplier and customer accounts can be added here.');
    }

    await FirebaseFirestore.instance
        .collection('profiles')
        .doc(newUser.uid)
        .set(profile);
  } catch (_) {
    if (newUser != null) {
      try {
        await newUser.delete();
      } catch (_) {
        // Keep the original creation error; the auth account may need cleanup.
      }
    }
    rethrow;
  } finally {
    await accountAuth.signOut();
  }
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({
    required this.role,
    required this.suppliers,
    this.profile,
  });
  final String role;
  final List<_SupplierOption> suppliers;
  final Map<String, dynamic>? profile;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _password;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _quantity;
  late final TextEditingController _price;
  String? _supplierId;

  bool get _isEditing => widget.profile != null;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile ?? {};
    _name = TextEditingController(text: profile['name'] as String? ?? '');
    _email = TextEditingController(text: profile['email'] as String? ?? '');
    _password = TextEditingController();
    _phone = TextEditingController(text: profile['phone'] as String? ?? '');
    _address = TextEditingController(text: profile['address'] as String? ?? '');
    _quantity = TextEditingController(text: '${profile['dailyQuantity'] ?? 1}');
    _price = TextEditingController(text: '${profile['bottlePrice'] ?? 0}');
    _supplierId = profile['supplierId'] as String?;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _address.dispose();
    _quantity.dispose();
    _price.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final supplier = widget.suppliers.where((item) => item.id == _supplierId);
    Navigator.of(context).pop({
      'role': widget.role,
      'name': _name.text.trim(),
      'email': _email.text.trim(),
      if (_password.text.isNotEmpty) 'password': _password.text,
      'phone': _phone.text.trim(),
      'address': _address.text.trim(),
      if (widget.role == 'customer') ...{
        'supplierId': _supplierId,
        'supplierName': supplier.isEmpty ? '' : supplier.first.name,
        'dailyQuantity': int.parse(_quantity.text),
        'bottlePrice': double.parse(_price.text),
        'deliverySuspended': widget.profile?['deliverySuspended'] == true,
      },
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCustomer = widget.role == 'customer';
    return AlertDialog(
      title: Text(
        '${_isEditing ? 'Edit' : 'Add'} '
        '${isCustomer ? 'customer' : 'supplier'}',
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FormField(
                  controller: _name,
                  label: 'Full name',
                  validator: _required,
                ),
                _FormField(
                  controller: _email,
                  label: 'Email',
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) =>
                      value == null ||
                          !RegExp(r'^[^@]+@[^@]+\.[^@]+$')
                              .hasMatch(value.trim())
                      ? 'Enter a valid email'
                      : null,
                ),
                _FormField(
                  controller: _password,
                  label: _isEditing
                      ? 'New password (leave blank to keep current)'
                      : 'Initial password (at least 8 characters)',
                  obscureText: true,
                  validator: (value) =>
                      !_isEditing && (value == null || value.length < 8)
                      ? 'Enter at least 8 characters'
                      : null,
                ),
                _FormField(
                  controller: _phone,
                  label: 'Phone number',
                  keyboardType: TextInputType.phone,
                ),
                if (!isCustomer)
                  _FormField(
                    controller: _address,
                    label: 'Delivery area / location',
                  ),
                if (isCustomer) ...[
                  _FormField(
                    controller: _address,
                    label: 'Delivery address',
                    validator: _required,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _supplierId,
                    decoration: const InputDecoration(
                      labelText: 'Assigned supplier',
                    ),
                    items: [
                      for (final supplier in widget.suppliers)
                        DropdownMenuItem(
                          value: supplier.id,
                          child: Text(supplier.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _supplierId = value),
                    validator: (value) =>
                        value == null ? 'Choose a supplier' : null,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _FormField(
                          controller: _quantity,
                          label: '19L bottles/day',
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            final number = int.tryParse(value ?? '');
                            return number == null || number < 1
                                ? 'Enter at least 1'
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _FormField(
                          controller: _price,
                          label: 'Price per bottle',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (value) {
                            final number = double.tryParse(value ?? '');
                            return number == null || number < 0
                                ? 'Enter a valid price'
                                : null;
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save account')),
      ],
    );
  }
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'This field is required' : null;

Future<void> _setSuspended(
  BuildContext context, {
  required String uid,
  required bool suspended,
}) async {
  try {
    await FirebaseFunctions.instance.httpsCallable('updateManagedUser').call({
      'uid': uid,
      'profile': {'suspended': suspended},
    });
  } on FirebaseFunctionsException catch (error) {
    if (context.mounted) _showError(context, error.message ?? 'Update failed.');
  } catch (error) {
    if (context.mounted) _showError(context, 'Update failed: $error');
  }
}

Future<void> _setDeliverySuspended(
  BuildContext context, {
  required String uid,
  required bool suspended,
}) async {
  try {
    await FirebaseFunctions.instance.httpsCallable('updateManagedUser').call({
      'uid': uid,
      'profile': {'deliverySuspended': suspended},
    });
  } on FirebaseFunctionsException catch (error) {
    if (context.mounted) {
      _showError(context, error.message ?? 'Could not change delivery status.');
    }
  } catch (error) {
    if (context.mounted) {
      _showError(context, 'Could not change delivery status: $error');
    }
  }
}

Future<void> _deleteAccount(BuildContext context, String uid) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete account?'),
      content: const Text(
        'The user will lose access. Existing delivery and payment history will '
        'remain for bookkeeping.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await FirebaseFunctions.instance.httpsCallable('deleteManagedUser').call({
      'uid': uid,
    });
  } on FirebaseFunctionsException catch (error) {
    if (context.mounted) {
      _showError(context, error.message ?? 'Could not delete the account.');
    }
  } catch (error) {
    if (context.mounted) {
      _showError(context, 'Could not delete the account: $error');
    }
  }
}

class _InventoryPage extends StatelessWidget {
  const _InventoryPage();

  @override
  Widget build(BuildContext context) {
    final products = FirebaseFirestore.instance.collection('products');
    return Column(
      children: [
        _PageHeader(
          title: 'Bottle inventory',
          actionLabel: 'Add bottle',
          onAction: () => _editProduct(context),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: products.orderBy('name').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const _EmptyPortal('Could not load bottle inventory.');
              }
              if (!snapshot.hasData) return const _PortalLoading();
              if (snapshot.data!.docs.isEmpty) {
                return const _EmptyPortal(
                  'No bottle products yet. Add mineral water bottle sizes to manage stock.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                itemCount: snapshot.data!.docs.length,
                separatorBuilder: (context, index) => const SizedBox(height: 9),
                itemBuilder: (context, index) {
                  final doc = snapshot.data!.docs[index];
                  final data = doc.data();
                  final stock = (data['stock'] as num? ?? 0).toInt();
                  final low = (data['lowStockAt'] as num? ?? 0).toInt();
                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFE4F3F2),
                        child: Icon(
                          Icons.water_drop_outlined,
                          color: _adminTeal,
                        ),
                      ),
                      title: Text(data['name'] as String? ?? 'Bottle'),
                      subtitle: Text(
                        '$stock in stock  •  Rs ${data['price'] ?? 0}  •  '
                        'Alert at $low',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          if (action == 'edit') {
                            _editProduct(context, id: doc.id, data: data);
                          } else if (action == 'stock') {
                            _adjustStock(context, doc.id, data);
                          } else if (action == 'toggle') {
                            _setProductActive(
                              context,
                              doc.id,
                              data['active'] != false,
                            );
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit product'),
                          ),
                          PopupMenuItem(
                            value: 'stock',
                            child: Text('Adjust stock'),
                          ),
                          PopupMenuItem(
                            value: 'toggle',
                            child: Text(
                              data['active'] == false
                                  ? 'Activate for sales'
                                  : 'Deactivate product',
                            ),
                          ),
                        ],
                      ),
                      tileColor: stock <= low
                          ? const Color(0xFFFFF8E9)
                          : Colors.transparent,
                    ),
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

Future<void> _setProductActive(
  BuildContext context,
  String id,
  bool active,
) async {
  try {
    await FirebaseFirestore.instance.collection('products').doc(id).update({
      'active': !active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  } catch (error) {
    if (context.mounted) {
      _showError(context, 'Could not update product: $error');
    }
  }
}

Future<void> _editProduct(
  BuildContext context, {
  String? id,
  Map<String, dynamic>? data,
}) async {
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => _ProductDialog(data: data),
  );
  if (result == null || !context.mounted) return;
  try {
    final db = FirebaseFirestore.instance;
    final ref = db.collection('products').doc(id);
    final batch = db.batch();
    if (id == null) {
      result['createdAt'] = FieldValue.serverTimestamp();
      final openingStock = result['stock'] as int;
      if (openingStock > 0) {
        final movement = db.collection('stockMovements').doc();
        batch.set(movement, {
          'productId': ref.id,
          'productName': result['name'],
          'change': openingStock,
          'reason': 'Opening stock',
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': FirebaseAuth.instance.currentUser?.uid,
        });
      }
    } else {
      result.remove('stock');
    }
    result['active'] = id == null ? true : data?['active'] != false;
    result['updatedAt'] = FieldValue.serverTimestamp();
    batch.set(ref, result, SetOptions(merge: true));
    await batch.commit();
  } catch (error) {
    if (context.mounted) _showError(context, 'Could not save bottle: $error');
  }
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({this.data});
  final Map<String, dynamic>? data;

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _stock;
  late final TextEditingController _alert;

  @override
  void initState() {
    super.initState();
    final data = widget.data ?? {};
    _name = TextEditingController(text: data['name'] as String? ?? '');
    _price = TextEditingController(text: '${data['price'] ?? ''}');
    _stock = TextEditingController(text: '${data['stock'] ?? '0'}');
    _alert = TextEditingController(text: '${data['lowStockAt'] ?? '5'}');
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _stock.dispose();
    _alert.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.data == null ? 'Add bottle product' : 'Edit product'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FormField(
                controller: _name,
                label: 'Product name / bottle size',
                validator: _required,
              ),
              _FormField(
                controller: _price,
                label: 'Counter price (Rs)',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  final price = double.tryParse(value ?? '');
                  return price == null || price < 0
                      ? 'Enter a non-negative price'
                      : null;
                },
              ),
              if (widget.data == null)
                _FormField(
                  controller: _stock,
                  label: 'Opening stock',
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final stock = int.tryParse(value ?? '');
                    return stock == null || stock < 0
                        ? 'Enter a non-negative whole number'
                        : null;
                  },
                ),
              _FormField(
                controller: _alert,
                label: 'Low stock alert at',
                keyboardType: TextInputType.number,
                validator: (value) {
                  final limit = int.tryParse(value ?? '');
                  return limit == null || limit < 0
                      ? 'Enter a non-negative whole number'
                      : null;
                },
              ),
            ],
          ),
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
            Navigator.pop(context, {
              'name': _name.text.trim(),
              'price': double.parse(_price.text),
              'stock': int.parse(_stock.text),
              'lowStockAt': int.parse(_alert.text),
              'active': true,
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

Future<void> _adjustStock(
  BuildContext context,
  String productId,
  Map<String, dynamic> product,
) async {
  final quantity = TextEditingController();
  final reason = TextEditingController();
  final adjustment = await showDialog<_StockAdjustment>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Adjust ${product['name']} stock'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Current stock: ${product['stock'] ?? 0}'),
          const SizedBox(height: 8),
          TextField(
            controller: quantity,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            decoration: const InputDecoration(
              labelText: 'Change (+ receive, - remove)',
            ),
          ),
          TextField(
            controller: reason,
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final value = int.tryParse(quantity.text);
            if (value == null || value == 0 || reason.text.trim().isEmpty) {
              return;
            }
            Navigator.pop(context, _StockAdjustment(value, reason.text.trim()));
          },
          child: const Text('Save adjustment'),
        ),
      ],
    ),
  );
  quantity.dispose();
  reason.dispose();
  if (adjustment == null || !context.mounted) return;
  final change = adjustment.quantity;
  try {
    final db = FirebaseFirestore.instance;
    final productRef = db.collection('products').doc(productId);
    final movementRef = db.collection('stockMovements').doc();
    await db.runTransaction((transaction) async {
      final current = await transaction.get(productRef);
      final stock = (current.data()?['stock'] as num?)?.toInt() ?? 0;
      if (!current.exists || stock + change < 0) {
        throw StateError('Stock cannot become negative.');
      }
      transaction.update(productRef, {
        'stock': stock + change,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(movementRef, {
        'productId': productId,
        'productName': product['name'],
        'change': change,
        'reason': adjustment.reason,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': FirebaseAuth.instance.currentUser?.uid,
      });
    });
  } catch (error) {
    if (context.mounted) _showError(context, 'Stock adjustment failed: $error');
  }
}

class _StockAdjustment {
  const _StockAdjustment(this.quantity, this.reason);
  final int quantity;
  final String reason;
}

class _PointOfSalePage extends StatefulWidget {
  const _PointOfSalePage();

  @override
  State<_PointOfSalePage> createState() => _PointOfSalePageState();
}

class _PointOfSalePageState extends State<_PointOfSalePage> {
  final Map<String, int> _cart = {};
  bool _checkout = false;

  Future<void> _completeSale(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> products,
  ) async {
    if (_cart.isEmpty || _checkout) return;
    setState(() => _checkout = true);
    final db = FirebaseFirestore.instance;
    final saleRef = db.collection('sales').doc();
    final entries = _cart.entries.toList();
    try {
      final sale = await db.runTransaction((transaction) async {
        final snapshots = <String, DocumentSnapshot<Map<String, dynamic>>>{};
        for (final entry in entries) {
          final ref = db.collection('products').doc(entry.key);
          snapshots[entry.key] = await transaction.get(ref);
        }
        var total = 0.0;
        final lines = <Map<String, dynamic>>[];
        for (final entry in entries) {
          final snapshot = snapshots[entry.key]!;
          final data = snapshot.data();
          if (!snapshot.exists || data == null || data['active'] == false) {
            throw StateError('A selected product is no longer available.');
          }
          final stock = (data['stock'] as num? ?? 0).toInt();
          if (stock < entry.value) {
            throw StateError('Not enough ${data['name']} in stock.');
          }
          final price = (data['price'] as num? ?? 0).toDouble();
          total += price * entry.value;
          lines.add({
            'productId': entry.key,
            'name': data['name'] ?? 'Bottle',
            'quantity': entry.value,
            'unitPrice': price,
            'amount': price * entry.value,
          });
        }
        for (final entry in entries) {
          final snapshot = snapshots[entry.key]!;
          final stock = (snapshot.data()!['stock'] as num? ?? 0).toInt();
          transaction.update(db.collection('products').doc(entry.key), {
            'stock': stock - entry.value,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          final movementRef = db.collection('stockMovements').doc();
          transaction.set(movementRef, {
            'productId': entry.key,
            'productName': snapshot.data()!['name'],
            'change': -entry.value,
            'reason': 'POS sale',
            'saleId': saleRef.id,
            'createdAt': FieldValue.serverTimestamp(),
            'createdBy': FirebaseAuth.instance.currentUser?.uid,
          });
        }
        final receipt = {
          'saleId': saleRef.id,
          'items': lines,
          'total': total,
          'paymentMethod': 'cash',
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': FirebaseAuth.instance.currentUser?.uid,
        };
        transaction.set(saleRef, receipt);
        return receipt;
      });
      if (!mounted) return;
      setState(_cart.clear);
      await _showReceipt(context, sale);
    } catch (error) {
      if (mounted) _showError(context, 'Sale could not be completed: $error');
    } finally {
      if (mounted) setState(() => _checkout = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('products')
          .where('active', isEqualTo: true)
          .orderBy('name')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _EmptyPortal('Could not load products for the counter.');
        }
        if (!snapshot.hasData) return const _PortalLoading();
        final products = snapshot.data!.docs;
        final total = _cart.entries.fold<double>(0, (value, entry) {
          final product = products.where((item) => item.id == entry.key);
          return value +
              (product.isEmpty
                  ? 0
                  : (product.first.data()['price'] as num? ?? 0) * entry.value);
        });
        return Column(
          children: [
            const _PageHeader(title: 'Point of sale'),
            Expanded(
              child: products.isEmpty
                  ? const _EmptyPortal(
                      'Add bottle products in Inventory before taking sales.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      itemCount: products.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final product = products[index];
                        final data = product.data();
                        final qty = _cart[product.id] ?? 0;
                        final stock = (data['stock'] as num? ?? 0).toInt();
                        return Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            title: Text(data['name'] as String? ?? 'Bottle'),
                            subtitle: Text(
                              'Rs ${data['price'] ?? 0}  •  $stock in stock',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Remove one',
                                  onPressed: qty == 0
                                      ? null
                                      : () => setState(() {
                                          if (qty == 1) {
                                            _cart.remove(product.id);
                                          } else {
                                            _cart[product.id] = qty - 1;
                                          }
                                        }),
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                                Text(
                                  '$qty',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Add one',
                                  onPressed: qty >= stock
                                      ? null
                                      : () => setState(
                                          () => _cart[product.id] = qty + 1,
                                        ),
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE5EEEE))),
              ),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _showRecentSales(context),
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: const Text('Recent sales / reprint'),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Cash sale total',
                              style: TextStyle(color: _adminMuted),
                            ),
                            Text(
                              'Rs ${total.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _cart.isEmpty || _checkout
                            ? null
                            : () => _completeSale(products),
                        icon: _checkout
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.print_outlined),
                        label: const Text('Charge & receipt'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<void> _showRecentSales(BuildContext pageContext) async {
  await showDialog<void>(
    context: pageContext,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Recent sales'),
      content: SizedBox(
        width: 440,
        height: 420,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('sales')
              .orderBy('createdAt', descending: true)
              .limit(25)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('Could not load sales history.'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.data!.docs.isEmpty) {
              return const Center(child: Text('No counter sales yet.'));
            }
            return ListView.separated(
              itemCount: snapshot.data!.docs.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final data = snapshot.data!.docs[index].data();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Rs ${data['total'] ?? 0}'),
                  subtitle: Text(
                    '${data['saleId'] ?? ''}  •  '
                    '${data['items'] is List ? (data['items'] as List).length : 0} items',
                  ),
                  trailing: IconButton(
                    tooltip: 'Print receipt',
                    icon: const Icon(Icons.print_outlined),
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                      await _showReceipt(pageContext, data);
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> _showReceipt(
  BuildContext context,
  Map<String, dynamic> sale,
) async {
  final printNow = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Sale complete'),
      content: Text(
        'Receipt ${sale['saleId']}\nTotal: Rs '
        '${(sale['total'] as num).toStringAsFixed(0)}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Done'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.print_outlined),
          label: const Text('Print 80 mm receipt'),
        ),
      ],
    ),
  );
  if (printNow != true || !context.mounted) return;
  try {
    final items = (sale['items'] as List).cast<Map<String, dynamic>>();
    final createdAt = sale['createdAt'];
    final receiptDate = createdAt is Timestamp
        ? createdAt.toDate()
        : DateTime.now();
    final document = pw.Document();
    final receiptHeight = math.max(110, 82 + items.length * 9).toDouble();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          80 * PdfPageFormat.mm,
          receiptHeight * PdfPageFormat.mm,
          marginAll: 4 * PdfPageFormat.mm,
        ),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                'AquaFlow',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Center(child: pw.Text('Water filtration plant')),
            pw.SizedBox(height: 8),
            pw.Text('Receipt: ${sale['saleId']}'),
            pw.Text('Date: $receiptDate'),
            pw.Divider(),
            for (final item in items)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Text('${item['name']} × ${item['quantity']}'),
                    ),
                    pw.Text('Rs ${item['amount']}'),
                  ],
                ),
              ),
            pw.Divider(),
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'TOTAL',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Text(
                  'Rs ${(sale['total'] as num).toStringAsFixed(0)}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Center(child: pw.Text('Thank you for your purchase')),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(
      name: 'AquaFlow-${sale['saleId']}',
      onLayout: (_) async => document.save(),
    );
  } catch (error) {
    if (context.mounted) _showError(context, 'Could not print receipt: $error');
  }
}

class _BillingPage extends StatefulWidget {
  const _BillingPage();

  @override
  State<_BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<_BillingPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _moveMonth(int offset) {
    setState(() => _month = DateTime(_month.year, _month.month + offset));
  }

  @override
  Widget build(BuildContext context) {
    final firstDay =
        '${_month.year.toString().padLeft(4, '0')}-'
        '${_month.month.toString().padLeft(2, '0')}-01';
    final lastDay =
        '${_month.year.toString().padLeft(4, '0')}-'
        '${_month.month.toString().padLeft(2, '0')}-31';
    final db = FirebaseFirestore.instance;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Monthly billing',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Previous month',
                onPressed: () => _moveMonth(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                _monthLabel(_month),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: () => _moveMonth(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db
                .collection('deliveries')
                .where('deliveryDate', isGreaterThanOrEqualTo: firstDay)
                .where('deliveryDate', isLessThanOrEqualTo: lastDay)
                .snapshots(),
            builder: (context, deliveries) =>
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: db
                      .collection('payments')
                      .where('paymentDate', isGreaterThanOrEqualTo: firstDay)
                      .where('paymentDate', isLessThanOrEqualTo: lastDay)
                      .snapshots(),
                  builder: (context, payments) =>
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: db
                            .collection('profiles')
                            .where('role', isEqualTo: 'customer')
                            .snapshots(),
                        builder: (context, customers) {
                          if (deliveries.hasError ||
                              payments.hasError ||
                              customers.hasError) {
                            return const _EmptyPortal(
                              'Could not load billing data for this month.',
                            );
                          }
                          if (!deliveries.hasData ||
                              !payments.hasData ||
                              !customers.hasData) {
                            return const _PortalLoading();
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
                          final customersById = {
                            for (final doc in customers.data!.docs)
                              doc.id: doc.data(),
                          };
                          final ids = {...charges.keys, ...paid.keys}.toList()
                            ..sort((a, b) {
                              final first =
                                  customersById[a]?['name'] as String? ?? a;
                              final second =
                                  customersById[b]?['name'] as String? ?? b;
                              return first.compareTo(second);
                            });
                          final monthCharges = charges.values.fold<double>(
                            0,
                            (a, b) => a + b,
                          );
                          final monthPaid = paid.values.fold<double>(
                            0,
                            (a, b) => a + b,
                          );
                          return ListView(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _MetricTile(
                                      label: 'Billed this month',
                                      value:
                                          'Rs ${monthCharges.toStringAsFixed(0)}',
                                      icon: Icons.receipt_long_outlined,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _MetricTile(
                                      label: 'Collected',
                                      value:
                                          'Rs ${monthPaid.toStringAsFixed(0)}',
                                      icon: Icons.payments_outlined,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (ids.isEmpty)
                                const _EmptyPortal(
                                  'No delivered bottles or payments for this month.',
                                )
                              else
                                for (final id in ids)
                                  _BillingCustomerRow(
                                    name:
                                        customersById[id]?['name'] as String? ??
                                        'Deleted customer',
                                    charges: charges[id] ?? 0,
                                    paid: paid[id] ?? 0,
                                  ),
                            ],
                          );
                        },
                      ),
                ),
          ),
        ),
      ],
    );
  }
}

class _BillingCustomerRow extends StatelessWidget {
  const _BillingCustomerRow({
    required this.name,
    required this.charges,
    required this.paid,
  });
  final String name;
  final double charges;
  final double paid;

  @override
  Widget build(BuildContext context) {
    final balance = math.max(0, charges - paid);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(name),
        subtitle: Text(
          'Billed Rs ${charges.toStringAsFixed(0)}  •  '
          'Paid Rs ${paid.toStringAsFixed(0)}',
        ),
        trailing: Text(
          'Rs ${balance.toStringAsFixed(0)} due',
          style: TextStyle(
            color: balance > 0 ? const Color(0xFFB36B15) : _adminTeal,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _DeliveryOverviewPage extends StatelessWidget {
  const _DeliveryOverviewPage();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _PageHeader(title: 'Today’s delivery route'),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('deliveries')
                .where('deliveryDate', isEqualTo: _adminToday())
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const _EmptyPortal('Could not load today’s deliveries.');
              }
              if (!snapshot.hasData) return const _PortalLoading();
              final records = snapshot.data!.docs;
              if (records.isEmpty) {
                return const _EmptyPortal(
                  'No delivery attempts recorded today.',
                );
              }
              records.sort(
                (a, b) => (a.data()['customerName'] as String? ?? '').compareTo(
                  b.data()['customerName'] as String? ?? '',
                ),
              );
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                itemCount: records.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final data = records[index].data();
                  final done = data['status'] == 'delivered';
                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: Icon(
                        done ? Icons.task_alt : Icons.door_front_door_outlined,
                        color: done ? _adminTeal : const Color(0xFFB36B15),
                      ),
                      title: Text(
                        data['customerName'] as String? ?? 'Customer',
                      ),
                      subtitle: Text(
                        '${data['supplierName'] ?? 'Supplier'}  •  '
                        '${data['quantity'] ?? 0} bottles',
                      ),
                      trailing: Text(
                        done ? 'Rs ${data['amount'] ?? 0}' : 'Not home',
                      ),
                    ),
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

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, this.actionLabel, this.onAction});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          if (actionLabel != null)
            FilledButton.tonalIcon(
              onPressed: onAction,
              icon: const Icon(Icons.add, size: 18),
              label: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _adminTeal),
            const SizedBox(height: 12),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 20,
                color: _adminNavy,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _adminMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortalHint extends StatelessWidget {
  const _PortalHint({
    required this.icon,
    required this.text,
    this.error = false,
  });
  final IconData icon;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? Colors.red : _adminTeal;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFFF0EF) : const Color(0xFFE7F4F3),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.label,
    this.validator,
    this.keyboardType,
    this.obscureText = false,
  });
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        obscureText: obscureText,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

class _EmptyPortal extends StatelessWidget {
  const _EmptyPortal(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _adminMuted, height: 1.5),
        ),
      ),
    );
  }
}

class _PortalLoading extends StatelessWidget {
  const _PortalLoading();

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(color: _adminTeal));
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
  );
}

String _adminToday() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

String _monthLabel(DateTime date) {
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
  return '${months[date.month - 1]} ${date.year}';
}
