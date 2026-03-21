import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:nit_goa_gate_app/services/user_cache.dart';
import 'package:nit_goa_gate_app/screens/login_screen.dart';
import 'package:nit_goa_gate_app/screens/student_dashboard.dart';
import 'package:nit_goa_gate_app/screens/warden_dashboard.dart';
import 'package:nit_goa_gate_app/screens/profile_setup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'NIT Goa Gate System',
      debugShowCheckedModeBanner: false,
      home: AuthGate(),
    );
  }
}

/// Checks if user is already signed in and routes accordingly.
/// If signed in → dashboard. If not → login screen.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAuthState();
  }

  Future<void> _checkAuthState() async {
    User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      // Single Firestore read — cached for all subsequent screens
      var data = await UserCache().loadProfile(forceRefresh: true);

      if (!mounted) return;

      if (data == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      String role = data["role"] ?? "student";

      if (role == "warden") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const WardenDashboard()),
        );
      } else {
        bool hasRollNumber = data["rollNumber"] != null &&
            (data["rollNumber"] as String).isNotEmpty;
        bool hasDegree = data["degree"] != null &&
            (data["degree"] as String).isNotEmpty;
        bool hasHostel = data["hostel"] != null &&
            (data["hostel"] as String).isNotEmpty;
        bool isDayScholar = data["hostel"] == "Day Scholar";
        bool hasRoomNumber = isDayScholar || (data["roomNumber"] != null &&
            (data["roomNumber"] as String).isNotEmpty);
        bool hasPhone = data["phone"] != null &&
            (data["phone"] as String).isNotEmpty;

        bool isProfileComplete = hasRollNumber && hasDegree && hasHostel &&
            hasRoomNumber && hasPhone;

        if (isProfileComplete) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const StudentDashboard()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const ProfileSetup(isFirstTime: true),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Auth gate error: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return const LoginScreen();
  }
}
