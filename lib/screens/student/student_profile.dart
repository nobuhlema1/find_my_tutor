import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StudentProfile extends StatefulWidget {
  const StudentProfile({super.key});

  @override
  State<StudentProfile> createState() => _StudentProfileState();
}

class _StudentProfileState extends State<StudentProfile> {
  static const teal = Color(0xFF008080);

  final schoolController = TextEditingController();

  String fullName = 'Student';
  String? selectedGrade;
  Set<String> selectedSubjects = {};

  List<String> grades = [];
  List<String> subjects = [];

  bool isLoadingProfile = true;
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
    schoolController.dispose();
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
      if (mounted) {
        setState(() => isLoadingProfile = false);
      }
      return;
    }

    setState(() => isLoadingProfile = true);

    try {
      final db = FirebaseFirestore.instance;

      final profile = await db.collection('users').doc(user.uid).get();

      final gradeSnapshot = await db
          .collection('grade_levels')
          .orderBy('order')
          .get();

      final subjectSnapshot = await db.collection('subjects').get();

      if (!mounted) return;

      final data = profile.data();

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

      final loadedSubjects =
          subjectSnapshot.docs
              .map((doc) => doc.data()['name']?.toString() ?? '')
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

      final storedList = data?['subjectsNeeded'];

      final storedSubjects = storedList is List
          ? storedList.whereType<String>().toSet()
          : <String>{};

      if (storedList is! List) {
        final oldSubject = data?['subject'];

        if (oldSubject is String && oldSubject.isNotEmpty) {
          storedSubjects.add(oldSubject);
        }
      }

      final savedSchool = data?['schoolName']?.toString() ?? '';

      final savedGrade = data?['gradeLevel']?.toString();

      final validGrade = loadedGrades.contains(savedGrade) ? savedGrade : null;

      final validSubjects = storedSubjects.intersection(loadedSubjects.toSet());

      final complete =
          savedSchool.trim().isNotEmpty &&
          validGrade != null &&
          validSubjects.isNotEmpty;

      setState(() {
        fullName = data?['fullName']?.toString() ?? 'Student';

        grades = loadedGrades;
        subjects = loadedSubjects;

        schoolController.text = savedSchool;
        selectedGrade = validGrade;
        selectedSubjects = validSubjects;

        profileComplete = complete;
        isEditing = !complete;
        isLoadingProfile = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() => isLoadingProfile = false);
      showMessage('Unable to load student profile');
    }
  }

  Future<void> saveProfile() async {
    if (isSaving) return;

    final user = FirebaseAuth.instance.currentUser;
    final school = schoolController.text.trim();

    if (user == null) {
      showMessage('Please log in first');
      return;
    }

    if (school.isEmpty || selectedGrade == null || selectedSubjects.isEmpty) {
      showMessage('Enter your school, grade and at least one subject');
      return;
    }

    setState(() => isSaving = true);

    try {
      final sortedSubjects = selectedSubjects.toList()..sort();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {
          'schoolName': school,
          'gradeLevel': selectedGrade,
          'subjectsNeeded': sortedSubjects,
          'profileUpdatedAt': FieldValue.serverTimestamp(),
        },
      );

      if (!mounted) return;

      setState(() {
        profileComplete = true;
        isEditing = false;
      });

      showMessage('Profile saved successfully!');
    } on FirebaseException catch (e) {
      showMessage(
        e.code == 'permission-denied'
            ? 'Profile update blocked by Firebase rules'
            : 'Unable to save profile',
      );
    } catch (_) {
      showMessage('An unexpected error occurred');
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  InputDecoration fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
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
            fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
        const Center(
          child: Text('Student Profile', style: TextStyle(color: teal)),
        ),
        const SizedBox(height: 24),
        informationTile('Full Name', fullName),
        informationTile('High School', schoolController.text.trim()),
        informationTile('Grade Level', selectedGrade ?? 'Not selected'),
        informationTile('Subjects Needed', displaySubjects.join(', ')),
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
          profileComplete ? 'Update Your Profile' : 'Complete Your Profile',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: teal,
          ),
        ),
        const SizedBox(height: 8),
        Text('Student: $fullName'),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: isSaving ? null : loadProfile,
          icon: const Icon(Icons.refresh, color: teal),
          label: const Text(
            'Refresh Subjects and Grades',
            style: TextStyle(color: teal),
          ),
        ),
        const SizedBox(height: 16),
        const Text('High School Name'),
        const SizedBox(height: 8),
        TextField(
          controller: schoolController,
          decoration: fieldDecoration('Enter your high school name'),
        ),
        const SizedBox(height: 20),
        const Text('Grade Level'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey(selectedGrade),
          initialValue: selectedGrade,
          isExpanded: true,
          decoration: fieldDecoration('Select your grade'),
          items: grades.map((grade) {
            return DropdownMenuItem(value: grade, child: Text(grade));
          }).toList(),
          onChanged: (value) {
            setState(() => selectedGrade = value);
          },
        ),
        const SizedBox(height: 20),
        const Text('Subjects Needed'),
        const SizedBox(height: 6),
        const Text('Select all subjects you need tutoring in.'),
        const SizedBox(height: 8),
        if (subjects.isEmpty) const Text('No subjects are available yet.'),
        ...subjects.map((subject) {
          return CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: teal,
            title: Text(subject),
            value: selectedSubjects.contains(subject),
            onChanged: (checked) {
              setState(() {
                if (checked == true) {
                  selectedSubjects.add(subject);
                } else {
                  selectedSubjects.remove(subject);
                }
              });
            },
          );
        }),
        const SizedBox(height: 12),
        Text(
          '${selectedSubjects.length} subject(s) selected',
          style: const TextStyle(color: teal),
        ),
        const SizedBox(height: 24),
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
    if (isLoadingProfile) {
      return const Center(child: CircularProgressIndicator(color: teal));
    }

    return isEditing ? buildEditProfile() : buildViewProfile();
  }
}
