import { initializeApp } from "firebase-admin/app";
import { getAuth, UserRecord } from "firebase-admin/auth";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const app = initializeApp();
const auth = getAuth(app);
const db = getFirestore(app);

type Role = "admin" | "supplier" | "customer";

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requiredString(
  value: unknown,
  field: string,
  maxLength = 200,
): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  const result = value.trim();
  if (result.length > maxLength) {
    throw new HttpsError("invalid-argument", `${field} is too long.`);
  }
  return result;
}

function validRole(value: unknown): value is Role {
  return value === "admin" || value === "supplier" || value === "customer";
}

function requiredPassword(value: unknown): string {
  if (typeof value !== "string" || value.length < 8 || value.length > 128) {
    throw new HttpsError(
      "invalid-argument",
      "Password must contain 8 to 128 characters.",
    );
  }
  return value;
}

async function assertAdmin(uid: string | undefined): Promise<void> {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  const snapshot = await db.collection("profiles").doc(uid).get();
  if (
    snapshot.data()?.role !== "admin" ||
    snapshot.data()?.suspended === true
  ) {
    throw new HttpsError("permission-denied", "Administrator access required.");
  }
}

async function assertSupplier(uid: unknown): Promise<void> {
  const supplierId = requiredString(uid, "Supplier", 128);
  const supplier = await db.collection("profiles").doc(supplierId).get();
  if (
    supplier.data()?.role !== "supplier" ||
    supplier.data()?.suspended === true
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Choose an active supplier account.",
    );
  }
}

function validatedProfile(
  role: Role,
  input: Record<string, unknown>,
): Record<string, unknown> {
  const profile: Record<string, unknown> = {
    role,
    name: requiredString(input.name, "Name", 100),
    suspended: input.suspended === true,
    updatedAt: FieldValue.serverTimestamp(),
  };
  const optionalStrings = ["address", "phone", "supplierId", "supplierName"];
  for (const field of optionalStrings) {
    const value = input[field];
    if (value !== undefined) {
      if (typeof value !== "string" || value.length > 300) {
        throw new HttpsError("invalid-argument", `${field} is invalid.`);
      }
      profile[field] = value.trim();
    }
  }
  if (role === "customer") {
    const dailyQuantity = input.dailyQuantity;
    const bottlePrice = input.bottlePrice;
    if (
      !Number.isInteger(dailyQuantity) ||
      typeof dailyQuantity !== "number" ||
      dailyQuantity < 1 ||
      dailyQuantity > 100
    ) {
      throw new HttpsError(
        "invalid-argument",
        "Daily quantity must be between 1 and 100.",
      );
    }
    if (
      typeof bottlePrice !== "number" ||
      !Number.isFinite(bottlePrice) ||
      bottlePrice < 0 ||
      bottlePrice > 10000000
    ) {
      throw new HttpsError("invalid-argument", "Bottle price is invalid.");
    }
    profile.dailyQuantity = dailyQuantity;
    profile.bottlePrice = bottlePrice;
    profile.deliverySuspended = input.deliverySuspended === true;
    profile.supplierId = requiredString(input.supplierId, "Supplier");
  }
  return profile;
}

export const createManagedUser = onCall(async (request) => {
  await assertAdmin(request.auth?.uid);
  if (!isRecord(request.data)) {
    throw new HttpsError("invalid-argument", "Invalid request.");
  }
  const { role, ...input } = request.data;
  if (!validRole(role)) {
    throw new HttpsError("invalid-argument", "Choose a valid user role.");
  }
  const email = requiredString(input.email, "Email", 254).toLowerCase();
  const password = requiredPassword(input.password);

  let user: UserRecord;
  try {
    user = await auth.createUser({
      email,
      password,
      displayName: requiredString(input.name, "Name", 100),
      disabled: input.suspended === true,
    });
  } catch (error) {
    throw new HttpsError(
      "already-exists",
      error instanceof Error ? error.message : "Could not create user.",
    );
  }

  try {
    const profile = validatedProfile(role, input);
    if (role === "customer") {
      await assertSupplier(profile.supplierId);
    }
    profile.email = email;
    profile.createdAt = FieldValue.serverTimestamp();
    await db.collection("profiles").doc(user.uid).create(profile);
    return { uid: user.uid };
  } catch (error) {
    try {
      await auth.deleteUser(user.uid);
    } catch (cleanupError) {
      console.error("Could not roll back Auth user creation", cleanupError);
    }
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", "Could not save the user profile.");
  }
});

export const updateManagedUser = onCall(async (request) => {
  await assertAdmin(request.auth?.uid);
  if (!isRecord(request.data) || !isRecord(request.data.profile)) {
    throw new HttpsError("invalid-argument", "Invalid user update.");
  }
  const uid = requiredString(request.data.uid, "User ID", 128);
  const reference = db.collection("profiles").doc(uid);
  const existing = await reference.get();
  const current = existing.data();
  if (!existing.exists || !current || !validRole(current.role)) {
    throw new HttpsError("not-found", "User profile was not found.");
  }
  if (uid === request.auth?.uid && request.data.profile.suspended === true) {
    throw new HttpsError(
      "failed-precondition",
      "You cannot suspend your own administrator account.",
    );
  }

  const authChanges: {
    email?: string;
    password?: string;
    displayName?: string;
    disabled?: boolean;
  } = {};
  const input = request.data.profile;
  if (input.email !== undefined) {
    authChanges.email = requiredString(input.email, "Email", 254).toLowerCase();
  }
  if (input.password !== undefined && input.password !== "") {
    authChanges.password = requiredPassword(input.password);
  }
  if (input.name !== undefined) {
    authChanges.displayName = requiredString(input.name, "Name", 100);
  }
  if (input.suspended !== undefined) {
    if (typeof input.suspended !== "boolean") {
      throw new HttpsError("invalid-argument", "Suspended must be a boolean.");
    }
    authChanges.disabled = input.suspended;
  }

  const nextProfile = validatedProfile(current.role, {
    ...current,
    ...input,
  });
  if (current.role === "customer") {
    await assertSupplier(nextProfile.supplierId);
  }
  if (authChanges.email) nextProfile.email = authChanges.email;
  if (input.password !== undefined) delete nextProfile.password;
  if (Object.keys(authChanges).length > 0) {
    await auth.updateUser(uid, authChanges);
  }
  await reference.set(nextProfile, { merge: true });
  return { uid };
});

export const deleteManagedUser = onCall(async (request) => {
  await assertAdmin(request.auth?.uid);
  const uid = requiredString(request.data?.uid, "User ID", 128);
  if (uid === request.auth?.uid) {
    throw new HttpsError(
      "failed-precondition",
      "You cannot delete your own administrator account.",
    );
  }
  const profileReference = db.collection("profiles").doc(uid);
  const profile = await profileReference.get();
  if (!profile.exists) {
    throw new HttpsError("not-found", "User profile was not found.");
  }
  if (profile.data()?.role === "supplier") {
    const assigned = await db
      .collection("profiles")
      .where("role", "==", "customer")
      .where("supplierId", "==", uid)
      .limit(1)
      .get();
    if (!assigned.empty) {
      throw new HttpsError(
        "failed-precondition",
        "Reassign this supplier’s customers before deleting the account.",
      );
    }
  }
  await auth.deleteUser(uid);
  await profileReference.delete();
  return { uid };
});

