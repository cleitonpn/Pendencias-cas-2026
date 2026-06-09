import 'dart:io';
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb ||
        (!kIsWeb &&
            (Platform.isWindows || Platform.isLinux || Platform.isMacOS))) {
      return web;
    }
    return android;
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCnNKGHqpa59_FbDeXFNrADk6yYBiiUU0o',
    appId: '1:154690975923:android:088b42eb7d47c36b5258c6',
    messagingSenderId: '154690975923',
    projectId: 'montagem-uset',
    storageBucket: 'montagem-uset.firebasestorage.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAqg0fPaDCOGckze6kkYY7V9lKRKUoic7I',
    appId: '1:154690975923:web:937904609f3a65505258c6',
    messagingSenderId: '154690975923',
    projectId: 'montagem-uset',
    storageBucket: 'montagem-uset.firebasestorage.app',
    authDomain: 'montagem-uset.firebaseapp.com',
  );
}
