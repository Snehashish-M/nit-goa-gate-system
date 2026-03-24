import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';

import 'login_screen.dart';

class WardenDashboard extends StatefulWidget {
  const WardenDashboard({super.key});

  @override
  State<WardenDashboard> createState() => _WardenDashboardState();
}

class _WardenDashboardState extends State<WardenDashboard> {

  List<DocumentSnapshot> _pendingRequests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchPendingRequests();
  }

  Future<void> _fetchPendingRequests() async {
    setState(() {
      _isLoading = true;
    });

    try {
      var snapshot = await FirebaseFirestore.instance
          .collection("leave_requests")
          .where("status", isEqualTo: "pending")
          .get();

      if (mounted) {
        setState(() {
          _pendingRequests = snapshot.docs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching requests: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Builds a CircleAvatar with the student's photo from base64, or a fallback icon
  Widget _buildStudentAvatar(DocumentSnapshot request, {double radius = 25}) {
    String? photoBase64;
    try {
      photoBase64 = request["photo"];
    } catch (_) {}

    Uint8List? photoBytes;
    if (photoBase64 != null && photoBase64.isNotEmpty) {
      try {
        photoBytes = base64Decode(photoBase64);
      } catch (e) {
        debugPrint("Error decoding student photo: $e");
      }
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey[300],
      backgroundImage: photoBytes != null ? MemoryImage(photoBytes) : null,
      child: photoBytes == null
          ? Icon(Icons.person, size: radius, color: Colors.grey)
          : null,
    );
  }

  Future approveRequest(BuildContext context, DocumentSnapshot request) async {

    await FirebaseFirestore.instance
        .collection("leave_requests")
        .doc(request.id)
        .update({
      "status": "approved",
    });

    // Refresh the list after approval
    _fetchPendingRequests();
  }

  Future rejectRequest(BuildContext context, DocumentSnapshot request) async {

    await FirebaseFirestore.instance
        .collection("leave_requests")
        .doc(request.id)
        .update({
      "status": "rejected"
    });

    // Refresh the list after rejection
    _fetchPendingRequests();
  }

  void showApproveConfirmation(BuildContext context, DocumentSnapshot request) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Approval"),
        content: Text("Approve leave for ${request["name"]}?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              approveRequest(context, request);
            },
            child: const Text("Approve"),
          ),
        ],
      ),
    );
  }

  void showRejectConfirmation(BuildContext context, DocumentSnapshot request) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Rejection"),
        content: Text("Reject leave for ${request["name"]}?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              rejectRequest(context, request);
            },
            child: const Text("Reject"),
          ),
        ],
      ),
    );
  }

  void showLeaveDetails(BuildContext context, DocumentSnapshot request) {
    DateTime? leavingDate;
    DateTime? returnDate;

    try {
      if (request["leavingDate"] is Timestamp) {
        leavingDate = (request["leavingDate"] as Timestamp).toDate();
      }
      if (request["returnDate"] is Timestamp) {
        returnDate = (request["returnDate"] as Timestamp).toDate();
      }
    } catch (e) {
      debugPrint("Error parsing dates: $e");
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Leave Application Details"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Student photo
              Center(
                child: _buildStudentAvatar(request, radius: 40),
              ),
              const SizedBox(height: 15),
              Text("Name: ${request["name"]}"),
              Text("Roll Number: ${request["rollNumber"]}"),
              Text("Degree: ${request["degree"]}"),
              Text("Hostel: ${request["hostel"]}"),
              Text("Room: ${request["roomNumber"]}"),
              Text("Phone: ${request["phone"]}"),
              const SizedBox(height: 10),
              if (leavingDate != null)
                Text("Leaving Date: ${DateFormat('yyyy-MM-dd').format(leavingDate)}"),
              if (returnDate != null)
                Text("Return Date: ${DateFormat('yyyy-MM-dd').format(returnDate)}"),
              Text("Duration: ${request["durationDays"]} days"),
              const SizedBox(height: 10),
              Text("Mode of Transport: ${request["modeOfTransport"]}"),
              Text("Purpose: ${request["purpose"]}"),
              Text("Address During Leave: ${request["addressDuringLeave"]}"),
              Text("Parent Phone: ${request["parentPhone"]}"),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text("Warden Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await GoogleSignIn().signOut();
              await FirebaseAuth.instance.signOut();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),

      body: RefreshIndicator(
        onRefresh: _fetchPendingRequests,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _pendingRequests.isEmpty
                ? ListView(
                    // Wrap in ListView so pull-to-refresh works even when empty
                    children: const [
                      SizedBox(height: 200),
                      Center(child: Text("No Pending Requests")),
                      SizedBox(height: 20),
                      Center(
                        child: Text(
                          "Pull down to refresh",
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(

                    itemCount: _pendingRequests.length,

                    itemBuilder: (context, index) {

                      var request = _pendingRequests[index];

                      return GestureDetector(
                        onTap: () => showLeaveDetails(context, request),
                        child: Card(

                          margin: const EdgeInsets.all(10),

                          child: Padding(
                            padding: const EdgeInsets.all(15),

                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,

                              children: [

                                Row(
                                  children: [
                                    _buildStudentAvatar(request, radius: 25),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text("${request["name"]}",
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                          Text("Roll: ${request["rollNumber"]}"),
                                          Text("${request["degree"]} • ${request["hostel"]} - ${request["roomNumber"]}"),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 10),

                                Text("Purpose: ${request["purpose"]}"),

                                const SizedBox(height: 10),

                                Row(

                                  children: [

                                    ElevatedButton(
                                      onPressed: () {
                                        showApproveConfirmation(context, request);
                                      },
                                      child: const Text("Approve"),
                                    ),

                                    const SizedBox(width: 10),

                                    ElevatedButton(
                                      onPressed: () {
                                        showRejectConfirmation(context, request);
                                      },
                                      child: const Text("Reject"),
                                    ),

                                  ],
                                )

                              ],
                            ),
                          ),

                        ),
                      );

                    },

                  ),
      ),

    );
  }
}