import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'dart:async';

import '../../services/notification_service.dart';

import '../login_screen.dart';
import 'tutor_profile.dart';
import 'tutor_subjects.dart';
import 'tutor_my_students.dart';
import 'tutor_enrolled_students.dart';
import 'tutor_bookings.dart';
import 'tutor_reviews.dart';

class TutorDashboard extends StatefulWidget {
  const TutorDashboard({super.key});

  @override
  State<TutorDashboard> createState() => _TutorDashboardState();
}

class _TutorDashboardState extends State<TutorDashboard> {
  static const teal = Color(0xFF008080);
  static const lightTeal = Color(0xFFE0F2F1);

  String currentPage = 'Dashboard';
  String tutorName = 'Tutor';

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  applicationSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? bookingSubscription;

  @override
  void initState() {
    super.initState();
    loadTutorName();
    listenForApplications();
    listenForBookings();
  }

  Future<void> listenForApplications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    applicationSubscription = FirebaseFirestore.instance
        .collection('applications')
        .where('tutorId', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) async {
          for (final change in snapshot.docChanges) {
            final data = change.doc.data();
            if (data == null || data['status'] != 'pending') continue;

            final notificationKey = 'application_${user.uid}_${change.doc.id}';

            if (prefs.getBool(notificationKey) == true) continue;

            final studentName = data['studentName']?.toString() ?? 'A student';

            await NotificationService.instance.showNotification(
              id: change.doc.id.hashCode & 0x7FFFFFFF,
              title: 'New Tutoring Application',
              body: '$studentName has applied for tutoring.',
            );

            await prefs.setBool(notificationKey, true);
          }
        });
  }

  Future<void> listenForBookings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    bookingSubscription = FirebaseFirestore.instance
        .collection('bookings')
        .where('tutorId', isEqualTo: user.uid)
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

            if (data['status'] != 'pending') continue;

            final notificationKey = 'booking_${user.uid}_${change.doc.id}';

            if (prefs.getBool(notificationKey) == true) continue;

            await NotificationService.instance.showNotification(
              id: ('booking_${change.doc.id}').hashCode & 0x7FFFFFFF,
              title: 'New Booking Request',
              body: 'A student has requested a tutoring session.',
            );

            await prefs.setBool(notificationKey, true);
          }
        });
  }

  @override
  void dispose() {
    applicationSubscription?.cancel();
    bookingSubscription?.cancel();
    super.dispose();
  }

  Future<void> loadTutorName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final document = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      setState(() {
        tutorName = document.data()?['fullName']?.toString() ?? 'Tutor';
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load tutor name')),
      );
    }
  }

  void navigateTo(String page) {
    Navigator.of(context).pop();
    setState(() {
      currentPage = page;
    });
  }

  Widget drawerItem(String title, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: teal),
      title: Text(title),
      selected: currentPage == title,
      selectedTileColor: lightTeal,
      onTap: () => navigateTo(title),
    );
  }

  Future<void> logout() async {
    await NotificationService.instance.cancelAllNotifications();
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
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
              padding: const EdgeInsets.all(24),
              child: const Column(
                children: [
                  Icon(Icons.school_rounded, color: Colors.white, size: 55),
                  SizedBox(height: 10),
                  Text(
                    'Find My Tutor',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text('Tutor Portal', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  drawerItem('Dashboard', Icons.dashboard_outlined),
                  drawerItem('My Profile', Icons.person_outline),
                  drawerItem('Subjects', Icons.menu_book_outlined),
                  drawerItem('Student Applications', Icons.assignment_outlined),
                  drawerItem('Enrolled Students', Icons.people_outline),
                  drawerItem('Bookings', Icons.calendar_month_outlined),
                  drawerItem('My Reviews', Icons.star_outline),
                  ListTile(
                    leading: const Icon(Icons.logout, color: teal),
                    title: const Text('Log Out'),
                    onTap: logout,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildHome() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 20),

        // Welcome card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: teal,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TUTOR HOME',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Welcome to Find My Tutor!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.person_outline, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tutorName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // One short motivational sentence
        Card(
          color: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome, color: teal, size: 26),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Every lesson is an opportunity to inspire a learner.',
                    style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget buildPlaceholder(String page) {
    return Center(
      child: Text(
        '$page will be implemented next',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, color: teal),
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
        content = const TutorProfile();
        break;

      case 'Subjects':
        content = const TutorSubjects();
        break;

      case 'Student Applications':
        content = const TutorMyStudents();
        break;

      case 'Enrolled Students':
        content = const TutorEnrolledStudents();
        break;

      case 'Bookings':
        content = const TutorBookings();
        break;

      case 'My Reviews':
        content = const TutorReviews();
        break;

      default:
        content = buildHome();
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
