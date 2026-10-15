import 'package:flutter/material.dart';
import 'create_match_tab.dart';
import '../widgets/player_drawer.dart';
import '../theme/app_theme.dart';

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
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        leading: canPop
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: AppColors.accent),
                onPressed: () => Navigator.pop(context),
              )
            : Builder(
                builder: (context) => IconButton(
                  icon: Icon(Icons.menu, color: AppColors.accent),
                  onPressed: () {
                    Scaffold.of(context).openDrawer();
                  },
                ),
              ),
        title: Text(
          'Creează un Meci',
          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold),
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
