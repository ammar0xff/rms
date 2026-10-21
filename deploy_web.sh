#!/usr/bin/env bash
set -e

echo "==> Building Flutter Web (Release)..."
flutter build web --release \
  --dart-define=FIREBASE_API_KEY=AIzaSyBWxqspTnEBI_i0QJ1uquD_tTn_0NIaS-U \
  --dart-define=FIREBASE_AUTH_DOMAIN=teletunnal.firebaseapp.com \
  --dart-define=FIREBASE_PROJECT_ID=teletunnal \
  --dart-define=FIREBASE_STORAGE_BUCKET=teletunnal.firebasestorage.app \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=285809811745 \
  --dart-define=FIREBASE_APP_ID=1:285809811745:web:065914e9d7a3c53f19de60 \
  --dart-define=APP_ENV=prod

echo "==> Deploying to Firebase Hosting (teletunnal)..."
npx --yes firebase-tools deploy --only hosting --project teletunnal

echo "==> Successfully deployed to https://teletunnal.web.app"
