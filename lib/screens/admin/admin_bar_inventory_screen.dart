import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';

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
              backgroundColor: AppColors.card,
              title: Text('Adaugă Produs Nou', style: TextStyle(color: AppColors.text)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    style: TextStyle(color: AppColors.text),
                    decoration: InputDecoration(
                      labelText: 'Nume Produs',
                      labelStyle: TextStyle(color: AppColors.muted),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    dropdownColor: AppColors.card,
                    style: TextStyle(color: AppColors.text),
                    items: categories.map((cat) {
                      return DropdownMenuItem(value: cat, child: Text(cat));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setStateDialog(() => selectedCategory = val);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Categorie',
                      labelStyle: TextStyle(color: AppColors.muted),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: AppColors.text),
                    decoration: InputDecoration(
                      labelText: 'Preț (RON)',
                      labelStyle: TextStyle(color: AppColors.muted),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Anulează', style: TextStyle(color: AppColors.muted)),
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
                    backgroundColor: AppColors.accent,
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
      backgroundColor: AppColors.card,
      builder: (context) {
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _templates.length,
          itemBuilder: (context, index) {
            final t = _templates[index];
            return ListTile(
              title: Text(t['name'], style: TextStyle(color: AppColors.text)),
              subtitle: Text('${t['category']} - ${t['price']} RON', style: TextStyle(color: AppColors.muted)),
              trailing: IconButton(
                icon: Icon(Icons.add_circle, color: AppColors.accent),
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
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('Inventar Bar / Snacks', style: TextStyle(color: AppColors.text, fontSize: 18)),
        backgroundColor: AppColors.card,
        iconTheme: IconThemeData(color: AppColors.accent),
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
                      backgroundColor: AppColors.card,
                      foregroundColor: AppColors.text,
                      side: BorderSide(color: AppColors.muted),
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
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(color: AppColors.muted),
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
                  return Center(child: CircularProgressIndicator(color: AppColors.accent));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text('Niciun produs în inventar.\nAdaugă produse pentru a fi disponibile jucătorilor.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted)),
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
                      color: AppColors.card,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: Icon(
                          category == 'Apă' ? Icons.water_drop :
                          category == 'Cafea' ? Icons.local_cafe :
                          category == 'Snack' ? Icons.fastfood : Icons.local_drink,
                          color: isActive ? AppColors.accent : AppColors.muted,
                        ),
                        title: Text(name, style: TextStyle(color: isActive ? AppColors.text : AppColors.muted, decoration: isActive ? null : TextDecoration.lineThrough)),
                        subtitle: Text('$category | $price RON', style: TextStyle(color: AppColors.muted)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: isActive,
                              activeColor: AppColors.accent,
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
