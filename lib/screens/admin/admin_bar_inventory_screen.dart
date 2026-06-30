import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminBarInventoryScreen extends StatefulWidget {
  final String venueId;

  const AdminBarInventoryScreen({super.key, required this.venueId});

  @override
  State<AdminBarInventoryScreen> createState() => _AdminBarInventoryScreenState();
}

class _AdminBarInventoryScreenState extends State<AdminBarInventoryScreen> {
  final List<Map<String, dynamic>> _templates = [
    {'name': 'Coca-Cola 0.5L', 'category': 'Suc', 'price': 10.0},
    {'name': 'Pepsi 0.5L', 'category': 'Suc', 'price': 10.0},
    {'name': 'Apă Plată Dorna 0.5L', 'category': 'Apă', 'price': 8.0},
    {'name': 'Apă Minerală Borsec 0.5L', 'category': 'Apă', 'price': 8.0},
    {'name': 'Cafea Espresso', 'category': 'Cafea', 'price': 12.0},
    {'name': 'Baton Proteic', 'category': 'Snack', 'price': 15.0},
    {'name': 'Timișoreana 0.5L', 'category': 'Bere', 'price': 12.0},
    {'name': 'Skol 0.5L', 'category': 'Bere', 'price': 11.0},
    {'name': 'Ursus Premium 0.5L', 'category': 'Bere', 'price': 14.0},
    {'name': 'Heineken 0.5L', 'category': 'Bere', 'price': 16.0},
    {'name': 'Ciuc 0.5L', 'category': 'Bere', 'price': 13.0},
  ];

  Future<void> _addTemplateItem(Map<String, dynamic> template) async {
    await FirebaseFirestore.instance
        .collection('venues')
        .doc(widget.venueId)
        .collection('inventory')
        .add({
      'name': template['name'],
      'category': template['category'],
      'price': template['price'],
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _toggleItemStatus(String id, bool currentStatus) async {
    await FirebaseFirestore.instance
        .collection('venues')
        .doc(widget.venueId)
        .collection('inventory')
        .doc(id)
        .update({'isActive': !currentStatus});
  }

  Future<void> _deleteItem(String id) async {
    await FirebaseFirestore.instance
        .collection('venues')
        .doc(widget.venueId)
        .collection('inventory')
        .doc(id)
        .delete();
  }

  void _showAddCustomItemDialog() {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    String selectedCategory = 'Suc';
    final categories = ['Suc', 'Apă', 'Cafea', 'Bere', 'Snack', 'Altul'];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF131A2A),
              title: const Text('Adaugă Produs Nou', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Nume Produs',
                      labelStyle: TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    dropdownColor: const Color(0xFF131A2A),
                    style: const TextStyle(color: Colors.white),
                    items: categories.map((cat) {
                      return DropdownMenuItem(value: cat, child: Text(cat));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setStateDialog(() => selectedCategory = val);
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'Categorie',
                      labelStyle: TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Preț (RON)',
                      labelStyle: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Anulează', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final price = double.tryParse(priceController.text.trim());
                    if (name.isNotEmpty && price != null) {
                      await FirebaseFirestore.instance
                          .collection('venues')
                          .doc(widget.venueId)
                          .collection('inventory')
                          .add({
                        'name': name,
                        'category': selectedCategory,
                        'price': price,
                        'isActive': true,
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Adaugă'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  void _showTemplatesDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131A2A),
      builder: (context) {
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _templates.length,
          itemBuilder: (context, index) {
            final t = _templates[index];
            return ListTile(
              title: Text(t['name'], style: const TextStyle(color: Colors.white)),
              subtitle: Text('${t['category']} - ${t['price']} RON', style: const TextStyle(color: Colors.grey)),
              trailing: IconButton(
                icon: const Icon(Icons.add_circle, color: Color(0xFF00E5FF)),
                onPressed: () {
                  _addTemplateItem(t);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${t['name']} adăugat!'), duration: const Duration(seconds: 1)),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        title: const Text('Inventar Bar / Snacks', style: TextStyle(color: Colors.white, fontSize: 18)),
        backgroundColor: const Color(0xFF131A2A),
        iconTheme: const IconThemeData(color: Color(0xFF00E5FF)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _showTemplatesDialog,
                    icon: const Icon(Icons.list_alt),
                    label: const Text('Din Șabloane'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF131A2A),
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.grey),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _showAddCustomItemDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Custom'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.grey),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('venues')
                  .doc(widget.venueId)
                  .collection('inventory')
                  .orderBy('category')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('Niciun produs în inventar.\nAdaugă produse pentru a fi disponibile jucătorilor.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey)),
                  );
                }

                final items = snapshot.data!.docs;

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final doc = items[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final name = data['name'] ?? '';
                    final category = data['category'] ?? '';
                    final price = data['price'] ?? 0.0;
                    final isActive = data['isActive'] ?? true;

                    return Card(
                      color: const Color(0xFF131A2A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: Icon(
                          category == 'Apă' ? Icons.water_drop :
                          category == 'Cafea' ? Icons.local_cafe :
                          category == 'Snack' ? Icons.fastfood : Icons.local_drink,
                          color: isActive ? const Color(0xFF00E5FF) : Colors.grey,
                        ),
                        title: Text(name, style: TextStyle(color: isActive ? Colors.white : Colors.grey, decoration: isActive ? null : TextDecoration.lineThrough)),
                        subtitle: Text('$category | $price RON', style: const TextStyle(color: Colors.grey)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: isActive,
                              activeColor: const Color(0xFF00E5FF),
                              onChanged: (val) => _toggleItemStatus(doc.id, isActive),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.redAccent),
                              onPressed: () => _deleteItem(doc.id),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
