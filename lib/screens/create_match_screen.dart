import 'package:flutter/material.dart';
import 'create_match_tab.dart';
import '../widgets/player_drawer.dart';

class CreateMatchScreen extends StatelessWidget {
  final String? preselectedCity;
  final String? preselectedVenueId;

  const CreateMatchScreen({
    super.key,
    this.preselectedCity,
    this.preselectedVenueId,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF131A2A),
        elevation: 0,
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF00E5FF)),
                onPressed: () => Navigator.pop(context),
              )
            : Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu, color: Color(0xFF00E5FF)),
                  onPressed: () {
                    Scaffold.of(context).openDrawer();
                  },
                ),
              ),
        title: const Text(
          'Creează un Meci',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      drawer: canPop ? null : const PlayerDrawer(activePage: 'create_match'),
      body: CreateMatchTab(
        preselectedCity: preselectedCity,
        preselectedVenueId: preselectedVenueId,
      ),
    );
  }
}
