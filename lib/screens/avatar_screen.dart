import 'package:flutter/material.dart';

class AvatarScreen extends StatefulWidget {
  const AvatarScreen({super.key});

  @override
  State<AvatarScreen> createState() => _AvatarScreenState();
}

class _AvatarScreenState extends State<AvatarScreen> {
  // Lista de avatare 3D mock (pot fi imagini dintr-un bucket Firebase/assets mai tarziu)
  // Momentan folosim Icon-uri de flutter sau un UI placeholders.
  int? _selectedAvatarIndex;

  final List<String> _avatarNames = [
    'Pro Player',
    'Speedster',
    'Smash King',
    'Spin Master',
    'Defender',
    'Rookie',
  ];

  final List<String> _avatarPaths = [
    'assets/images/avatars/pro_player.png',
    'assets/images/avatars/speedster.png',
    'assets/images/avatars/smash_king.png',
    'assets/images/avatars/spin_master.png',
    'assets/images/avatars/defender.png',
    'assets/images/avatars/rookie.png',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              const Text(
                'Alege-ți Avatarul 3D',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Selectează personajul care te reprezintă cel mai bine pe teren.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 40),
              
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: 6, // Numărul de avatare 3D mock
                  itemBuilder: (context, index) {
                    final isSelected = _selectedAvatarIndex == index;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedAvatarIndex = index;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          color: const Color(0xFF131A2A),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF00E5FF) : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF00E5FF).withOpacity(0.4),
                                    blurRadius: 15,
                                    spreadRadius: 2,
                                  )
                                ]
                              : [],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Imaginea Avatarului 3D
                            CircleAvatar(
                              radius: 45,
                              backgroundColor: const Color(0xFF1E293B),
                              backgroundImage: AssetImage(_avatarPaths[index]),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _avatarNames[index],
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.white : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _selectedAvatarIndex != null
                    ? () {
                        // TODO: Save selected avatar to Firebase user profile
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Cont configurat cu succes!')),
                        );
                      }
                    : null, // Disabled if no avatar selected
                child: const Text('FINALIZEAZĂ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
