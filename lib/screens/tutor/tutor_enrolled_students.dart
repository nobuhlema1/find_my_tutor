import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TutorEnrolledStudents extends StatefulWidget {
  const TutorEnrolledStudents({super.key});

  @override
  State<TutorEnrolledStudents> createState() => _TutorEnrolledStudentsState();
}

class _TutorEnrolledStudentsState extends State<TutorEnrolledStudents> {
  static const teal = Color(0xFF008080);

  Future<void> removeStudent(String applicationId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Student?'),
        content: const Text(
          'This student will no longer be enrolled with you. '
          'They can apply again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep Student'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

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
            data['status'] != 'accepted') {
          throw StateError('Student is no longer enrolled');
        }

        transaction.update(ref, {
          'status': 'cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student removed from enrolled students')),
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
                ? 'You do not have permission to remove this student'
                : 'Unable to remove student',
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
          return const Center(child: Text('Unable to load enrolled students'));
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: teal));
        }

        final enrolled = snapshot.data!.docs
            .where((doc) => doc.data()['status'] == 'accepted')
            .toList();

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Enrolled Students',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: teal,
              ),
            ),
            const SizedBox(height: 8),
            const Text('Students whose applications you have accepted.'),
            const SizedBox(height: 24),

            if (enrolled.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('No enrolled students yet'),
                ),
              ),

            ...enrolled.map((doc) {
              final data = doc.data();

              final name = data['studentName']?.toString() ?? 'Student';

              final grade = data['studentGrade']?.toString() ?? 'Not available';

              final rawSubjects = data['subjectsNeeded'];

              final subjects = rawSubjects is List
                  ? rawSubjects.whereType<String>().join(', ')
                  : '';

              final displaySubjects = subjects.trim().isEmpty
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
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline,
                            color: teal,
                            size: 30,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      Row(
                        children: [
                          const Icon(
                            Icons.school_outlined,
                            color: teal,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Grade: $grade')),
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
                        'Status: Enrolled',
                        style: TextStyle(
                          color: teal,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 12),

                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: () => removeStudent(doc.id),
                          icon: const Icon(Icons.person_remove_outlined),
                          label: const Text('Remove Student'),
                        ),
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
