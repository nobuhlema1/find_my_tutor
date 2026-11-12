import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TutorMyStudents extends StatefulWidget {
  const TutorMyStudents({super.key});

  @override
  State<TutorMyStudents> createState() => _TutorMyStudentsState();
}

class _TutorMyStudentsState extends State<TutorMyStudents> {
  static const teal = Color(0xFF008080);

  Future<void> updateApplication(String applicationId, String newStatus) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final ref = FirebaseFirestore.instance
          .collection('applications')
          .doc(applicationId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        final data = snapshot.data();

        if (!snapshot.exists ||
            data == null ||
            data['tutorId'] != user.uid ||
            data['status'] != 'pending' ||
            !['accepted', 'declined'].contains(newStatus)) {
          throw StateError('Application is no longer pending');
        }

        transaction.update(ref, {
          'status': newStatus,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == 'accepted'
                ? 'Student application accepted'
                : 'Student application declined',
          ),
        ),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'permission-denied'
                ? 'You do not have permission to update this application'
                : 'Unable to update application',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Something went wrong')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(child: Text('Please log in first'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('applications')
          .where('tutorId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Unable to load student applications'),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: teal));
        }

        final pending = snapshot.data!.docs
            .where((doc) => doc.data()['status'] == 'pending')
            .toList();

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Student Applications',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: teal,
              ),
            ),
            const SizedBox(height: 8),
            const Text('Review new applications from students.'),
            const SizedBox(height: 24),

            if (pending.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('No pending applications'),
                ),
              ),

            ...pending.map((doc) {
              final data = doc.data();
              final name = data['studentName']?.toString() ?? 'Student';

              final grade = data['studentGrade']?.toString() ?? 'Not available';

              final rawSubjects = data['subjectsNeeded'];

              final subjects = rawSubjects is List
                  ? rawSubjects.whereType<String>().join(', ')
                  : 'Not available';

              final displaySubjects = subjects.isEmpty
                  ? 'Not available'
                  : subjects;

              return Card(
                color: Colors.white,
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.person_outline, color: teal, size: 32),
                      const SizedBox(height: 8),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          const Icon(
                            Icons.school_outlined,
                            color: teal,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(grade)),
                        ],
                      ),

                      const SizedBox(height: 10),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.menu_book_outlined,
                            color: teal,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Subjects: $displaySubjects')),
                        ],
                      ),

                      const SizedBox(height: 12),
                      const Text(
                        'Status: Pending',
                        style: TextStyle(
                          color: teal,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),

                      Wrap(
                        spacing: 8,
                        children: [
                          ElevatedButton(
                            onPressed: () =>
                                updateApplication(doc.id, 'accepted'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: teal,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Accept'),
                          ),
                          OutlinedButton(
                            onPressed: () =>
                                updateApplication(doc.id, 'declined'),
                            child: const Text('Decline'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
