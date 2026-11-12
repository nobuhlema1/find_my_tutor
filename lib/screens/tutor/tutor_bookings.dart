import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

class TutorBookings extends StatelessWidget {
  const TutorBookings({super.key});

  static const teal = Color(0xFF008080);

  Future<void> scheduleSession(BuildContext context, String bookingId) async {
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now();
    final linkController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Schedule Session'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: const Text('Date'),
                      subtitle: Text(
                        '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );

                        if (picked != null) {
                          setDialogState(() {
                            selectedDate = picked;
                          });
                        }
                      },
                    ),
                    ListTile(
                      title: const Text('Time'),
                      subtitle: Text(selectedTime.format(context)),
                      trailing: const Icon(Icons.access_time),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );

                        if (picked != null) {
                          setDialogState(() {
                            selectedTime = picked;
                          });
                        }
                      },
                    ),
                    TextField(
                      controller: linkController,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Microsoft Teams Link',
                        hintText: 'https://teams.microsoft.com/...',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, false);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: teal,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (!linkController.text.trim().startsWith('https://')) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Enter a valid HTTPS Teams meeting link',
                          ),
                        ),
                      );
                      return;
                    }

                    Navigator.pop(dialogContext, true);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true) {
      linkController.dispose();
      return;
    }

    final sessionDate = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );

    if (!sessionDate.isAfter(DateTime.now())) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please choose a future date and time')),
        );
      }
      linkController.dispose();
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(bookingId)
          .update({
            'status': 'scheduled',
            'sessionDate': Timestamp.fromDate(sessionDate),
            'meetingLink': linkController.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session scheduled successfully!')),
        );
      }
    } on FirebaseException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to schedule session')),
        );
      }
    } finally {
      linkController.dispose();
    }
  }

  Future<void> updateStatus(
    BuildContext context,
    String bookingId,
    String status,
  ) async {
    try {
      final bookingRef = FirebaseFirestore.instance
          .collection('bookings')
          .doc(bookingId);

      if (status == 'completed') {
        final bookingSnapshot = await bookingRef.get();

        if (!context.mounted) return;

        if (!bookingSnapshot.exists) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Booking not found')));
          return;
        }

        final booking = bookingSnapshot.data();

        if (booking?['status'] != 'scheduled') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Only scheduled sessions can be completed.'),
            ),
          );
          return;
        }

        final scheduledTime = booking?['sessionDate'];

        if (scheduledTime is! Timestamp ||
            DateTime.now().isBefore(scheduledTime.toDate())) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cannot mark as completed before the scheduled session time.',
              ),
            ),
          );
          return;
        }
      }

      await bookingRef.update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Booking $status')));
      }
    } on FirebaseException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.code == 'permission-denied'
                  ? 'This booking update is not allowed.'
                  : 'Unable to update booking.',
            ),
          ),
        );
      }
    }
  }

  Widget bookingCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();

    final studentName = data['studentName']?.toString() ?? 'Student';
    final studentGrade = data['studentGrade']?.toString() ?? 'Not available';

    final subject = data['subject']?.toString() ?? '';
    final topic = data['topic']?.toString() ?? '';
    final status = data['status']?.toString() ?? 'pending';

    final sessionDate = data['sessionDate'] is Timestamp
        ? (data['sessionDate'] as Timestamp).toDate()
        : null;

    final meetingLink = data['meetingLink']?.toString() ?? '';

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
            Text(studentGrade),
            Text('Subject: $subject'),
            Text('Topic: $topic'),
            const SizedBox(height: 12),

            if (sessionDate != null) ...[
              Text(
                'Date: ${sessionDate.day}/${sessionDate.month}/${sessionDate.year}',
              ),
              Text(
                'Time: ${TimeOfDay.fromDateTime(sessionDate).format(context)}',
              ),
              const SizedBox(height: 8),
            ],

            if (status == 'scheduled' && meetingLink.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.link, color: teal, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      meetingLink,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: teal),
                    tooltip: 'Copy Teams link',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: meetingLink));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied')),
                      );
                    },
                  ),
                ],
              ),
            ],

            if (status == 'pending')
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          updateStatus(context, doc.id, 'declined'),
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: teal,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => scheduleSession(context, doc.id),
                      child: const Text('Schedule'),
                    ),
                  ),
                ],
              ),

            if (status == 'scheduled')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: teal,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => updateStatus(context, doc.id, 'completed'),
                  child: const Text('Mark as Completed'),
                ),
              ),

            if (status == 'completed')
              const Text(
                'Completed',
                style: TextStyle(color: teal, fontWeight: FontWeight.bold),
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

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const Material(
            color: Colors.white,
            child: TabBar(
              labelColor: teal,
              indicatorColor: teal,
              unselectedLabelColor: Colors.grey,
              tabs: [
                Tab(text: 'Pending'),
                Tab(text: 'Scheduled'),
                Tab(text: 'Completed'),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('bookings')
                  .where('tutorId', isEqualTo: user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Unable to load bookings'));
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: teal),
                  );
                }

                final bookings = snapshot.data!.docs;

                final pending = bookings
                    .where((doc) => doc.data()['status'] == 'pending')
                    .toList();

                final scheduled = bookings
                    .where((doc) => doc.data()['status'] == 'scheduled')
                    .toList();

                final completed = bookings
                    .where((doc) => doc.data()['status'] == 'completed')
                    .toList();

                Widget bookingList(
                  List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
                  String emptyMessage,
                ) {
                  if (items.isEmpty) {
                    return Center(child: Text(emptyMessage));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    itemBuilder: (context, index) =>
                        bookingCard(context, items[index]),
                  );
                }

                return TabBarView(
                  children: [
                    bookingList(pending, 'No pending requests'),
                    bookingList(scheduled, 'No scheduled sessions'),
                    bookingList(completed, 'No completed sessions'),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
