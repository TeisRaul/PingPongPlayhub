import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  void init() {
    _appLinks = AppLinks();
    
    // Check initial link if app was closed
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        _handleDeepLink(uri);
      }
    });

    // Listen for links while app is running or in background
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    }, onError: (err) {
      print('AppLinks error: $err');
    });
  }

  void _handleDeepLink(Uri uri) async {
    print('Received Deep Link: $uri');
    
    // Example: pingpongplayhub://pos-success?matchId=123
    if (uri.scheme == 'pingpongplayhub' && uri.host == 'pos-success') {
      final matchId = uri.queryParameters['matchId'];
      if (matchId != null && matchId.isNotEmpty) {
        try {
          await FirebaseFirestore.instance.collection('matches').doc(matchId).update({
            'paymentStatus': 'confirmed',
            'paymentMethod': 'Smart POS',
          });
          print('Match $matchId payment confirmed via Smart POS AppLink.');
        } catch (e) {
          print('Error confirming match via Smart POS: $e');
        }
      }
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
  }
}
