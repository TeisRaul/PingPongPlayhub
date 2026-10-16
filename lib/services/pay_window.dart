// Fereastra în care se deschide pagina Stripe Checkout (doar pe web).
// Pe Android/iOS se folosește varianta goală: acolo plata merge prin PaymentSheet.
export 'pay_window_stub.dart' if (dart.library.js_interop) 'pay_window_web.dart';
