import 'package:flutter/material.dart';
import 'create_match_tab.dart';
import 'find_match_tab.dart';

class FindMatchScreen extends StatelessWidget {
  const FindMatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF131A2A),
          elevation: 0,
          title: const Text('Meciuri'),
          centerTitle: true,
          bottom: const TabBar(
            indicatorColor: Color(0xFF00E5FF),
            labelColor: Color(0xFF00E5FF),
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: 'FIND A MATCH'),
              Tab(text: 'CREATE MATCH'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            FindMatchTab(),
            CreateMatchTab(),
          ],
        ),
      ),
    );
  }
}
