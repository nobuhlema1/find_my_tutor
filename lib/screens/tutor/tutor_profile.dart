import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TutorProfile extends StatefulWidget {
  const TutorProfile({super.key});

  @override
  State<TutorProfile> createState() => _TutorProfileState();
}

class _TutorProfileState extends State<TutorProfile> {
  static const teal = Color(0xFF008080);

  final qualificationController = TextEditingController();

  String tutorName = 'Tutor';
  List<String> subjects = [];
  List<String> grades = [];

  Set<String> selectedSubjects = {};
  Set<String> selectedGrades = {};

  bool isLoading = true;
  bool isSaving = false;
  bool isEditing = false;
  bool profileComplete = false;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  @override
  void dispose() {
    qualificationController.dispose();
    super.dispose();
  }

  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (mounted) setState(() => isLoading = false);
      return;
    }

    setState(() => isLoading = true);

    try {
      final db = FirebaseFirestore.instance;

      final profile = await db.collection('users').doc(user.uid).get();

      final subjectSnapshot = await db.collection('subjects').get();

      final gradeSnapshot = await db
          .collection('grade_levels')
          .orderBy('order')
          .get();

      if (!mounted) return;

      final data = profile.data();

      if (data == null || data['role'] != 'Tutor') {
        setState(() => isLoading = false);
        showMessage('Tutor profile not found');
        return;
      }

      final loadedSubjects =
          subjectSnapshot.docs
              .map((doc) => doc.data()['name']?.toString() ?? '')
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

      final loadedGrades = gradeSnapshot.docs
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

      final storedSubjects = data['subjectsOffered'];
      final storedGrades = data['gradesOffered'];

      final validSubjects = storedSubjects is List
          ? storedSubjects.whereType<String>().toSet().intersection(
              loadedSubjects.toSet(),
            )
          : <String>{};

      final validGrades = storedGrades is List
          ? storedGrades.whereType<String>().toSet().intersection(
              loadedGrades.toSet(),
            )
          : <String>{};

      final qualification = data['qualification']?.toString() ?? '';

      final complete =
          qualification.trim().isNotEmpty &&
          validSubjects.isNotEmpty &&
          validGrades.isNotEmpty;

      setState(() {
        tutorName = data['fullName']?.toString() ?? 'Tutor';

        qualificationController.text = qualification;
        subjects = loadedSubjects;
        grades = loadedGrades;

        selectedSubjects = validSubjects;
        selectedGrades = validGrades;

        profileComplete = complete;
        isEditing = !complete;
        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => isLoading = false);
      showMessage('Unable to load tutor profile');
    }
  }

  Future<void> saveProfile() async {
    if (isSaving) return;

    final user = FirebaseAuth.instance.currentUser;
    final qualification = qualificationController.text.trim();

    if (user == null) {
      showMessage('Please log in first');
      return;
    }

    if (qualification.isEmpty ||
        selectedSubjects.isEmpty ||
        selectedGrades.isEmpty) {
      showMessage('Enter qualifications and select subjects and grades');
      return;
    }

    setState(() => isSaving = true);

    try {
      final db = FirebaseFirestore.instance;

      final subjectsList = selectedSubjects.toList()..sort();
      final gradesList = selectedGrades.toList()..sort();

      final batch = db.batch();

      final userReference = db.collection('users').doc(user.uid);

      final publicProfileReference = db
          .collection('tutor_profiles')
          .doc(user.uid);

      batch.update(userReference, {
        'qualification': qualification,
        'subjectsOffered': subjectsList,
        'gradesOffered': gradesList,
        'profileUpdatedAt': FieldValue.serverTimestamp(),
      });

      batch.set(publicProfileReference, {
        'tutorId': user.uid,
        'fullName': tutorName,
        'qualification': qualification,
        'subjectsOffered': subjectsList,
        'gradesOffered': gradesList,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      if (!mounted) return;

      setState(() {
        profileComplete = true;
        isEditing = false;
      });

      showMessage('Tutor profile saved successfully!');
    } on FirebaseException catch (e) {
      showMessage(
        e.code == 'permission-denied'
            ? 'Profile update blocked by Firestore rules'
            : 'Could not save tutor profile',
      );
    } catch (_) {
      showMessage('An unexpected error occurred');
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  Widget informationTile(String label, String value) {
    return Card(
      color: Colors.white,
      child: ListTile(
        title: Text(
          label,
          style: const TextStyle(color: teal, fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(value),
        ),
      ),
    );
  }

  Widget buildViewProfile() {
    final displaySubjects = selectedSubjects.toList()..sort();
    final displayGrades = selectedGrades.toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Center(
          child: CircleAvatar(
            radius: 42,
            backgroundColor: Color(0xFFE0F2F1),
            child: Icon(Icons.person, size: 48, color: teal),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            tutorName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
        const Center(
          child: Text('Tutor Profile', style: TextStyle(color: teal)),
        ),
        const SizedBox(height: 24),
        informationTile('Full Name', tutorName),
        informationTile('Qualifications', qualificationController.text.trim()),
        informationTile('Subjects Offered', displaySubjects.join(', ')),
        informationTile('Grade Levels Offered', displayGrades.join(', ')),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: () {
              setState(() => isEditing = true);
            },
            icon: const Icon(Icons.edit),
            label: const Text('Update Profile'),
            style: ElevatedButton.styleFrom(
              backgroundColor: teal,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget buildEditProfile() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          profileComplete
              ? 'Update Your Tutor Profile'
              : 'Complete Your Tutor Profile',
          style: const TextStyle(
            color: teal,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text('Tutor: $tutorName'),
        const SizedBox(height: 20),
        TextButton.icon(
          onPressed: isSaving ? null : loadProfile,
          icon: const Icon(Icons.refresh, color: teal),
          label: const Text(
            'Refresh Subjects and Grades',
            style: TextStyle(color: teal),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Qualifications',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: qualificationController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Enter your qualifications',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 25),
        const Text(
          'Subjects Offered',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: teal,
          ),
        ),
        if (subjects.isEmpty) const Text('No subjects are available yet.'),
        ...subjects.map(
          (subject) => CheckboxListTile(
            title: Text(subject),
            value: selectedSubjects.contains(subject),
            activeColor: teal,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (checked) {
              setState(() {
                if (checked == true) {
                  selectedSubjects.add(subject);
                } else {
                  selectedSubjects.remove(subject);
                }
              });
            },
          ),
        ),
        const SizedBox(height: 25),
        const Text(
          'Grade Levels Offered',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: teal,
          ),
        ),
        if (grades.isEmpty) const Text('No grades are available yet.'),
        ...grades.map(
          (grade) => CheckboxListTile(
            title: Text(grade),
            value: selectedGrades.contains(grade),
            activeColor: teal,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (checked) {
              setState(() {
                if (checked == true) {
                  selectedGrades.add(grade);
                } else {
                  selectedGrades.remove(grade);
                }
              });
            },
          ),
        ),
        const SizedBox(height: 25),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: isSaving ? null : saveProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: teal,
              foregroundColor: Colors.white,
            ),
            child: Text(isSaving ? 'Saving...' : 'Save Profile'),
          ),
        ),
        if (profileComplete) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: isSaving ? null : loadProfile,
            child: const Text('Cancel and View Profile'),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: teal));
    }

    return isEditing ? buildEditProfile() : buildViewProfile();
  }
}
