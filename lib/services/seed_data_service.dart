import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:faker/faker.dart';
import 'dart:math';

class SeedDataService {
  static Future<void> seedAll() async {
    final firestore = FirebaseFirestore.instance;

    // 1. Create fake Users (2 normal, 1 trainer)
    final user1Ref = firestore.collection('users').doc('fake_user_1');
    await user1Ref.set({
      'username': 'Alex Jucător',
      'email': 'alex@test.com',
      'role': 'player',
      'rating': 1200,
      'isTrainer': false,
      'trustScore': 100,
      'followers': [],
      'following': [],
      'bio': 'Îmi place ping pong-ul și joc în fiecare weekend.',
      'avatarUrl': '', // Optional base64
    });

    final user2Ref = firestore.collection('users').doc('fake_user_2');
    await user2Ref.set({
      'username': 'Maria Popa',
      'email': 'maria@test.com',
      'role': 'player',
      'rating': 900,
      'isTrainer': false,
      'trustScore': 95,
      'followers': ['fake_user_1'],
      'following': [],
      'bio': 'Sunt nouă, vreau să învăț!',
      'avatarUrl': '',
    });

    final trainerRef = firestore.collection('users').doc('fake_trainer_1');
    await trainerRef.set({
      'username': 'Mihai Antrenorul',
      'email': 'mihai@test.com',
      'role': 'player',
      'rating': 2500,
      'isTrainer': true,
      'trainerPrice': 100.0,
      'trustScore': 100,
      'followers': ['fake_user_1', 'fake_user_2'],
      'following': [],
      'bio': 'Fost campion național, ofer antrenamente private. Pentru programări dă-mi un mesaj!',
      'avatarUrl': '',
    });

    // 2. Create fake Posts in Feed
    final post1Ref = await firestore.collection('posts').add({
      'authorUid': 'fake_trainer_1',
      'authorUsername': 'Mihai Antrenorul',
      'authorAvatarUrl': '',
      'content': 'Astăzi la antrenament am exersat forehand-ul top spin. Voi cât de des repetați loviturile de bază?',
      'imageBase64': null,
      'timestamp': FieldValue.serverTimestamp(),
      'likesCount': 2,
      'commentsCount': 1,
      'likedBy': ['fake_user_1', 'fake_user_2'],
    });

    await post1Ref.collection('comments').add({
      'authorUid': 'fake_user_1',
      'authorUsername': 'Alex Jucător',
      'authorAvatarUrl': '',
      'text': 'În fiecare marți!',
      'timestamp': FieldValue.serverTimestamp(),
    });

    await firestore.collection('posts').add({
      'authorUid': 'fake_user_2',
      'authorUsername': 'Maria Popa',
      'authorAvatarUrl': '',
      'content': 'Caut partener de joc pentru mâine seară în sectorul 3!',
      'imageBase64': null,
      'timestamp': FieldValue.serverTimestamp(),
      'likesCount': 0,
      'commentsCount': 0,
      'likedBy': [],
    });

    // 3. Create fake Venue
    final venueRef = firestore.collection('venues').doc('fake_venue_1');
    await venueRef.set({
      'venueName': 'Super PingPong Club',
      'address': 'Bulevardul Unirii 10',
      'city': 'București',
      'pricePerHour': 40.0,
      'role': 'venue',
      'tablesCount': 4,
      'sports': ['Ping Pong', 'Box'],
      'posType': 'Niciunul',
    });

    // 4. Create fake Match/Reservation
    await firestore.collection('matches').add({
      'venueId': 'fake_venue_1',
      'venueName': 'Super PingPong Club',
      'creatorId': 'fake_user_1',
      'creatorName': 'Alex Jucător',
      'sport': 'Ping Pong',
      'tableNumber': 1,
      'date': '2026-07-01',
      'time': '18:00 - 19:00',
      'status': 'open',
      'playersJoined': 1,
      'maxPlayers': 2,
      'price': 40.0,
      'paymentStatus': 'pending',
      'checkedIn': false,
    });
  }

  static Future<void> seedMassiveData(int count) async {
    final firestore = FirebaseFirestore.instance;
    final fakerObj = Faker();
    final random = Random();

    // 1. Venues (Săli)
    final List<String> venueIds = [];
    final cities = ['București', 'Cluj-Napoca', 'Timișoara', 'Iași', 'Constanța', 'Brașov'];
    
    for (int i = 0; i < 10; i++) {
      final docRef = firestore.collection('venues').doc();
      venueIds.add(docRef.id);
      await docRef.set({
        'venueName': '${fakerObj.company.name()} Ping Pong Club',
        'address': fakerObj.address.streetAddress(),
        'city': cities[random.nextInt(cities.length)],
        'pricePerHour': (random.nextInt(40) + 20).toDouble(), // 20 - 60 RON
        'role': 'venue',
        'tablesCount': random.nextInt(10) + 2,
        'sports': ['Ping Pong'],
        'posType': random.nextBool() ? 'Acceptă card' : 'Doar cash',
      });
    }

    // 2. Users (Jucători + Antrenori)
    final List<String> userIds = [];
    
    for (int i = 0; i < count; i++) {
      final docRef = firestore.collection('users').doc();
      userIds.add(docRef.id);
      
      final isTrainer = random.nextDouble() > 0.8; // 20% antrenori
      
      await docRef.set({
        'username': fakerObj.person.name(),
        'email': fakerObj.internet.email(),
        'role': 'player',
        'rating': random.nextInt(1500) + 500, // 500 - 2000
        'isTrainer': isTrainer,
        'trainerPrice': isTrainer ? (random.nextInt(100) + 50).toDouble() : null,
        'trustScore': random.nextInt(20) + 80, // 80 - 100
        'followers': [],
        'following': [],
        'followRequests': [],
        'isPrivate': random.nextBool(),
        'bio': fakerObj.lorem.sentence(),
        'avatarUrl': '', // No avatar
      });
    }

    // Assign followers to each other randomly
    for (String uid in userIds) {
      final followersCount = random.nextInt(5);
      final followers = <String>[];
      for (int i = 0; i < followersCount; i++) {
        final fId = userIds[random.nextInt(userIds.length)];
        if (fId != uid && !followers.contains(fId)) {
          followers.add(fId);
        }
      }
      if (followers.isNotEmpty) {
        await firestore.collection('users').doc(uid).update({
          'followers': followers,
        });
        // We skip symmetric following for simplicity in seeding, 
        // but normally we'd update following of followers.
      }
    }

    // 3. Posts
    for (int i = 0; i < (count / 2).floor(); i++) {
      final authorId = userIds[random.nextInt(userIds.length)];
      final userSnap = await firestore.collection('users').doc(authorId).get();
      final userData = userSnap.data() as Map<String, dynamic>?;
      
      if (userData != null) {
        await firestore.collection('posts').add({
          'authorUid': authorId,
          'authorUsername': userData['username'],
          'authorAvatarUrl': '',
          'content': fakerObj.lorem.sentences(2).join(' '),
          'imageBase64': null,
          'timestamp': FieldValue.serverTimestamp(),
          'likesCount': random.nextInt(50),
          'commentsCount': 0,
          'likedBy': [],
          'visibility': 'public',
        });
      }
    }
  }
}
