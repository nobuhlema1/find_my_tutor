import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TutorReviews extends StatelessWidget {
  const TutorReviews({super.key});

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

  Widget stars(int rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Icon(
          index < rating ? Icons.star : Icons.star_border,
          color: Colors.amber,
          size: 20,
        );
      }),
    );
  }

  Widget reviewCard(
    QueryDocumentSnapshot<Map<String, dynamic>> reviewDoc,
    String tutorId,
  ) {
    final review = reviewDoc.data();

    final studentName = review['studentName']?.toString() ?? 'Student';
    final reviewGrade = review['studentGrade']?.toString() ?? '';
    final comment = review['comment']?.toString() ?? '';
    final rating = review['rating'] is num
        ? (review['rating'] as num).toInt()
        : 0;
    final bookingId = review['bookingId']?.toString() ?? reviewDoc.id;

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              studentName,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: teal,
              ),
            ),
            const SizedBox(height: 8),
            stars(rating),
            const SizedBox(height: 8),
            Text('Rating: $rating/5'),
            const SizedBox(height: 8),
            Text('Review: $comment'),
            const SizedBox(height: 12),
            Text('Reviewed on: ${formatDateTime(review['createdAt'])}'),
            const Divider(height: 24),
            FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance
                  .collection('bookings')
                  .doc(bookingId)
                  .get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Text('Loading session details...');
                }

                if (snapshot.hasError ||
                    !snapshot.hasData ||
                    !snapshot.data!.exists) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reviewGrade.trim().isEmpty
                            ? 'Not available'
                            : reviewGrade,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Subject: ${review['subject']?.toString() ?? 'Not available'}',
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Topic: ${review['topic']?.toString() ?? 'Not available'}',
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Session date and time: '
                        '${formatDateTime(review['sessionDate'])}',
                      ),
                    ],
                  );
                }

                final booking = snapshot.data!.data();
                if (booking == null || booking['tutorId'] != tutorId) {
                  return const Text('Session details unavailable');
                }

                final bookingGrade = booking['studentGrade']?.toString() ?? '';
                final studentGrade = reviewGrade.trim().isNotEmpty
                    ? reviewGrade
                    : bookingGrade.trim().isNotEmpty
                    ? bookingGrade
                    : 'Not available';
                final subject = booking['subject']?.toString() ?? 'Unknown';
                final topic = booking['topic']?.toString() ?? 'Unknown';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(studentGrade),
                    const SizedBox(height: 6),
                    Text('Subject: $subject'),
                    const SizedBox(height: 6),
                    Text('Topic: $topic'),
                    const SizedBox(height: 6),
                    Text(
                      'Session date and time: '
                      '${formatDateTime(booking['sessionDate'])}',
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(child: Text('Please log in first'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('reviews')
          .where('tutorId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Unable to load reviews'));
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: teal));
        }

        final reviews = snapshot.data!.docs;
        double totalStars = 0;

        for (final review in reviews) {
          final rating = review.data()['rating'];
          if (rating is num) totalStars += rating.toDouble();
        }

        final average = reviews.isEmpty ? 0.0 : totalStars / reviews.length;

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
            const SizedBox(height: 16),
            Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      reviews.isEmpty
                          ? 'No ratings yet'
                          : '${average.toStringAsFixed(1)} / 5',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: teal,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (reviews.isNotEmpty) stars(average.round()),
                    const SizedBox(height: 8),
                    Text(
                      '${reviews.length} '
                      '${reviews.length == 1 ? 'review' : 'reviews'}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Student Reviews',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: teal,
              ),
            ),
            const SizedBox(height: 12),
            if (reviews.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No student reviews yet.'),
                ),
              ),
            ...reviews.map((reviewDoc) => reviewCard(reviewDoc, user.uid)),
          ],
        );
      },
    );
  }
}
