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

class _WardenDashboardState extends State<WardenDashboard>
    with SingleTickerProviderStateMixin {

  late TabController _tabController;

  List<DocumentSnapshot> _pendingRequests = [];
  List<DocumentSnapshot> _extensionRequests = [];
  bool _isLoadingLeaves = true;
  bool _isLoadingExtensions = true;

  String _leaveSearchQuery = "";
  String _extensionSearchQuery = "";
  final _leaveSearchController = TextEditingController();
  final _extensionSearchController = TextEditingController();

  String? _selectedHostel;
  final List<String> _hostels = ["Talpona Hostel", "Terekhol Hostel"];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSavedHostel();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _leaveSearchController.dispose();
    _extensionSearchController.dispose();
    super.dispose();
  }

  // ─── Load saved hostel preference ───

  Future<void> _loadSavedHostel() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      var doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .get();

      if (doc.exists && doc.data()!.containsKey("wardenHostel")) {
        String saved = doc["wardenHostel"];
        if (_hostels.contains(saved)) {
          setState(() => _selectedHostel = saved);
          _fetchPendingRequests();
          _fetchExtensionRequests();
          return;
        }
      }
    } catch (e) {
      debugPrint("Error loading saved hostel: $e");
    }

    // No saved preference — just show the dropdown
    setState(() {
      _isLoadingLeaves = false;
      _isLoadingExtensions = false;
    });
  }

  void _onHostelChanged(String? hostel) async {
    if (hostel == null) return;
    setState(() => _selectedHostel = hostel);

    // Save to Firestore
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .update({"wardenHostel": hostel});
    }

    _fetchPendingRequests();
    _fetchExtensionRequests();
  }

  // ─── Fetch leave requests ───

  Future<void> _fetchPendingRequests() async {
    setState(() {
      _isLoadingLeaves = true;
    });

    try {
      var query = FirebaseFirestore.instance
          .collection("leave_requests")
          .where("status", isEqualTo: "pending");

      if (_selectedHostel != null) {
        query = query.where("hostel", isEqualTo: _selectedHostel);
      }

      var snapshot = await query.get();

      if (mounted) {
        setState(() {
          _pendingRequests = snapshot.docs;
          _isLoadingLeaves = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching requests: $e");
      if (mounted) {
        setState(() {
          _isLoadingLeaves = false;
        });
      }
    }
  }

  // ─── Fetch extension requests ───

  Future<void> _fetchExtensionRequests() async {
    setState(() {
      _isLoadingExtensions = true;
    });

    try {
      var query = FirebaseFirestore.instance
          .collection("leave_requests")
          .where("extensionStatus", isEqualTo: "pending");

      if (_selectedHostel != null) {
        query = query.where("hostel", isEqualTo: _selectedHostel);
      }

      var snapshot = await query.get();

      if (mounted) {
        setState(() {
          _extensionRequests = snapshot.docs;
          _isLoadingExtensions = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching extension requests: $e");
      if (mounted) {
        setState(() {
          _isLoadingExtensions = false;
        });
      }
    }
  }

  // ─── Helpers ───

  Widget _buildStudentAvatar(String? photoBase64, {double radius = 25}) {
    Uint8List? photoBytes;
    if (photoBase64 != null && photoBase64.isNotEmpty) {
      try {
        photoBytes = base64Decode(photoBase64);
      } catch (e) {
        debugPrint("Error decoding student photo: $e");
      }
    }

    Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey[300],
      backgroundImage: photoBytes != null ? MemoryImage(photoBytes) : null,
      child: photoBytes == null
          ? Icon(Icons.person, size: radius, color: Colors.grey)
          : null,
    );

    if (photoBytes != null) {
      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  title: const Text("Student Photo"),
                ),
                body: Center(
                  child: InteractiveViewer(
                    child: Image.memory(
                      photoBytes!,
                      fit: BoxFit.contain,
                      width: double.infinity,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        child: avatar,
      );
    }

    return avatar;
  }

  Widget _buildStudentAvatarFromDoc(DocumentSnapshot request, {double radius = 25}) {
    String? photoBase64;
    try {
      photoBase64 = request["photo"];
    } catch (_) {}
    return _buildStudentAvatar(photoBase64, radius: radius);
  }

  // ─── Leave request approve / reject ───

  Future approveRequest(BuildContext context, DocumentSnapshot request) async {
    await FirebaseFirestore.instance
        .collection("leave_requests")
        .doc(request.id)
        .update({
      "status": "approved",
    });

    _fetchPendingRequests();
  }

  Future rejectRequest(BuildContext context, DocumentSnapshot request, {String? reason}) async {
    Map<String, dynamic> updateData = {
      "status": "rejected",
      "rejectedAt": Timestamp.now(),
    };
    if (reason != null && reason.trim().isNotEmpty) {
      updateData["rejectionReason"] = reason.trim();
    }

    await FirebaseFirestore.instance
        .collection("leave_requests")
        .doc(request.id)
        .update(updateData);

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
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Rejection"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Reject leave for ${request["name"]}?"),
            const SizedBox(height: 15),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: "Reason (optional)",
                prefixIcon: Icon(Icons.edit_note),
                hintText: "Enter reason for rejection",
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              rejectRequest(context, request, reason: reasonController.text);
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
                child: _buildStudentAvatarFromDoc(request, radius: 40),
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

  // ─── Extension approve / reject ───

  void showExtensionApproveConfirmation(BuildContext context, DocumentSnapshot extRequest) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Extension Approval"),
        content: Text("Approve extension for ${extRequest["name"]}?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _approveExtension(extRequest);
            },
            child: const Text("Approve"),
          ),
        ],
      ),
    );
  }

  void showExtensionRejectConfirmation(BuildContext context, DocumentSnapshot extRequest) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Extension Rejection"),
        content: Text("Reject extension for ${extRequest["name"]}?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _rejectExtension(extRequest);
            },
            child: const Text("Reject"),
          ),
        ],
      ),
    );
  }

  Future _approveExtension(DocumentSnapshot extRequest) async {
    try {
      Timestamp newReturnDate = extRequest["extensionNewReturnDate"];
      Timestamp leavingDateTs = extRequest["leavingDate"];
      DateTime leavingDate = leavingDateTs.toDate();
      DateTime newReturn = newReturnDate.toDate();
      int newDuration = newReturn.difference(leavingDate).inDays + 1;

      // Update the same leave request doc
      await FirebaseFirestore.instance
          .collection("leave_requests")
          .doc(extRequest.id)
          .update({
        "returnDate": newReturnDate,
        "durationDays": newDuration,
        "extended": true,
        "extensionStatus": "approved",
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Extension approved")),
        );
      }

      _fetchExtensionRequests();
    } catch (e) {
      debugPrint("Error approving extension: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.toString()}")),
        );
      }
    }
  }

  Future _rejectExtension(DocumentSnapshot extRequest) async {
    try {
      // Update extension status on the same leave request doc
      await FirebaseFirestore.instance
          .collection("leave_requests")
          .doc(extRequest.id)
          .update({"extensionStatus": "rejected"});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Extension rejected")),
        );
      }

      _fetchExtensionRequests();
    } catch (e) {
      debugPrint("Error rejecting extension: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.toString()}")),
        );
      }
    }
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: Text(_selectedHostel ?? "Warden Dashboard"),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.apartment),
            tooltip: "Select Hostel",
            onSelected: _onHostelChanged,
            itemBuilder: (context) => _hostels.map((hostel) {
              return PopupMenuItem<String>(
                value: hostel,
                child: Row(
                  children: [
                    Icon(
                      _selectedHostel == hostel
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(hostel),
                  ],
                ),
              );
            }).toList(),
          ),
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
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(Icons.description),
              text: "Leave Requests",
            ),
            Tab(
              icon: Icon(Icons.date_range),
              text: "Extensions",
            ),
          ],
        ),
      ),

      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Leave Requests
          _buildLeaveRequestsTab(),
          // Tab 2: Extension Requests
          _buildExtensionRequestsTab(),
        ],
      ),

    );
  }

  // ─── Tab 1: Leave Requests ───

  Widget _buildLeaveRequestsTab() {
    // Filter based on search query
    List<DocumentSnapshot> filtered = _pendingRequests;
    if (_leaveSearchQuery.isNotEmpty) {
      filtered = _pendingRequests.where((req) {
        String name = (req["name"] ?? "").toString().toLowerCase();
        String roll = (req["rollNumber"] ?? "").toString().toLowerCase();
        String query = _leaveSearchQuery.toLowerCase();
        return name.contains(query) || roll.contains(query);
      }).toList();
    }

    return RefreshIndicator(
      onRefresh: _fetchPendingRequests,
      child: _isLoadingLeaves
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: TextField(
                    controller: _leaveSearchController,
                    decoration: InputDecoration(
                      hintText: "Search by name or roll number",
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _leaveSearchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _leaveSearchController.clear();
                                setState(() => _leaveSearchQuery = "");
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: (value) {
                      setState(() => _leaveSearchQuery = value);
                    },
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 150),
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

                          itemCount: filtered.length,

                          itemBuilder: (context, index) {

                            var request = filtered[index];

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
                                          _buildStudentAvatarFromDoc(request, radius: 25),
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
              ],
            ),
    );
  }

  // ─── Tab 2: Extension Requests ───

  Widget _buildExtensionRequestsTab() {
    // Filter based on search query
    List<DocumentSnapshot> filtered = _extensionRequests;
    if (_extensionSearchQuery.isNotEmpty) {
      filtered = _extensionRequests.where((req) {
        String name = (req["name"] ?? "").toString().toLowerCase();
        String roll = (req["rollNumber"] ?? "").toString().toLowerCase();
        String query = _extensionSearchQuery.toLowerCase();
        return name.contains(query) || roll.contains(query);
      }).toList();
    }

    return RefreshIndicator(
      onRefresh: _fetchExtensionRequests,
      child: _isLoadingExtensions
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: TextField(
                    controller: _extensionSearchController,
                    decoration: InputDecoration(
                      hintText: "Search by name or roll number",
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _extensionSearchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _extensionSearchController.clear();
                                setState(() => _extensionSearchQuery = "");
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: (value) {
                      setState(() => _extensionSearchQuery = value);
                    },
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 150),
                            Center(child: Text("No Pending Extension Requests")),
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

                          itemCount: filtered.length,

                          itemBuilder: (context, index) {

                            var extRequest = filtered[index];

                            DateTime? currentReturnDate;
                            DateTime? newReturnDate;

                            try {
                              if (extRequest["returnDate"] is Timestamp) {
                                currentReturnDate = (extRequest["returnDate"] as Timestamp).toDate();
                              }
                              if (extRequest["extensionNewReturnDate"] is Timestamp) {
                                newReturnDate = (extRequest["extensionNewReturnDate"] as Timestamp).toDate();
                              }
                            } catch (e) {
                              debugPrint("Error parsing extension dates: $e");
                            }

                            String? photoBase64;
                            try {
                              photoBase64 = extRequest["photo"];
                            } catch (_) {}

                            return Card(

                              margin: const EdgeInsets.all(10),

                              child: Padding(
                                padding: const EdgeInsets.all(15),

                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,

                                  children: [

                                    Row(
                                      children: [
                                        _buildStudentAvatar(photoBase64, radius: 25),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "${extRequest["name"]}",
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              Text("Roll: ${extRequest["rollNumber"]}"),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 12),

                                    if (currentReturnDate != null)
                                      Text(
                                        "Current Return: ${DateFormat('yyyy-MM-dd').format(currentReturnDate)}",
                                        style: const TextStyle(fontSize: 14),
                                      ),

                                    if (newReturnDate != null)
                                      Text(
                                        "Requested Return: ${DateFormat('yyyy-MM-dd').format(newReturnDate)}",
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue,
                                        ),
                                      ),

                                    const SizedBox(height: 8),

                                    Text(
                                      "Reason: ${extRequest["extensionReason"]}",
                                      style: const TextStyle(fontSize: 14),
                                    ),

                                    const SizedBox(height: 12),

                                    Row(
                                      children: [

                                        ElevatedButton(
                                          onPressed: () {
                                            showExtensionApproveConfirmation(context, extRequest);
                                          },
                                          child: const Text("Approve"),
                                        ),

                                        const SizedBox(width: 10),

                                        ElevatedButton(
                                          onPressed: () {
                                            showExtensionRejectConfirmation(context, extRequest);
                                          },
                                          child: const Text("Reject"),
                                        ),

                                      ],
                                    ),

                                  ],
                                ),
                              ),

                            );

                          },

                        ),
                ),
              ],
            ),
    );
  }
}