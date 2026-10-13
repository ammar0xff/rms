// Publishes a release manifest to Firestore and uploads the artifact to
// Cloud Storage.
//
// Invoked by .github/workflows/release.yml after a build. Kept as a separate
// script so the workflow stays declarative and the manifest shape lives in one
// auditable place — it must match UpdateManifest.toRecord() on the client, or
// the client silently treats the document as absent.
//
// Usage:
//   node tool/publish_release.mjs \
//     --artifact <path> --platform android --version 0.9.0 \
//     --channel production --severity recommended --rollout 100
//
// Requires:
//   FIREBASE_SERVICE_ACCOUNT  service-account JSON, used to authenticate
//   FIREBASE_PROJECT_ID       target project

import { readFileSync, statSync } from 'node:fs';
import { basename } from 'node:path';
import { createHash } from 'node:crypto';

import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';

const COLLECTION = 'releases';

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) continue;
    const key = token.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) {
      out[key] = 'true';
    } else {
      out[key] = next;
      i += 1;
    }
  }
  return out;
}

function required(args, key) {
  const value = args[key];
  if (!value) {
    console.error(`Missing required argument --${key}`);
    process.exit(2);
  }
  return value;
}

function sha256Hex(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  // Workflow B builds and uploads the artifact. Workflow A is the same
  // publisher pointed at an artifact that already exists: pass --reference and
  // nothing is uploaded, only the manifest is written.
  const uploadLocally = !args.reference;
  const artifactPath = uploadLocally ? required(args, 'artifact') : null;
  const platform = required(args, 'platform');
  const version = required(args, 'version');
  const channel = args.channel || 'production';
  const severity = args.severity || 'recommended';
  const rolloutPercent = Number(args.rollout ?? '100');
  const status = args.status || 'active';
  const minSupportedVersion = args['min-supported'] || '0.0.0';
  const releaseNotes = args['release-notes'] || '';
  const forceAfter = args['force-after'] || null;
  const rollbackTargetVersion = args['rollback-target'] || null;

  if (!Number.isInteger(rolloutPercent) || rolloutPercent < 1 || rolloutPercent > 100) {
    console.error('--rollout must be an integer between 1 and 100');
    process.exit(2);
  }

  const rawServiceAccount = process.env.FIREBASE_SERVICE_ACCOUNT;
  const projectId = process.env.FIREBASE_PROJECT_ID;
  if (!rawServiceAccount || !projectId) {
    console.error('FIREBASE_SERVICE_ACCOUNT and FIREBASE_PROJECT_ID must be set');
    process.exit(2);
  }

  const app = initializeApp({
    credential: cert(JSON.parse(rawServiceAccount)),
    storageBucket: `${projectId}.firebasestorage.app`,
  });
  const db = getFirestore(app);
  const bucket = getStorage(app).bucket();

  // The next build number is derived from what is already published rather than
  // taken from the caller. Android refuses an update whose versionCode is not
  // strictly higher than the installed one, so a re-run of this workflow must
  // always produce something installable.
  const existing = await db.collection(COLLECTION).get();
  const highest = existing.docs.reduce((max, doc) => {
    const n = Number(doc.get('buildNumber') ?? 0);
    return Number.isFinite(n) && n > max ? n : max;
  }, 0);
  const buildNumber = highest + 1;
  console.log(`Build number: ${highest} -> ${buildNumber}`);

  let digest;
  let sizeBytes;
  let objectName;

  if (uploadLocally) {
    digest = sha256Hex(artifactPath);
    sizeBytes = statSync(artifactPath).size;
    objectName = `releases/${platform}/${version}/${buildNumber}/${basename(artifactPath)}`;
    await bucket.file(objectName).save(readFileSync(artifactPath), {
      contentType: 'application/octet-stream',
      metadata: { cacheControl: 'private, max-age=0, no-store' },
    });
    console.log(`Uploaded ${objectName} (${sizeBytes} bytes, sha256 ${digest})`);
  } else {
    // The artifact is already in Storage. Its checksum and size must be
    // supplied, because the manifest is the only thing the client trusts when
    // it decides whether to install.
    objectName = args.reference;
    digest = required(args, 'sha256').toLowerCase();
    sizeBytes = Number(required(args, 'size'));
    if (!/^[0-9a-f]{64}$/.test(digest)) {
      console.error('--sha256 must be 64 lowercase hex characters');
      process.exit(2);
    }
    if (!Number.isInteger(sizeBytes) || sizeBytes < 0) {
      console.error('--size must be a non-negative integer');
      process.exit(2);
    }
    const [exists] = await bucket.file(objectName).exists();
    if (!exists) {
      console.error(`No such object in Storage: ${objectName}`);
      process.exit(2);
    }
    console.log(`Using existing artifact ${objectName} (${sizeBytes} bytes)`);
  }

  // Matches UpdateManifest.toRecord() on the client.
  const releaseId = `${platform}-${version}-${buildNumber}`;
  const manifest = {
    releaseId,
    version,
    buildNumber,
    platform,
    architecture: args.architecture || '',
    channel,
    status,
    rolloutPercent,
    severity,
    publishedAt: new Date().toISOString(),
    artifact: {
      reference: objectName,
      sizeBytes,
      sha256: digest,
      signature: '',
      expiresAt: null,
    },
    minSupportedVersion,
    minBackendVersion: null,
    maxBackendVersion: null,
    localSchemaMin: null,
    localSchemaMax: null,
    requiredMigrationVersion: args['migration-version']
      ? Number(args['migration-version'])
      : null,
    releaseNotes,
    expiresAt: args['expires-at'] || null,
    forceAfter,
    rollbackTargetVersion,
    targetBranchIds: args['branches'] ? args['branches'].split(',') : [],
    targetDeviceGroups: args['device-groups']
      ? args['device-groups'].split(',')
      : [],
    manifestSchemaVersion: Number(args['manifest-schema'] || '1'),
    createdAt: FieldValue.serverTimestamp(),
  };

  await db.collection(COLLECTION).doc(releaseId).set(manifest, { merge: true });
  console.log(`Published release ${releaseId}`);

  // A per-platform pointer lets the client fetch a single document instead of
  // querying the whole collection.
  await db.collection('activeReleases').doc(platform).set(
    {
      releaseId,
      channel,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  console.log(`Pointed activeReleases/${platform} at ${releaseId}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});