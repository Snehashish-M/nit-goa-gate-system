import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:nit_goa_gate_app/services/user_cache.dart';

class DayScholar extends StatefulWidget {
  const DayScholar({super.key});

  @override
  State<DayScholar> createState() => _DayScholarState();
}

class _DayScholarState extends State<DayScholar> {

  final placeController = TextEditingController();

  Map<String, dynamic>? userData;

  String? qrData;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Use cached profile — no Firestore read
    userData = UserCache().profileData;
    if (userData == null) {
      // Fallback: load from Firestore if cache is empty
      _loadFromFirestore();
    }
  }

  @override
  void dispose() {
    placeController.dispose();
    super.dispose();
  }

  Future _loadFromFirestore() async {
    var data = await UserCache().loadProfile();
    if (mounted) {
      setState(() {
        userData = data;
      });
    }
  }

  Future generateQR() async {

    if (userData == null) return;

    // Validate place field
    if (placeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter where you are coming from")),
      );
      return;
    }

    User? user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      DocumentReference passRef =
          FirebaseFirestore.instance.collection("gate_passes").doc();

      await passRef.set({

        "studentId": user.uid,

        "name": userData!["name"],
        "rollNumber": userData!["rollNumber"],
        "degree": userData!["degree"],
        "phone": userData!["phone"],

        "comingFrom": placeController.text,

        "type": "day_scholar",

        "status": "active",

        "scanCount": 0,

        "createdAt": Timestamp.now()

      });

      setState(() {
        qrData = passRef.id;
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("QR Code generated successfully")),
        );
      }
    } catch (e) {
      debugPrint("Error generating QR: $e");
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.toString()}")),
        );
      }
    }

  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text("Day Scholar Portal"),
      ),

      body: userData == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),

              child: ListView(
                children: [

                  TextField(
                    controller: placeController,
                    decoration: const InputDecoration(
                      labelText: "Place you are coming from",
                      prefixIcon: Icon(Icons.place),
                    ),
                  ),

                  const SizedBox(height: 30),

                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : generateQR,
                    icon: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.qr_code),
                    label: const Text("Generate QR"),
                  ),

                  const SizedBox(height: 40),

                  if (qrData != null)
                    Center(
                      child: QrImageView(
                        data: qrData!,
                        size: 250,
                      ),
                    ),

                ],
              ),
            ),
    );
  }
}
