import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TutorGrades extends StatelessWidget {
  const TutorGrades({super.key});

  static const teal = Color(0xFF008080);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('grade_levels')
          .orderBy('order')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Unable to load grade levels'));
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: teal));
        }

        final grades = snapshot.data!.docs
            .map((doc) => doc.data()['name']?.toString() ?? '')
            .where(
              (name) => const [
                'Grade 8',
                'Grade 9',
                'Grade 10',
                'Grade 11',
                'Grade 12',
              ].contains(name),
            )
            .toList();

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Grade Levels',
              style: TextStyle(
                color: teal,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text('Available South African high school grade levels.'),
            const SizedBox(height: 20),
            if (grades.isEmpty) const Text('No grade levels available yet'),
            ...grades.map(
              (grade) => Card(
                color: Colors.white,
                child: ListTile(
                  leading: const Icon(Icons.school_outlined, color: teal),
                  title: Text(grade),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
