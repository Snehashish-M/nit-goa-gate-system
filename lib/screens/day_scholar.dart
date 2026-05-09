import 'dart:async';
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
  StreamSubscription? _passListener;

  @override
  void initState() {
    super.initState();
    // Use cached profile — no Firestore read
    userData = UserCache().profileData;
    if (userData == null) {
      // Fallback: load from Firestore if cache is empty
      _loadFromFirestore();
    }
    _loadExistingPass();
  }

  @override
  void dispose() {
    _passListener?.cancel();
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

  /// Check if there's already an active day scholar gate pass for this user
  Future _loadExistingPass() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      var snapshot = await FirebaseFirestore.instance
          .collection("gate_passes")
          .where("studentId", isEqualTo: user.uid)
          .where("type", isEqualTo: "day_scholar")
          .where("status", isEqualTo: "active")
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty && mounted) {
        var doc = snapshot.docs.first;
        // Delete passes from previous days — clears at midnight
        var createdAt = doc["createdAt"] as Timestamp?;
        if (createdAt != null) {
          var now = DateTime.now();
          var todayMidnight = DateTime(now.year, now.month, now.day);
          if (createdAt.toDate().isBefore(todayMidnight)) {
            doc.reference.delete();
            return;
          }
        }
        setState(() {
          qrData = doc.id;
        });
        _watchPass(doc.id);
      }
    } catch (e) {
      debugPrint("Error loading existing pass: $e");
    }
  }

  Future generateQR() async {

    if (userData == null) return;

    // Prevent generating a new QR if one is already active
    if (qrData != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You already have an active QR code.")),
      );
      return;
    }

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

      _watchPass(passRef.id);

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

  /// Watches the gate pass document — if it gets deleted, hide the QR
  void _watchPass(String passId) {
    _passListener?.cancel();
    _passListener = FirebaseFirestore.instance
        .collection("gate_passes")
        .doc(passId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists && mounted) {
        setState(() {
          qrData = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Gate pass used. QR code removed.")),
        );
      }
    });
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
                        embeddedImage: const AssetImage('assets/images/logo.png'),
                        embeddedImageStyle: const QrEmbeddedImageStyle(
                          size: Size(40, 40),
                        ),
                      ),
                    ),

                ],
              ),
            ),
    );
  }
}
