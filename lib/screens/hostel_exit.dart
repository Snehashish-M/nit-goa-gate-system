import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:nit_goa_gate_app/services/user_cache.dart';

class HostelExit extends StatefulWidget {
  const HostelExit({super.key});

  @override
  State<HostelExit> createState() => _HostelExitState();
}

class _HostelExitState extends State<HostelExit> {

  final destinationController = TextEditingController();

  Map<String, dynamic>? userData;

  String? qrData;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Use cached profile — no Firestore read
    userData = UserCache().profileData;
    if (userData == null) {
      _loadFromFirestore();
    }
  }

  @override
  void dispose() {
    destinationController.dispose();
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

    // Validate destination field
    if (destinationController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a destination")),
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
        "hostel": userData!["hostel"],
        "roomNumber": userData!["roomNumber"],
        "phone": userData!["phone"],

        "destination": destinationController.text,

        "type": "hostel",

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
        title: const Text("Hostel Entry / Exit"),
      ),

      body: userData == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),

              child: ListView(
                children: [

                  TextField(
                    controller: destinationController,
                    decoration: const InputDecoration(
                      labelText: "Destination",
                      prefixIcon: Icon(Icons.location_on),
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
