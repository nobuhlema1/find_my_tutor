import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'student_profile.dart';
import 'student_my_tutors.dart';
import 'student_bookings.dart';
import 'student_reviews.dart';
import '../login_screen.dart';

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../services/notification_service.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  static const teal = Color(0xFF008080);
  static const lightTeal = Color(0xFFE0F2F1);
  String currentPage = 'Dashboard';
  String studentName = 'Student';

  @override
  void initState() {
    super.initState();
    loadName();
    listenForAcceptedApplications();
    listenForStudentBookings();
    listenForPendingReviews();
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  acceptedApplicationSubscription;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? bookingSubscription;

  Future<void> listenForAcceptedApplications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    acceptedApplicationSubscription = FirebaseFirestore.instance
        .collection('applications')
        .where('studentId', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) async {
          for (final change in snapshot.docChanges) {
            final data = change.doc.data();
            if (data == null || data['status'] != 'accepted') continue;

            final notificationKey = 'accepted_${user.uid}_${change.doc.id}';

            if (prefs.getBool(notificationKey) == true) continue;

            await NotificationService.instance.showNotification(
              id: change.doc.id.hashCode & 0x7FFFFFFF,
              title: 'Application Accepted',
              body: 'Your tutoring application has been accepted!',
            );

            await prefs.setBool(notificationKey, true);
          }
        });
  }

  Future<void> listenForStudentBookings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    bookingSubscription = FirebaseFirestore.instance
        .collection('bookings')
        .where('studentId', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) async {
          for (final change in snapshot.docChanges) {
            final data = change.doc.data();
            if (data == null) continue;

            final reminderId =
                ('lesson_${user.uid}_${change.doc.id}').hashCode & 0x7FFFFFFF;

            if (data['status'] == 'scheduled' &&
                data['sessionDate'] is Timestamp) {
              final sessionDate = (data['sessionDate'] as Timestamp).toDate();

              await NotificationService.instance.scheduleLessonReminder(
                id: reminderId,
                sessionDate: sessionDate,
              );
            } else {
              await NotificationService.instance.cancelNotification(reminderId);
            }
          }
        });
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  pendingReviewSubscription;

  Future<void> listenForPendingReviews() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    pendingReviewSubscription = FirebaseFirestore.instance
        .collection('bookings')
        .where('studentId', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) async {
          for (final bookingDoc in snapshot.docs) {
            final booking = bookingDoc.data();

            if (booking['status'] != 'completed') continue;

            final notificationKey =
                'pending_review_${user.uid}_${bookingDoc.id}';

            if (prefs.getBool(notificationKey) == true) continue;

            try {
              final reviewDoc = await FirebaseFirestore.instance
                  .collection('reviews')
                  .doc(bookingDoc.id)
                  .get();

              if (!mounted) return;

              // Don't notify if this session has already been reviewed.
              if (reviewDoc.exists) continue;

              // Avoid duplicate notifications while processing.
              if (prefs.getBool(notificationKey) == true) continue;

              await NotificationService.instance.showNotification(
                id: notificationKey.hashCode & 0x7FFFFFFF,
                title: 'You have a pending review',
                body:
                    'Your tutoring session has been completed. '
                    'Please review your tutor.',
              );

              await prefs.setBool(notificationKey, true);
            } on FirebaseException {
              // A temporary connection problem should not mark
              // this review notification as delivered.
            }
          }
        });
  }

  @override
  void dispose() {
    acceptedApplicationSubscription?.cancel();
    bookingSubscription?.cancel();
    pendingReviewSubscription?.cancel();
    super.dispose();
  }

  Future<void> loadName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!mounted) return;
      setState(() {
        studentName = doc.data()?['fullName']?.toString() ?? 'Student';
      });
    } catch (_) {}
  }

  void navigateTo(String page) {
    Navigator.of(context).pop();
    setState(() => currentPage = page);
  }

  Widget menuItem(String title, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: teal),
      title: Text(title),
      selected: currentPage == title,
      selectedTileColor: lightTeal,
      onTap: () => navigateTo(title),
    );
  }

  Widget buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: teal,
              padding: const EdgeInsets.all(25),
              child: const Column(
                children: [
                  Icon(Icons.school, color: Colors.white, size: 55),
                  SizedBox(height: 12),
                  Text(
                    'Find My Tutor',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Student Portal',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            menuItem('Dashboard', Icons.dashboard_outlined),
            menuItem('My Profile', Icons.person_outline),
            menuItem('My Tutors', Icons.people_outline),
            menuItem('Bookings', Icons.calendar_month_outlined),
            menuItem('Reviews', Icons.star_outline),

            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: teal),
              title: const Text('Log Out'),
              onTap: () async {
                await NotificationService.instance.cancelAllNotifications();
                await FirebaseAuth.instance.signOut();

                if (!mounted) return;

                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget buildHome() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 30),

        const Center(
          child: CircleAvatar(
            radius: 45,
            backgroundColor: Colors.white,
            child: Icon(Icons.school, size: 50, color: teal),
          ),
        ),

        const SizedBox(height: 24),

        Text(
          'Hello, $studentName! ',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: teal,
          ),
        ),

        const SizedBox(height: 12),

        const Text(
          'Welcome to Find My Tutor!',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18),
        ),

        const SizedBox(height: 8),

        const Text(
          'Your learning journey starts here.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15),
        ),

        const SizedBox(height: 35),

        Card(
          color: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.auto_awesome, color: teal, size: 35),
                SizedBox(height: 14),
                Text(
                  'Every step you take towards learning brings you closer to your dreams.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Keep learning. Keep growing. Keep believing.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: teal, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 30),

        const Text(
          'Use the menu ☰ at the top left to explore your tutors, bookings and reviews.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
      ],
    );
  }

  Widget buildPlaceholder(String page) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '$page will be implemented next',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    switch (currentPage) {
      case 'Dashboard':
        content = buildHome();
        break;
      case 'My Profile':
        content = const StudentProfile();
        break;
      case 'My Tutors':
        content = const StudentMyTutors();
        break;
      case 'Bookings':
        content = const StudentBookings();
        break;
      case 'Reviews':
        content = const StudentReviews();
        break;
      default:
        content = buildPlaceholder(currentPage);
    }

    return Scaffold(
      backgroundColor: lightTeal,
      appBar: AppBar(
        title: Text(currentPage),
        backgroundColor: teal,
        foregroundColor: Colors.white,
      ),
      drawer: buildDrawer(),
      body: content,
    );
  }
}
