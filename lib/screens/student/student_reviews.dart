import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StudentReviews extends StatelessWidget {
  const StudentReviews({super.key});

  static const teal = Color(0xFF008080);

  String formatDateTime(dynamic value) {
    if (value is! Timestamp) return 'Not available';
    final date = value.toDate();
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} at $hour:$minute';
  }

  Future<void> writeReview(
    BuildContext context,
    String bookingId,
    String tutorName,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ReviewDialog(tutorName: tutorName),
    );

    if (result == null || !context.mounted) return;

    final rating = result['rating'] as int;
    final comment = (result['comment'] as String).trim();

    try {
      final db = FirebaseFirestore.instance;
      final bookingRef = db.collection('bookings').doc(bookingId);
      final reviewRef = db.collection('reviews').doc(bookingId);

      await db.runTransaction((transaction) async {
        final bookingSnapshot = await transaction.get(bookingRef);
        final existingReview = await transaction.get(reviewRef);

        if (!bookingSnapshot.exists) {
          throw StateError('Booking not found');
        }

        final booking = bookingSnapshot.data()!;

        if (booking['studentId'] != user.uid) {
          throw StateError('This booking is not yours');
        }

        if (booking['status'] != 'completed') {
          throw StateError('Session must be completed first');
        }

        if (existingReview.exists) {
          throw StateError('You already reviewed this session');
        }

        transaction.set(reviewRef, {
          'bookingId': bookingId,
          'studentId': user.uid,
          'studentName': booking['studentName'] ?? 'Student',
          'studentGrade': booking['studentGrade'],
          'tutorId': booking['tutorId'],
          'tutorName': booking['tutorName'] ?? tutorName,
          'subject': booking['subject'] ?? '',
          'topic': booking['topic'] ?? '',
          'sessionDate': booking['sessionDate'],
          'rating': rating,
          'comment': comment,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Review submitted successfully!')),
        );
      }
    } on StateError catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } on FirebaseException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.code == 'permission-denied'
                  ? 'Review blocked by Firestore rules'
                  : 'Unable to submit review',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(child: Text('Please log in first'));
    }

    final db = FirebaseFirestore.instance;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db
          .collection('bookings')
          .where('studentId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, bookingSnapshot) {
        if (bookingSnapshot.hasError) {
          return const Center(child: Text('Unable to load completed sessions'));
        }

        if (!bookingSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: teal));
        }

        final completed = bookingSnapshot.data!.docs
            .where((doc) => doc.data()['status'] == 'completed')
            .toList();

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db
              .collection('reviews')
              .where('studentId', isEqualTo: user.uid)
              .snapshots(),
          builder: (context, reviewSnapshot) {
            if (reviewSnapshot.hasError) {
              return const Center(child: Text('Unable to load your reviews'));
            }

            if (!reviewSnapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: teal),
              );
            }

            final reviews = {
              for (final doc in reviewSnapshot.data!.docs) doc.id: doc.data(),
            };

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'My Reviews',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: teal,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Review your completed tutoring sessions.'),
                const SizedBox(height: 20),
                if (completed.isEmpty) const Text('No completed sessions yet'),
                ...completed.map((bookingDoc) {
                  final booking = bookingDoc.data();
                  final tutorName = booking['tutorName']?.toString() ?? 'Tutor';
                  final subject = booking['subject']?.toString() ?? '';
                  final topic = booking['topic']?.toString() ?? '';

                  final existingReview = reviews[bookingDoc.id];

                  return Card(
                    color: Colors.white,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tutorName,
                            style: const TextStyle(
                              color: teal,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('Subject: $subject'),
                          Text('Topic: $topic'),
                          Text(
                            'Session date and time: '
                            '${formatDateTime(booking['sessionDate'])}',
                          ),
                          const SizedBox(height: 12),
                          if (existingReview == null)
                            ElevatedButton.icon(
                              onPressed: () => writeReview(
                                context,
                                bookingDoc.id,
                                tutorName,
                              ),
                              icon: const Icon(Icons.star),
                              label: const Text('Review Session'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: teal,
                                foregroundColor: Colors.white,
                              ),
                            )
                          else ...[
                            Row(
                              children: List.generate(5, (index) {
                                final savedRating =
                                    (existingReview['rating'] as num?)
                                        ?.toInt() ??
                                    0;
                                return Icon(
                                  index < savedRating
                                      ? Icons.star
                                      : Icons.star_border,
                                  color: Colors.amber,
                                  size: 22,
                                );
                              }),
                            ),
                            const SizedBox(height: 8),
                            Text(existingReview['comment']?.toString() ?? ''),
                            const SizedBox(height: 8),
                            const Text(
                              'Review submitted',
                              style: TextStyle(color: teal),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Reviewed on: '
                              '${formatDateTime(existingReview['createdAt'])}',
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// REVIEW DIALOG — owns its TextEditingController
// ─────────────────────────────────────────────────────────────
class _ReviewDialog extends StatefulWidget {
  final String tutorName;

  const _ReviewDialog({required this.tutorName});

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  static const teal = Color(0xFF008080);

  final _commentController = TextEditingController();
  int _rating = 0;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_rating == 0 || _commentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select stars and write a review')),
      );
      return;
    }

    Navigator.pop(context, {
      'rating': _rating,
      'comment': _commentController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Review ${widget.tutorName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('How was your tutoring session?'),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              children: List.generate(5, (index) {
                return IconButton(
                  icon: Icon(
                    index < _rating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                  ),
                  onPressed: () {
                    setState(() => _rating = index + 1);
                  },
                );
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _commentController,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Your Review',
                hintText: 'Tell us about your session',
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
          style: ElevatedButton.styleFrom(
            backgroundColor: teal,
            foregroundColor: Colors.white,
          ),
          onPressed: _submit,
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
