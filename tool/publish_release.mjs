// Publishes a release manifest to Firestore.
//
// The artifact itself is uploaded by the workflow, which creates a GitHub
// Release and passes the resulting download URL here. Keeping upload out of this
// script means the manifest is written from a single, auditable place and the
// hosting can change without touching it.
//
// Usage:
//   node tool/publish_release.mjs \
//     --reference https://github.com/OWNER/REPO/releases/download/v1.0.0-3/app.apk \
//     --sha256 <64 hex> --size <bytes> \
//     --platform android --version 1.0.0
//
// Requires:
//   FIREBASE_SERVICE_ACCOUNT  service-account JSON, used to authenticate
//   FIREBASE_PROJECT_ID       target project
//
// Artifacts are hosted on GitHub Releases rather than Cloud Storage because
// Cloud Storage requires a Blaze billing account. GitHub Releases needs no
// billing and gives stable public download URLs. The trade-off is that release
// assets on a public repository are world-readable; if a private bucket is
// wanted later, only the hosting changes — this script already takes the URL as
// an input.

import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

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

/** SHA-256 of a local file, so the workflow can hash without a second tool. */
function sha256Hex(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  const platform = required(args, 'platform');
  const version = required(args, 'version');
  const channel = args.channel || 'production';
  const severity = args.severity || 'recommended';
  const rolloutPercent = Number(args.rollout ?? '100');
  const status = args.status || 'active';
  const minSupportedVersion = args['min-supported'] || '0.0.0';
  const releaseNotes = args['release-notes'] || '';

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

  // Either a published download URL, or a local file to hash and describe.
  let reference = args.reference;
  let digest;
  let sizeBytes;

  if (reference) {
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
  } else {
    const artifactPath = required(args, 'artifact');
    reference = required(args, 'reference');
    digest = sha256Hex(artifactPath);
    sizeBytes = readFileSync(artifactPath).length;
  }

  const app = initializeApp({
    credential: cert(JSON.parse(rawServiceAccount)),
  });
  const db = getFirestore(app);

  // The next build number is derived from what is already published rather than
  // taken from the caller. Android refuses an update whose versionCode is not
  // strictly higher than the installed one, so a re-run of this workflow must
  // always produce something installable.
  const existing = await db.collection(COLLECTION).get();
  const highest = existing.docs.reduce((max, doc) => {
    const n = Number(doc.get('buildNumber') ?? 0);
    return Number.isFinite(n) && n > max ? n : max;
  }, 0);
  const buildNumber = Number(args['build-number'] || 0) || highest + 1;
  console.log(`Build number: ${buildNumber}`);
  console.log(`Artifact: ${reference} (${sizeBytes} bytes, sha256 ${digest})`);

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
      reference,
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
    forceAfter: args['force-after'] || null,
    rollbackTargetVersion: args['rollback-target'] || null,
    targetBranchIds: args.branches ? args.branches.split(',') : [],
    targetDeviceGroups: args['device-groups'] ? args['device-groups'].split(',') : [],
    manifestSchemaVersion: Number(args['manifest-schema'] || '1'),
    createdAt: FieldValue.serverTimestamp(),
  };

  await db.collection(COLLECTION).doc(releaseId).set(manifest, { merge: true });
  console.log(`Published release ${releaseId}`);

  // A per-platform pointer lets the client fetch one small document instead of
  // querying the whole collection.
  await db.collection('activeReleases').doc(platform).set(
    { releaseId, channel, updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  console.log(`Pointed activeReleases/${platform} at ${releaseId}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});