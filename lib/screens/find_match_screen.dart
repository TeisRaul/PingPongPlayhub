import 'package:flutter/material.dart';
import 'find_match_tab.dart';
import '../widgets/player_drawer.dart';
import '../theme/app_theme.dart';

class FindMatchScreen extends StatelessWidget {
  const FindMatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(Icons.menu, color: AppColors.accent),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        title: Text(
          'Descoperă Meciuri',
          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      drawer: const PlayerDrawer(activePage: 'find_match'),
      body: const FindMatchTab(),
    );
  }
}
