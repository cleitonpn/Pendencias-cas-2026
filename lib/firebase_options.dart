import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => android;

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCnNKGHqpa59_FbDeXFNrADk6yYBiiUU0o',
    appId: '1:154690975923:android:088b42eb7d47c36b5258c6',
    messagingSenderId: '154690975923',
    projectId: 'montagem-uset',
    storageBucket: 'montagem-uset.firebasestorage.app',
  );
}
