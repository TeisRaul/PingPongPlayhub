// Service worker pentru notificările push din browser (Firebase Cloud Messaging).
// Trebuie să stea în rădăcina site-ului web (web/), ca să fie servit la /firebase-messaging-sw.js.
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDS0KVNyhW5-3y72ojQo0SciuWp-iFPwTk',
  authDomain: 'pingpongplayhub1.firebaseapp.com',
  projectId: 'pingpongplayhub1',
  storageBucket: 'pingpongplayhub1.firebasestorage.app',
  messagingSenderId: '265197532784',
  appId: '1:265197532784:web:af8400b9d9849a058726b5',
});

// Mesajele cu câmpul "notification" sunt afișate automat de browser când aplicația e în fundal.
firebase.messaging();

self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({type: 'window', includeUncontrolled: true}).then(function (list) {
      for (const c of list) {
        if ('focus' in c) return c.focus();
      }
      if (clients.openWindow) return clients.openWindow('/');
    })
  );
});
