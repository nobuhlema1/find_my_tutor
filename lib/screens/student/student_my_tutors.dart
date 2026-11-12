import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StudentMyTutors extends StatefulWidget {
  const StudentMyTutors({super.key});

  @override
  State<StudentMyTutors> createState() => _StudentMyTutorsState();
}

class _StudentMyTutorsState extends State<StudentMyTutors>
    with SingleTickerProviderStateMixin {
  static const teal = Color(0xFF008080);
  static const lightTeal = Color(0xFFE0F2F1);

  late TabController _tabController;
  final Set<String> applyingToTutors = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String formatDateTime(dynamic value) {
    if (value is! Timestamp) return 'Not available';
    final date = value.toDate();
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} at $hour:$minute';
  }

  Widget buildTutorReviews(String tutorId, {bool showComments = false}) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('reviews')
          .where('tutorId', isEqualTo: tutorId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text(
            'Reviews unavailable',
            style: TextStyle(fontSize: 11),
          );
        }
        if (!snapshot.hasData) {
          return const Text(
            'Loading reviews...',
            style: TextStyle(fontSize: 11),
          );
        }

        final reviews = snapshot.data!.docs.where((doc) {
          final rating = doc.data()['rating'];
          return rating is num && rating >= 1 && rating <= 5;
        }).toList();

        if (reviews.isEmpty) {
          return const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star_outline, color: Colors.amber, size: 16),
              SizedBox(width: 4),
              Flexible(
                child: Text('No ratings yet', style: TextStyle(fontSize: 11)),
              ),
            ],
          );
        }

        final total = reviews.fold<double>(
          0,
          (runningTotal, doc) =>
              runningTotal + (doc.data()['rating'] as num).toDouble(),
        );
        final average = total / reviews.length;
        final summary =
            '${average.toStringAsFixed(1)}/5 (${reviews.length} reviews)';

        if (!showComments) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star, color: Colors.amber, size: 16),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  summary,
                  style: const TextStyle(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 19),
                const SizedBox(width: 6),
                Flexible(child: Text(summary)),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Student Reviews',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            ...reviews.map((doc) {
              final review = doc.data();
              final student = review['studentName']?.toString() ?? 'Student';
              final studentGrade =
                  review['studentGrade']?.toString() ?? 'Not available';
              final stars = (review['rating'] as num).toInt();
              final comment = review['comment']?.toString() ?? '';

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$student · $stars/5 ★',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(studentGrade),
                    const SizedBox(height: 6),
                    Text('Reviewed on: ${formatDateTime(review['createdAt'])}'),
                    const SizedBox(height: 8),
                    Text(
                      'Subject: ${review['subject']?.toString() ?? 'Not available'}',
                    ),
                    Text(
                      'Topic: ${review['topic']?.toString() ?? 'Not available'}',
                    ),
                    Text('Session: ${formatDateTime(review['sessionDate'])}'),
                    const SizedBox(height: 8),
                    if (comment.isNotEmpty) Text('Review: $comment'),
                    const Divider(),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Future<void> applyForTutor(String tutorId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showMessage('Please log in first');
      return;
    }
    if (applyingToTutors.contains(tutorId)) return;
    setState(() => applyingToTutors.add(tutorId));

    try {
      final applicationId = '${user.uid}_$tutorId';
      final applicationReference = FirebaseFirestore.instance
          .collection('applications')
          .doc(applicationId);

      final studentProfile = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final verifiedName = studentProfile.data()?['fullName']?.toString();
      final studentGrade =
          studentProfile.data()?['gradeLevel']?.toString() ?? '';
      final rawSubjects = studentProfile.data()?['subjectsNeeded'];
      final subjectsNeeded = rawSubjects is List
          ? rawSubjects.whereType<String>().toList()
          : <String>[];

      if (verifiedName == null ||
          verifiedName.trim().isEmpty ||
          studentGrade.isEmpty ||
          subjectsNeeded.isEmpty) {
        if (mounted) {
          showMessage(
            'Complete your profile (name, grade, subjects) before applying',
          );
        }
        return;
      }

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final existing = await transaction.get(applicationReference);

        if (!existing.exists) {
          transaction.set(applicationReference, {
            'studentId': user.uid,
            'tutorId': tutorId,
            'studentName': verifiedName,
            'studentGrade': studentGrade,
            'subjectsNeeded': subjectsNeeded,
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
          });
        } else if (existing.data()?['status'] == 'cancelled' ||
            existing.data()?['status'] == 'declined') {
          transaction.update(applicationReference, {
            'status': 'pending',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          throw StateError('You already have an application with this tutor.');
        }
      });

      if (!mounted) return;
      showMessage('Application submitted successfully!');
    } on FirebaseException catch (e) {
      if (!mounted) return;
      showMessage(
        e.code == 'permission-denied'
            ? 'Application denied. Check Firestore rules '
                  'or whether you have already applied.'
            : 'Could not submit application',
      );
    } on StateError catch (e) {
      if (mounted) showMessage(e.message);
    } finally {
      if (mounted) setState(() => applyingToTutors.remove(tutorId));
    }
  }

  void showTutorDetails(
    String tutorId,
    Map<String, dynamic> data,
    String? applicationStatus,
  ) {
    final name = data['fullName']?.toString() ?? 'Tutor';
    final qualification = data['qualification']?.toString() ?? 'Not provided';
    final tutorSubjects = List<String>.from(data['subjectsOffered'] ?? []);
    final tutorGrades = List<String>.from(data['gradesOffered'] ?? []);

    final canApply =
        applicationStatus == null ||
        applicationStatus == 'cancelled' ||
        applicationStatus == 'declined';

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Qualifications',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(qualification),
              const SizedBox(height: 16),
              const Text(
                'Subjects Offered',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(tutorSubjects.join(', ')),
              const SizedBox(height: 16),
              const Text(
                'Grades Offered',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(tutorGrades.join(', ')),
              const SizedBox(height: 16),
              buildTutorReviews(tutorId, showComments: true),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: canApply
                ? () {
                    Navigator.pop(dialogContext);
                    applyForTutor(tutorId);
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: teal,
              foregroundColor: Colors.white,
            ),
            child: Text(
              applicationStatus == 'pending'
                  ? 'Pending'
                  : applicationStatus == 'accepted'
                  ? 'Enrolled'
                  : applicationStatus == 'declined'
                  ? 'Apply Again'
                  : applicationStatus == 'cancelled'
                  ? 'Apply Again'
                  : 'Apply',
            ),
          ),
        ],
      ),
    );
  }

  Widget tutorCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String? status,
  ) {
    final data = doc.data();
    final name = data['fullName']?.toString() ?? 'Tutor';
    final tutorSubjects = List<String>.from(data['subjectsOffered'] ?? []);
    final tutorGrades = List<String>.from(data['gradesOffered'] ?? []);
    final busy = applyingToTutors.contains(doc.id);

    return Card(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            const CircleAvatar(
              backgroundColor: lightTeal,
              child: Icon(Icons.person, color: teal),
            ),
            const SizedBox(height: 7),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              tutorSubjects.join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 5),
            Text(
              tutorGrades.join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
            const Spacer(),
            buildTutorReviews(doc.id),
            const SizedBox(height: 7),
            SizedBox(
              width: double.infinity,
              height: 34,
              child: ElevatedButton(
                onPressed: busy
                    ? null
                    : () => showTutorDetails(doc.id, data, status),
                style: ElevatedButton.styleFrom(
                  backgroundColor: teal,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                ),
                child: Text(
                  status == null
                      ? 'View / Apply'
                      : (status == 'cancelled' || status == 'declined')
                      ? 'Apply Again'
                      : 'View • $status',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget tutorGrid(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Map<String, String> statuses,
  ) {
    if (docs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('No tutors to show.', textAlign: TextAlign.center),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 650 ? 3 : 2;
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 235,
          ),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            return tutorCard(doc, statuses[doc.id]);
          },
        );
      },
    );
  }

  Widget buildTabs() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Please log in first'));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, studentSnapshot) {
        if (studentSnapshot.hasError) {
          return const Center(child: Text('Unable to load your profile'));
        }
        if (!studentSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: teal));
        }
        final studentData = studentSnapshot.data!.data();
        if (studentData == null) {
          return const Center(child: Text('Student profile not found'));
        }

        final neededSubjects = (studentData['subjectsNeeded'] is List)
            ? (studentData['subjectsNeeded'] as List)
                  .map((s) => s.toString().trim().toLowerCase())
                  .where((s) => s.isNotEmpty)
                  .toSet()
            : <String>{};
        final studentGrade =
            studentData['gradeLevel']?.toString().trim().toLowerCase() ?? '';

        if (neededSubjects.isEmpty || studentGrade.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Complete your Student Profile with your grade and subjects '
                'to see matching tutors.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('tutor_profiles')
              .snapshots(),
          builder: (context, tutorSnapshot) {
            if (tutorSnapshot.hasError) {
              return const Center(child: Text('Unable to load tutors'));
            }
            if (!tutorSnapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: teal),
              );
            }

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('applications')
                  .where('studentId', isEqualTo: user.uid)
                  .snapshots(),
              builder: (context, applicationSnapshot) {
                if (applicationSnapshot.hasError) {
                  return const Center(
                    child: Text('Unable to load applications'),
                  );
                }
                if (!applicationSnapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: teal),
                  );
                }

                final statuses = <String, String>{};
                for (final doc in applicationSnapshot.data!.docs) {
                  final tid = doc.data()['tutorId']?.toString();
                  final st = doc.data()['status']?.toString();
                  if (tid != null && st != null) statuses[tid] = st;
                }

                final allTutors = tutorSnapshot.data!.docs.where((doc) {
                  final data = doc.data();
                  final subjects = (data['subjectsOffered'] is List)
                      ? (data['subjectsOffered'] as List)
                            .map((s) => s.toString().trim().toLowerCase())
                            .toSet()
                      : <String>{};
                  final grades = (data['gradesOffered'] is List)
                      ? (data['gradesOffered'] as List)
                            .map((g) => g.toString().trim().toLowerCase())
                            .toSet()
                      : <String>{};

                  return neededSubjects.intersection(subjects).isNotEmpty &&
                      grades.contains(studentGrade);
                }).toList();

                final findTutors = allTutors.where((d) {
                  final status = statuses[d.id];
                  return status == null ||
                      status == 'cancelled' ||
                      status == 'declined';
                }).toList();

                final myApplications = allTutors.where((d) {
                  final status = statuses[d.id];
                  return status == 'pending' || status == 'declined';
                }).toList();

                final enrolled = allTutors.where((d) {
                  return statuses[d.id] == 'accepted';
                }).toList();

                return Column(
                  children: [
                    Container(
                      color: Colors.white,
                      child: TabBar(
                        controller: _tabController,
                        labelColor: teal,
                        unselectedLabelColor: Colors.grey,
                        indicatorColor: teal,
                        tabs: const [
                          Tab(text: 'Find Tutors'),
                          Tab(text: 'Applications'),
                          Tab(text: 'Enrolled'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          tutorGrid(findTutors, statuses),
                          tutorGrid(myApplications, statuses),
                          tutorGrid(enrolled, statuses),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => buildTabs();
}
