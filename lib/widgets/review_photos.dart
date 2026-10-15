import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';

/// Numărul maxim de poze la o recenzie.
const int kMaxReviewPhotos = 3;

// Pozele se salvează comprimate (base64) direct în documentul recenziei, ca și avatarele.
// O poză ≤ ~250 KB după comprimare; 3 poze rămân mult sub limita de 1 MB a unui document Firestore.
const int _maxEncodedBytes = 330 * 1024;

Uint8List? _decode(dynamic value) {
  try {
    var s = value.toString();
    final comma = s.indexOf(',');
    if (s.startsWith('data:') && comma != -1) s = s.substring(comma + 1);
    return base64Decode(s);
  } catch (_) {
    return null;
  }
}

/// Alegerea pozelor pentru o recenzie (maxim [kMaxReviewPhotos]). Întoarce lista prin [onChanged].
class ReviewPhotoPicker extends StatefulWidget {
  final List<String> photos;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;

  const ReviewPhotoPicker({super.key, required this.photos, required this.onChanged, this.enabled = true});

  @override
  State<ReviewPhotoPicker> createState() => _ReviewPhotoPickerState();
}

class _ReviewPhotoPickerState extends State<ReviewPhotoPicker> {
  final ImagePicker _picker = ImagePicker();
  bool _busy = false;
  String? _error;

  Future<void> _add() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 900,
        maxHeight: 900,
        imageQuality: 60,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final encoded = base64Encode(bytes);
      if (encoded.length > _maxEncodedBytes) {
        if (mounted) setState(() => _error = tr('rev.photo_big'));
        return;
      }
      widget.onChanged([...widget.photos, encoded]);
    } catch (_) {
      if (mounted) setState(() => _error = tr('rev.photo_fail'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = widget.enabled && !_busy && widget.photos.length < kMaxReviewPhotos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (int i = 0; i < widget.photos.length; i++)
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Builder(builder: (_) {
                      final bytes = _decode(widget.photos[i]);
                      return bytes == null
                          ? Container(width: 64, height: 64, color: AppColors.card3)
                          : Image.memory(bytes, width: 64, height: 64, fit: BoxFit.cover);
                    }),
                  ),
                  if (widget.enabled)
                    Positioned(
                      top: -6,
                      right: -6,
                      child: InkWell(
                        onTap: () => widget.onChanged([...widget.photos]..removeAt(i)),
                        child: Container(
                          decoration: BoxDecoration(color: AppColors.bad, shape: BoxShape.circle),
                          padding: const EdgeInsets.all(2),
                          child: const Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            if (widget.photos.length < kMaxReviewPhotos)
              InkWell(
                onTap: canAdd ? _add : null,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.6)),
                  ),
                  child: _busy
                      ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                      : Icon(Icons.add_a_photo_outlined, color: AppColors.accent),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(tr('rev.photos_hint', {'n': '$kMaxReviewPhotos'}), style: TextStyle(color: AppColors.text54, fontSize: 11)),
        if (_error != null) Text(_error!, style: TextStyle(color: AppColors.bad, fontSize: 12)),
      ],
    );
  }
}

/// Pozele unei recenzii, ca miniaturi; la atingere se deschid mari.
class ReviewPhotoStrip extends StatelessWidget {
  final List<dynamic> photos;
  const ReviewPhotoStrip({super.key, required this.photos});

  void _open(BuildContext context, Uint8List bytes) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain)),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final decoded = photos.map(_decode).whereType<Uint8List>().toList();
    if (decoded.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final b in decoded)
            GestureDetector(
              onTap: () => _open(context, b),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(b, width: 72, height: 72, fit: BoxFit.cover),
              ),
            ),
        ],
      ),
    );
  }
}
