#!/usr/bin/env bash
# Runs PIE connected to live Firebase (teletunnal)
flutter run \
  --dart-define=FIREBASE_API_KEY=AIzaSyBWxqspTnEBI_i0QJ1uquD_tTn_0NIaS-U \
  --dart-define=FIREBASE_AUTH_DOMAIN=teletunnal.firebaseapp.com \
  --dart-define=FIREBASE_PROJECT_ID=teletunnal \
  --dart-define=FIREBASE_STORAGE_BUCKET=teletunnal.firebasestorage.app \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=285809811745 \
  --dart-define=FIREBASE_APP_ID=1:285809811745:web:065914e9d7a3c53f19de60 \
  --dart-define=APP_ENV=prod \
  "$@"
