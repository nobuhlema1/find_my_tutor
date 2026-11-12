import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TutorSubjects extends StatefulWidget {
  const TutorSubjects({super.key});

  @override
  State<TutorSubjects> createState() => _TutorSubjectsState();
}

class _TutorSubjectsState extends State<TutorSubjects> {
  static const teal = Color(0xFF008080);
  static String normalizeSubject(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static const Map<String, String> subjectAliases = {
    'math': 'mathematics',
    'maths': 'mathematics',
    'mathematics': 'mathematics',
    'physicalscience': 'physicalsciences',
    'physicalsciences': 'physicalsciences',
    'lifescience': 'lifesciences',
    'lifesciences': 'lifesciences',
    'businessstudy': 'businessstudies',
    'businessstudies': 'businessstudies',
    'computerapplicationtechnology': 'computerapplicationtechnology',
    'cat': 'computerapplicationtechnology',
  };

  static String subjectKey(String value) {
    final normalized = normalizeSubject(value);
    return subjectAliases[normalized] ?? normalized;
  }

  final subjectController = TextEditingController();

  bool isLoading = true;
  bool isAddingSubject = false;
  List<String> subjects = [];

  @override
  void initState() {
    super.initState();
    loadSubjects();
  }

  @override
  void dispose() {
    subjectController.dispose();
    super.dispose();
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> loadSubjects() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('subjects')
          .get();

      if (!mounted) return;

      setState(() {
        subjects =
            snapshot.docs
                .map((doc) => doc.data()['name']?.toString() ?? '')
                .where((name) => name.isNotEmpty)
                .toList()
              ..sort();

        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      showMessage('Unable to load subjects');
    }
  }

  Future<void> addSubject() async {
    if (isAddingSubject) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showMessage('Please log in first');
      return;
    }

    final name = subjectController.text.trim().replaceAll(RegExp(r'\s+'), ' ');

    if (name.length < 3 || name.length > 60) {
      showMessage('Subject name must be 3 to 60 characters');
      return;
    }

    if (subjects.any((subject) => subjectKey(subject) == subjectKey(name))) {
      showMessage(
        'This subject already exists under the same or another name.',
      );
      return;
    }

    final id = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    if (id.isEmpty) {
      showMessage('Please enter a valid subject name');
      return;
    }

    setState(() => isAddingSubject = true);

    try {
      final reference = FirebaseFirestore.instance
          .collection('subjects')
          .doc(id);

      // Create only if it does not already exist.
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final existing = await transaction.get(reference);

        if (existing.exists) {
          throw StateError('Subject already exists');
        }

        transaction.set(reference, {'name': name});
      });

      if (!mounted) return;

      subjectController.clear();
      showMessage('Subject added successfully!');
      await loadSubjects();
    } on FirebaseException catch (e) {
      if (!mounted) return;

      showMessage(
        e.code == 'permission-denied'
            ? 'You do not have permission to add subjects'
            : 'Unable to add subject',
      );
    } on StateError catch (_) {
      if (!mounted) return;
      showMessage('This subject already exists');
    } catch (e) {
      if (!mounted) return;
      showMessage('Unable to add subject');
    } finally {
      if (mounted) {
        setState(() => isAddingSubject = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: teal));
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Subjects',
          style: TextStyle(
            color: teal,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text('View subjects or add a missing high-school subject.'),
        const SizedBox(height: 20),
        TextField(
          controller: subjectController,
          decoration: InputDecoration(
            labelText: 'Subject Name',
            hintText: 'e.g. Agricultural Sciences',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: isAddingSubject ? null : addSubject,
          icon: const Icon(Icons.add),
          label: Text(isAddingSubject ? 'Adding...' : 'Add Subject'),
          style: ElevatedButton.styleFrom(
            backgroundColor: teal,
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Available Subjects',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: teal,
          ),
        ),
        const SizedBox(height: 12),
        if (subjects.isEmpty) const Text('No subjects available yet'),
        ...subjects.map(
          (subject) => Card(
            color: Colors.white,
            child: ListTile(
              leading: const Icon(Icons.menu_book, color: teal),
              title: Text(subject),
            ),
          ),
        ),
      ],
    );
  }
}
