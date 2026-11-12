import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'student_reviews.dart';

class StudentBookings extends StatefulWidget {
  const StudentBookings({super.key});

  @override
  State<StudentBookings> createState() => _StudentBookingsState();
}

class _StudentBookingsState extends State<StudentBookings> {
  int selectedSection = 0;
  static const teal = Color(0xFF008080);

  final db = FirebaseFirestore.instance;

  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> requestSession(
    QueryDocumentSnapshot<Map<String, dynamic>> applicationDoc,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final application = applicationDoc.data();
    final tutorId = application['tutorId']?.toString() ?? '';

    if (tutorId.isEmpty) {
      showMessage('Tutor information is missing');
      return;
    }

    try {
      final tutorDoc = await db.collection('tutor_profiles').doc(tutorId).get();

      if (!mounted) return;

      final rawSubjects = tutorDoc.data()?['subjectsOffered'];
      final subjects = rawSubjects is List
          ? rawSubjects.whereType<String>().toList()
          : <String>[];

      if (subjects.isEmpty) {
        showMessage('This tutor has no subjects available');
        return;
      }

      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (_) => _RequestSessionDialog(subjects: subjects),
      );

      if (result == null || !mounted) return;

      final selectedSubject = result['subject']!;
      final topic = result['topic']!;

      final latestApplication = await db
          .collection('applications')
          .doc(applicationDoc.id)
          .get();

      if (!mounted) return;

      if (latestApplication.data()?['studentId'] != user.uid ||
          latestApplication.data()?['tutorId'] != tutorId ||
          latestApplication.data()?['status'] != 'accepted') {
        showMessage('Tutor acceptance is required');
        return;
      }

      final studentDoc = await db.collection('users').doc(user.uid).get();

      final studentGrade = studentDoc.data()?['gradeLevel']?.toString() ?? '';

      if (studentGrade.isEmpty) {
        if (mounted) {
          showMessage('Please complete your Student Profile grade first');
        }
        return;
      }

      await db.collection('bookings').add({
        'studentId': user.uid,
        'studentName': studentDoc.data()?['fullName']?.toString() ?? 'Student',
        'studentGrade': studentGrade,
        'tutorId': tutorId,
        'tutorName': tutorDoc.data()?['fullName']?.toString() ?? 'Tutor',
        'subject': selectedSubject,
        'topic': topic,
        'status': 'pending',
        'sessionDate': null,
        'meetingLink': '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        showMessage('Booking request sent!');
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        showMessage(
          e.code == 'permission-denied'
              ? 'Booking blocked by Firestore rules'
              : 'Unable to request session',
        );
      }
    }
  }

  Future<void> cancelBooking(String bookingId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await db.runTransaction((transaction) async {
        final reference = db.collection('bookings').doc(bookingId);
        final snapshot = await transaction.get(reference);
        final data = snapshot.data();

        if (data == null || data['studentId'] != user.uid) {
          throw StateError('Booking not found');
        }

        if (data['status'] != 'pending' && data['status'] != 'scheduled') {
          throw StateError('This booking cannot be cancelled');
        }

        // For scheduled bookings, block cancellation once the session
        // start time has arrived.
        if (data['status'] == 'scheduled') {
          final scheduledTime = data['sessionDate'];

          if (scheduledTime is! Timestamp ||
              !scheduledTime.toDate().isAfter(DateTime.now())) {
            throw StateError(
              'You cannot cancel a session once its scheduled time has arrived.',
            );
          }
        }

        transaction.update(reference, {
          'status': 'cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (mounted) showMessage('Booking cancelled');
    } on FirebaseException catch (e) {
      if (mounted) {
        showMessage(
          e.code == 'permission-denied'
              ? 'Cancellation blocked by Firestore rules'
              : 'Unable to cancel booking',
        );
      }
    } on StateError catch (e) {
      if (mounted) showMessage(e.message);
    }
  }

  Widget bookingCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    final name = data['tutorName']?.toString() ?? 'Tutor';
    final subject = data['subject']?.toString() ?? '';
    final topic = data['topic']?.toString() ?? '';
    final status = data['status']?.toString() ?? 'pending';
    final link = data['meetingLink']?.toString() ?? '';

    final timestamp = data['sessionDate'];
    final date = timestamp is Timestamp ? timestamp.toDate() : null;

    final canCancel =
        status == 'pending' ||
        (status == 'scheduled' && date != null && date.isAfter(DateTime.now()));

    final sessionStarted =
        status == 'scheduled' && date != null && !date.isAfter(DateTime.now());

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: teal,
              ),
            ),
            const SizedBox(height: 8),
            Text('Subject: $subject'),
            Text('Topic: $topic'),
            const SizedBox(height: 8),
            Text('Status: ${status.toUpperCase()}'),

            if (date != null) ...[
              const SizedBox(height: 8),
              Text('Date: ${date.day}/${date.month}/${date.year}'),
              Text('Time: ${TimeOfDay.fromDateTime(date).format(context)}'),
            ],

            if (status == 'scheduled' && link.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.link, color: teal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      link,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: teal),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: link));
                      showMessage('Teams link copied');
                    },
                  ),
                ],
              ),
            ],

            if (canCancel) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => cancelBooking(doc.id),
                child: const Text('Cancel Booking'),
              ),
            ],

            if (sessionStarted) ...[
              const SizedBox(height: 10),
              const Text(
                'Cancellation is no longer available because '
                'the session has started.',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            if (status == 'completed') ...[
              const SizedBox(height: 10),
              const Text('Session completed', style: TextStyle(color: teal)),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(
                          title: const Text('My Reviews'),
                          backgroundColor: const Color(0xFF008080),
                          foregroundColor: Colors.white,
                        ),
                        body: const StudentReviews(),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.star),
                label: const Text('Review Session'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: teal,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionButton({
    required IconData icon,
    required String title,
    required int index,
  }) {
    final selected = selectedSection == index;

    return InkWell(
      onTap: () => setState(() => selectedSection = index),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE0F2F1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? teal : Colors.grey.shade300),
        ),
        child: Column(
          children: [
            Icon(icon, color: teal, size: 28),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? teal : Colors.black87,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestSession(String studentId) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Request a Session',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: teal,
          ),
        ),
        const SizedBox(height: 8),
        const Text('Choose a tutor who accepted your application.'),
        const SizedBox(height: 16),

        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db
              .collection('applications')
              .where('studentId', isEqualTo: studentId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text('Unable to load tutors');
            }

            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: teal),
              );
            }

            final accepted = snapshot.data!.docs
                .where((doc) => doc.data()['status'] == 'accepted')
                .toList();

            if (accepted.isEmpty) {
              return const Text('No accepted tutors yet');
            }

            return Column(
              children: accepted.map((doc) {
                final data = doc.data();
                final tutorId = data['tutorId']?.toString() ?? '';

                return Card(
                  color: Colors.white,
                  child: ListTile(
                    leading: const Icon(Icons.person, color: teal),
                    title: tutorId.isEmpty
                        ? const Text('Tutor unavailable')
                        : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            stream: db
                                .collection('tutor_profiles')
                                .doc(tutorId)
                                .snapshots(),
                            builder: (context, tutorSnapshot) {
                              if (tutorSnapshot.hasError) {
                                return const Text('Unable to load tutor name');
                              }

                              if (!tutorSnapshot.hasData) {
                                return const Text('Loading tutor...');
                              }

                              final tutorData = tutorSnapshot.data!.data();

                              final tutorName =
                                  tutorData?['fullName']?.toString() ?? 'Tutor';

                              final subjects =
                                  tutorData?['subjectsOffered'] is List
                                  ? (tutorData!['subjectsOffered'] as List)
                                        .whereType<String>()
                                        .join(', ')
                                  : '';

                              // Strip "Grade " prefix so "Grade 10, Grade 11"
                              // becomes "10, 11".
                              final grades = tutorData?['gradesOffered'] is List
                                  ? (tutorData!['gradesOffered'] as List)
                                        .whereType<String>()
                                        .map(
                                          (grade) => grade.replaceFirst(
                                            RegExp(
                                              r'^Grade\s+',
                                              caseSensitive: false,
                                            ),
                                            '',
                                          ),
                                        )
                                        .join(', ')
                                  : '';

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tutorName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Subjects: ${subjects.isEmpty ? 'Not available' : subjects}',
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Grades: ${grades.isEmpty ? 'Not available' : grades}',
                                  ),
                                ],
                              );
                            },
                          ),
                    subtitle: const Text('Tap to request a session'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: tutorId.isEmpty ? null : () => requestSession(doc),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMyBookings(String studentId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db
          .collection('bookings')
          .where('studentId', isEqualTo: studentId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Unable to load bookings'));
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: teal));
        }

        final bookings = snapshot.data!.docs.toList();

        bookings.sort((a, b) {
          final aDate = a.data()['createdAt'];
          final bDate = b.data()['createdAt'];

          final aTime = aDate is Timestamp ? aDate.millisecondsSinceEpoch : 0;
          final bTime = bDate is Timestamp ? bDate.millisecondsSinceEpoch : 0;

          return bTime.compareTo(aTime);
        });

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'My Bookings',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: teal,
              ),
            ),
            const SizedBox(height: 8),
            const Text('View your tutoring sessions and their status.'),
            const SizedBox(height: 16),

            if (bookings.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('No bookings yet'),
                ),
              ),

            ...bookings.map((doc) => bookingCard(doc)),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(child: Text('Please log in first'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: _sectionButton(
                  icon: Icons.calendar_month_outlined,
                  title: 'Request Session',
                  index: 0,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _sectionButton(
                  icon: Icons.event_note_outlined,
                  title: 'My Bookings',
                  index: 1,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: selectedSection == 0
              ? _buildRequestSession(user.uid)
              : _buildMyBookings(user.uid),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// REQUEST SESSION DIALOG
// ─────────────────────────────────────────────────────────────
class _RequestSessionDialog extends StatefulWidget {
  final List<String> subjects;

  const _RequestSessionDialog({required this.subjects});

  @override
  State<_RequestSessionDialog> createState() => _RequestSessionDialogState();
}

class _RequestSessionDialogState extends State<_RequestSessionDialog> {
  static const teal = Color(0xFF008080);

  final _topicController = TextEditingController();
  late String _selectedSubject;

  @override
  void initState() {
    super.initState();
    _selectedSubject = widget.subjects.first;
  }

  @override
  void dispose() {
    _topicController.dispose();
    super.dispose();
  }

  void _submit() {
    final topic = _topicController.text.trim();
    if (topic.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please enter a topic')));
      return;
    }

    Navigator.pop(context, {'subject': _selectedSubject, 'topic': topic});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Request Session'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Subject'),
            DropdownButtonFormField<String>(
              initialValue: _selectedSubject,
              isExpanded: true,
              items: widget.subjects.map((s) {
                return DropdownMenuItem(value: s, child: Text(s));
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedSubject = value);
                }
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _topicController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Topic',
                hintText: 'e.g. Algebra',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: teal,
            foregroundColor: Colors.white,
          ),
          child: const Text('Request'),
        ),
      ],
    );
  }
}
