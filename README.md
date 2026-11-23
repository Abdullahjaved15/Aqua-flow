# AquaFlow

AquaFlow is an offline-capable Flutter management app for a local water
filtration plant. Authentication and business records use Firebase
Authentication and Cloud Firestore.

## Run the app

```shell
flutter pub get
flutter run
```

The configured Firebase project is `aquaflow002`. Email/Password sign-in and
Cloud Firestore must be enabled in its Firebase Console. Firebase app options
currently exist for Android, web, and Windows.

## Initial administrator and deployment

Firebase Auth user creation is not exposed to the client. Seed the first admin
through Firebase Console:

1. Create an Email/Password user in **Authentication → Users**.
2. Create `profiles/{authUid}` in Firestore with the Auth user's `email`,
   `name`, `role: "admin"`, and `suspended: false`.
3. Select the Firebase project and deploy the security rules, indexes, and
   account-management functions:

```shell
firebase use aquaflow002
firebase deploy --only firestore,functions
```

Cloud Functions deployment requires a Firebase plan that supports Functions
and a Node.js 22 runtime.
On the no-cost Firebase plan, deploy only the Firestore rules and indexes with
`firebase deploy --only firestore`. Admin-side supplier and customer creation
uses a separate Firebase Auth session and writes each new profile to Firestore,
so it does not require Cloud Functions. Email/Password account creation must be
enabled in Firebase Authentication. The profile rules still prevent a newly
created, unprofiled account from assigning itself a role. Account edits that
change Auth credentials, suspensions, and deletion still use Cloud Functions
and require a plan that supports Functions. Payment balances and history do
not require Functions or push notification setup; they stream directly from
Firestore while the customer app is open.

After Functions deployment, the admin portal can update account details and
passwords, suspend/reactivate accounts, and delete accounts.
Existing delivery and payment records are retained when a customer account is
deleted. A supplier with assigned customers must have those customers
reassigned first.

## Modules

- **Admin:** live overview, customer and supplier accounts, customer delivery
  assignments and per-customer 19L rates, delivery pause/reactivation, bottle
  inventory and stock adjustments, cash point of sale, 80 mm PDF receipt
  printing, monthly delivery/payment ledger, daily delivery oversight, and
  administrator accounts.
- **Supplier:** assigned route, delivered/not-home status, outstanding customer
  balances, and cash or bank-transfer payment recording.
- **Customer:** current-month bottle and charge summary, outstanding balance,
  delivery history, and payment history. Payment records and balances update
  live from Firestore while the customer app is open; no push notification is
  sent.

Supplier delivery and payment writes are queued by Firestore while offline and
sync on reconnect. A supplier must sign in and load the route while online
before going offline. POS checkout and admin-managed account creation require
an internet connection.

## Firestore data

- `profiles/{authUid}`: account role and customer subscription/assignment data.
- `deliveries/{yyyy-MM-dd_customerUid}`: daily delivery attempt, quantity,
  price, and charge.
- `payments/{paymentId}`: customer, supplier, amount, method, and date.
- `products/{productId}`: bottle price, stock, and low-stock threshold.
- `stockMovements/{movementId}`: opening stock, adjustments, and POS movements.
- `sales/{saleId}`: cash sale receipt lines and total.

Customer profile fields include `supplierId`, `address`, `dailyQuantity`,
`bottlePrice`, `deliverySuspended`, and `suspended`. Do not store passwords in
Firestore; Firebase Authentication manages credentials.
