import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final TextEditingController _contentController = TextEditingController();
  String? _imageBase64;
  bool _isPosting = false;
  String _visibility = 'public';

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);

    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _imageBase64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      });
    }
  }

  Future<void> _publishPost() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final content = _contentController.text.trim();
    if (content.isEmpty && _imageBase64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Postarea nu poate fi goală!'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isPosting = true);

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};

      await FirebaseFirestore.instance.collection('posts').add({
        'authorUid': user.uid,
        'authorUsername': userData['username'] ?? 'Utilizator',
        'authorAvatarUrl': userData['avatarUrl'] ?? '',
        'city': userData['city'] ?? 'Necunoscut',
        'content': content,
        'imageBase64': _imageBase64,
        'visibility': _visibility,
        'allowedCloseFriends': _visibility == 'close_friends' ? (userData['closeFriends'] ?? []) : [],
        'timestamp': FieldValue.serverTimestamp(),
        'likesCount': 0,
        'commentsCount': 0,
        'likedBy': [],
      });

      if (mounted) {
        Navigator.pop(context, true); // return true to refresh feed
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        title: Text('Creează o postare', style: TextStyle(color: AppColors.text)),
        iconTheme: IconThemeData(color: AppColors.text),
        actions: [
          _isPosting
              ? Center(child: Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))))
              : TextButton(
                  onPressed: _publishPost,
                  child: Text('POSTEAZĂ', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
                ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.card2,
                  radius: 20,
                  child: Icon(Icons.person, color: AppColors.text),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _contentController,
                    style: TextStyle(color: AppColors.text),
                    maxLines: null,
                    minLines: 4,
                    decoration: InputDecoration(
                      hintText: 'La ce te gândești, campionule?',
                      hintStyle: TextStyle(color: AppColors.muted),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Cine poate vedea postarea?', style: TextStyle(color: AppColors.text70, fontSize: 14)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildVisibilityChip('Public', 'public', Icons.public),
                  const SizedBox(width: 8),
                  _buildVisibilityChip('Prieteni', 'friends', Icons.group),
                  const SizedBox(width: 8),
                  _buildVisibilityChip('Close Friends', 'close_friends', Icons.star),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_imageBase64 != null) ...[
              Stack(
                alignment: Alignment.topRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      base64Decode(_imageBase64!.split(',').last),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 250,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.cancel, color: AppColors.text, size: 30),
                    onPressed: () {
                      setState(() => _imageBase64 = null);
                    },
                  )
                ],
              ),
              const SizedBox(height: 16),
            ],
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: Icon(Icons.image, color: AppColors.text),
              label: Text('Adaugă o fotografie', style: TextStyle(color: AppColors.text)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.muted),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisibilityChip(String label, String value, IconData icon) {
    final isSelected = _visibility == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _visibility = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent.withValues(alpha: 0.2) : AppColors.card2,
          border: Border.all(color: isSelected ? AppColors.accent : Colors.transparent),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? AppColors.accent : AppColors.muted),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: isSelected ? AppColors.accent : AppColors.muted, fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}
