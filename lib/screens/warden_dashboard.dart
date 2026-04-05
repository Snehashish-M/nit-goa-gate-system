import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';

import 'login_screen.dart';
import 'package:nit_goa_gate_app/services/user_cache.dart';

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
  List<DocumentSnapshot> _historyRequests = [];
  List<DocumentSnapshot> _extensionHistoryRequests = [];
  bool _isLoadingLeaves = true;
  bool _isLoadingExtensions = true;
  bool _isLoadingHistory = true;
  bool _isLoadingExtHistory = true;
  int _historyToggle = 0; // 0 = Leave, 1 = Extension

  String _leaveSearchQuery = "";
  String _extensionSearchQuery = "";
  String _historySearchQuery = "";
  final _leaveSearchController = TextEditingController();
  final _extensionSearchController = TextEditingController();
  final _historySearchController = TextEditingController();

  String? _selectedHostel;
  final List<String> _hostels = ["Talpona Hostel", "Terekhol Hostel"];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSavedHostel();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _leaveSearchController.dispose();
    _extensionSearchController.dispose();
    _historySearchController.dispose();
    super.dispose();
  }

  // ─── Load saved hostel preference ───

  Future<void> _loadSavedHostel() async {
    // Use cached profile data instead of a separate Firestore read
    var cachedData = UserCache().profileData;

    if (cachedData != null && cachedData.containsKey("wardenHostel")) {
      String saved = cachedData["wardenHostel"];
      if (_hostels.contains(saved)) {
        setState(() => _selectedHostel = saved);
        _fetchPendingRequests();
        _fetchExtensionRequests();
        _fetchHistory();
        _fetchExtensionHistory();
        _cleanupOldHistory(); // Delete entries older than 7 days from Firebase
        return;
      }
    }

    // No saved preference — just show the dropdown
    setState(() {
      _isLoadingLeaves = false;
      _isLoadingExtensions = false;
      _isLoadingHistory = false;
      _isLoadingExtHistory = false;
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
    _fetchHistory();
    _fetchExtensionHistory();
    _cleanupOldHistory();
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
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.5,
                      ),
                      child: Image.memory(
                        photoBytes!,
                        fit: BoxFit.contain,
                        width: double.infinity,
                      ),
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

  // ─── Helpers ───

  String? _safeGet(DocumentSnapshot doc, String field) {
    try {
      return doc[field]?.toString();
    } catch (_) {
      return null;
    }
  }

  // ─── Save to leave_history collection ───

  Future<void> _saveToHistory({
    required String type, // "leave" or "extension"
    required String status, // "approved" or "rejected"
    required String actionBy,
    required Timestamp actionAt,
    required DocumentSnapshot request,
    String? rejectionReason,
    String? extensionReason,
    Timestamp? extensionNewReturnDate,
  }) async {
    try {
      Map<String, dynamic> historyData = {
        "type": type,
        "status": status,
        "actionBy": actionBy,
        "actionAt": actionAt,
        "name": _safeGet(request, "name") ?? "",
        "rollNumber": _safeGet(request, "rollNumber") ?? "",
        "degree": _safeGet(request, "degree") ?? "",
        "hostel": _safeGet(request, "hostel") ?? "",
        "roomNumber": _safeGet(request, "roomNumber") ?? "",
        "phone": _safeGet(request, "phone") ?? "",
        "purpose": _safeGet(request, "purpose") ?? "",
        "modeOfTransport": _safeGet(request, "modeOfTransport") ?? "",
        "addressDuringLeave": _safeGet(request, "addressDuringLeave") ?? "",
        "parentPhone": _safeGet(request, "parentPhone") ?? "",
      };

      // Dates
      try { historyData["leavingDate"] = request["leavingDate"]; } catch (_) {}
      try { historyData["returnDate"] = request["returnDate"]; } catch (_) {}
      try { historyData["durationDays"] = request["durationDays"]; } catch (_) {}

      // Photo — save for avatar display
      try { historyData["photo"] = request["photo"]; } catch (_) {}

      if (rejectionReason != null && rejectionReason.trim().isNotEmpty) {
        historyData["rejectionReason"] = rejectionReason.trim();
      }
      if (extensionReason != null) {
        historyData["extensionReason"] = extensionReason;
      }
      if (extensionNewReturnDate != null) {
        historyData["extensionNewReturnDate"] = extensionNewReturnDate;
      }

      await FirebaseFirestore.instance
          .collection("leave_history")
          .add(historyData);
    } catch (e) {
      debugPrint("Error saving to history: $e");
    }
  }

  // ─── Leave request approve / reject ───

  Future approveRequest(BuildContext context, DocumentSnapshot request) async {
    String wardenName = FirebaseAuth.instance.currentUser?.displayName ?? "Warden";
    Timestamp now = Timestamp.now();
    await FirebaseFirestore.instance
        .collection("leave_requests")
        .doc(request.id)
        .update({
      "status": "approved",
      "approvedBy": wardenName,
      "approvedAt": now,
    });

    // Save to history collection
    await _saveToHistory(
      type: "leave",
      status: "approved",
      actionBy: wardenName,
      actionAt: now,
      request: request,
    );

    _fetchPendingRequests();
    _fetchHistory();
  }

  Future rejectRequest(BuildContext context, DocumentSnapshot request, {String? reason}) async {
    String wardenName = FirebaseAuth.instance.currentUser?.displayName ?? "Warden";
    Timestamp now = Timestamp.now();
    Map<String, dynamic> updateData = {
      "status": "rejected",
      "rejectedAt": now,
      "rejectedBy": wardenName,
    };
    if (reason != null && reason.trim().isNotEmpty) {
      updateData["rejectionReason"] = reason.trim();
    }

    await FirebaseFirestore.instance
        .collection("leave_requests")
        .doc(request.id)
        .update(updateData);

    // Save to history collection
    await _saveToHistory(
      type: "leave",
      status: "rejected",
      actionBy: wardenName,
      actionAt: now,
      request: request,
      rejectionReason: reason,
    );

    _fetchPendingRequests();
    _fetchHistory();
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
      String wardenName = FirebaseAuth.instance.currentUser?.displayName ?? "Warden";
      Timestamp now = Timestamp.now();
      Timestamp newReturnDate = extRequest["extensionNewReturnDate"];
      Timestamp leavingDateTs = extRequest["leavingDate"];
      DateTime leavingDate = leavingDateTs.toDate();
      DateTime newReturn = newReturnDate.toDate();
      int newDuration = newReturn.difference(leavingDate).inDays + 1;

      await FirebaseFirestore.instance
          .collection("leave_requests")
          .doc(extRequest.id)
          .update({
        "returnDate": newReturnDate,
        "durationDays": newDuration,
        "extended": true,
        "extensionStatus": "approved",
        "extensionApprovedBy": wardenName,
        "extensionApprovedAt": now,
      });

      // Save to history collection
      await _saveToHistory(
        type: "extension",
        status: "approved",
        actionBy: wardenName,
        actionAt: now,
        request: extRequest,
        extensionReason: _safeGet(extRequest, "extensionReason"),
        extensionNewReturnDate: newReturnDate,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Extension approved")),
        );
      }

      _fetchExtensionRequests();
      _fetchExtensionHistory();
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
      String wardenName = FirebaseAuth.instance.currentUser?.displayName ?? "Warden";
      Timestamp now = Timestamp.now();
      await FirebaseFirestore.instance
          .collection("leave_requests")
          .doc(extRequest.id)
          .update({
        "extensionStatus": "rejected",
        "extensionRejectedBy": wardenName,
        "extensionRejectedAt": now,
      });

      // Save to history collection
      await _saveToHistory(
        type: "extension",
        status: "rejected",
        actionBy: wardenName,
        actionAt: now,
        request: extRequest,
        extensionReason: _safeGet(extRequest, "extensionReason"),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Extension rejected")),
        );
      }

      _fetchExtensionRequests();
      _fetchExtensionHistory();
    } catch (e) {
      debugPrint("Error rejecting extension: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.toString()}")),
        );
      }
    }
  }

  // ─── Badge helper ───

  Widget _buildBadgedIcon(IconData iconData, int count) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(iconData),
        if (count > 0)
          Positioned(
            right: -8,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(
                minWidth: 18,
                minHeight: 18,
              ),
              child: Center(
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
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
                      color: Colors.blueGrey,
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
              final shouldLogout = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("Confirm Logout"),
                  content: const Text("Are you sure you want to log out?"),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text("Cancel"),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text("Log Out"),
                    ),
                  ],
                ),
              );

              if (shouldLogout != true) return;

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
          tabs: [
            Tab(
              icon: _buildBadgedIcon(Icons.description, _pendingRequests.length),
              text: "Leave Requests",
            ),
            Tab(
              icon: _buildBadgedIcon(Icons.date_range, _extensionRequests.length),
              text: "Extensions",
            ),
            const Tab(
              icon: Icon(Icons.history),
              text: "History",
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
          // Tab 3: History
          _buildHistoryTab(),
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

  // ─── Cleanup: delete history older than 7 days from Firebase ───

  Future<void> _cleanupOldHistory() async {
    try {
      DateTime oneWeekAgo = DateTime.now().subtract(const Duration(days: 7));

      var snapshot = await FirebaseFirestore.instance
          .collection("leave_history")
          .get();

      WriteBatch batch = FirebaseFirestore.instance.batch();
      int deleteCount = 0;

      for (var doc in snapshot.docs) {
        try {
          Timestamp actionAt = doc["actionAt"];
          if (actionAt.toDate().isBefore(oneWeekAgo)) {
            batch.delete(doc.reference);
            deleteCount++;
          }
        } catch (_) {
          // If no actionAt field, delete the doc (malformed)
          batch.delete(doc.reference);
          deleteCount++;
        }
      }

      if (deleteCount > 0) {
        await batch.commit();
        debugPrint("Cleaned up $deleteCount old history entries");
      }
    } catch (e) {
      debugPrint("Error cleaning up old history: $e");
    }
  }

  // ─── Fetch leave history (last 7 days) ───

  Future<void> _fetchHistory() async {
    setState(() => _isLoadingHistory = true);

    try {
      DateTime oneWeekAgo = DateTime.now().subtract(const Duration(days: 7));

      var query = FirebaseFirestore.instance
          .collection("leave_history")
          .where("type", isEqualTo: "leave");

      if (_selectedHostel != null) {
        query = query.where("hostel", isEqualTo: _selectedHostel);
      }

      var snapshot = await query.get();

      // Client-side: filter by last 7 days and sort
      var filtered = snapshot.docs.where((doc) {
        try {
          Timestamp actionAt = doc["actionAt"];
          return actionAt.toDate().isAfter(oneWeekAgo);
        } catch (_) {
          return false;
        }
      }).toList();

      filtered.sort((a, b) {
        try {
          Timestamp aTime = a["actionAt"];
          Timestamp bTime = b["actionAt"];
          return bTime.compareTo(aTime);
        } catch (_) {
          return 0;
        }
      });

      if (mounted) {
        setState(() {
          _historyRequests = filtered;
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching history: $e");
      if (mounted) {
        setState(() => _isLoadingHistory = false);
      }
    }
  }

  // ─── Fetch extension history (last 7 days) ───

  Future<void> _fetchExtensionHistory() async {
    setState(() => _isLoadingExtHistory = true);

    try {
      DateTime oneWeekAgo = DateTime.now().subtract(const Duration(days: 7));

      var query = FirebaseFirestore.instance
          .collection("leave_history")
          .where("type", isEqualTo: "extension");

      if (_selectedHostel != null) {
        query = query.where("hostel", isEqualTo: _selectedHostel);
      }

      var snapshot = await query.get();

      // Client-side: filter by last 7 days and sort
      var filtered = snapshot.docs.where((doc) {
        try {
          Timestamp actionAt = doc["actionAt"];
          return actionAt.toDate().isAfter(oneWeekAgo);
        } catch (_) {
          return false;
        }
      }).toList();

      filtered.sort((a, b) {
        try {
          Timestamp aTime = a["actionAt"];
          Timestamp bTime = b["actionAt"];
          return bTime.compareTo(aTime);
        } catch (_) {
          return 0;
        }
      });

      if (mounted) {
        setState(() {
          _extensionHistoryRequests = filtered;
          _isLoadingExtHistory = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching extension history: $e");
      if (mounted) {
        setState(() => _isLoadingExtHistory = false);
      }
    }
  }

  // ─── Show history details dialog ───

  void showHistoryDetails(BuildContext context, DocumentSnapshot historyDoc) {
    DateTime? leavingDate;
    DateTime? returnDate;

    try {
      if (historyDoc["leavingDate"] is Timestamp) {
        leavingDate = (historyDoc["leavingDate"] as Timestamp).toDate();
      }
      if (historyDoc["returnDate"] is Timestamp) {
        returnDate = (historyDoc["returnDate"] as Timestamp).toDate();
      }
    } catch (_) {}

    String status = historyDoc["status"] ?? "";
    String type = historyDoc["type"] ?? "leave";
    String actionBy = historyDoc["actionBy"] ?? "";
    String statusLabel = status == "approved" ? "Approved" : "Rejected";
    Color statusColor = status == "approved" ? Colors.green : Colors.red;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(type == "extension" ? "Extension Details" : "Leave Application Details"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Student photo
              Center(
                child: _buildStudentAvatarFromDoc(historyDoc, radius: 40),
              ),
              const SizedBox(height: 15),
              Text("Name: ${historyDoc["name"]}"),
              Text("Roll Number: ${historyDoc["rollNumber"]}"),
              Text("Degree: ${historyDoc["degree"]}"),
              Text("Hostel: ${historyDoc["hostel"]}"),
              Text("Room: ${historyDoc["roomNumber"]}"),
              Text("Phone: ${historyDoc["phone"]}"),
              const SizedBox(height: 10),
              if (leavingDate != null)
                Text("Leaving Date: ${DateFormat('yyyy-MM-dd').format(leavingDate)}"),
              if (returnDate != null)
                Text("Return Date: ${DateFormat('yyyy-MM-dd').format(returnDate)}"),
              if (historyDoc.data() != null && (historyDoc.data() as Map).containsKey("durationDays"))
                Text("Duration: ${historyDoc["durationDays"]} days"),
              const SizedBox(height: 10),
              Text("Mode of Transport: ${historyDoc["modeOfTransport"]}"),
              Text("Purpose: ${historyDoc["purpose"]}"),
              Text("Address During Leave: ${historyDoc["addressDuringLeave"]}"),
              Text("Parent Phone: ${historyDoc["parentPhone"]}"),
              const SizedBox(height: 10),

              // Status & warden
              Text(
                "$statusLabel by: $actionBy",
                style: TextStyle(fontWeight: FontWeight.bold, color: statusColor),
              ),

              // Extension specific
              if (type == "extension") ...[
                Builder(builder: (context) {
                  String? extReason;
                  try { extReason = historyDoc["extensionReason"]; } catch (_) {}
                  if (extReason != null && extReason.isNotEmpty) {
                    return Text("Extension Reason: $extReason");
                  }
                  return const SizedBox.shrink();
                }),
                Builder(builder: (context) {
                  try {
                    Timestamp? newDate = historyDoc["extensionNewReturnDate"];
                    if (newDate != null) {
                      return Text("New Return Date: ${DateFormat('yyyy-MM-dd').format(newDate.toDate())}");
                    }
                  } catch (_) {}
                  return const SizedBox.shrink();
                }),
              ],

              // Rejection reason
              Builder(builder: (context) {
                String? rejReason;
                try { rejReason = historyDoc["rejectionReason"]; } catch (_) {}
                if (rejReason != null && rejReason.isNotEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      "Rejection Reason: $rejReason",
                      style: const TextStyle(color: Colors.red, fontStyle: FontStyle.italic),
                    ),
                  );
                }
                return const SizedBox.shrink();
              }),
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

  // ─── Tab 3: History with Toggle ───

  Widget _buildHistoryTab() {
    return Column(
      children: [
        // Toggle between Leave and Extension history
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _historyToggle = 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _historyToggle == 0 ? const Color(0xFF0D1B2A) : Colors.grey.shade200,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(10),
                        bottomLeft: Radius.circular(10),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        "Leave History",
                        style: TextStyle(
                          color: _historyToggle == 0 ? Colors.white : Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _historyToggle = 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _historyToggle == 1 ? const Color(0xFF0D1B2A) : Colors.grey.shade200,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(10),
                        bottomRight: Radius.circular(10),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        "Extension History",
                        style: TextStyle(
                          color: _historyToggle == 1 ? Colors.white : Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _historyToggle == 0
              ? _buildLeaveHistoryList()
              : _buildExtensionHistoryList(),
        ),
      ],
    );
  }

  Widget _buildLeaveHistoryList() {
    List<DocumentSnapshot> filtered = _historyRequests;
    if (_historySearchQuery.isNotEmpty) {
      filtered = _historyRequests.where((req) {
        String name = (req["name"] ?? "").toString().toLowerCase();
        String roll = (req["rollNumber"] ?? "").toString().toLowerCase();
        String query = _historySearchQuery.toLowerCase();
        return name.contains(query) || roll.contains(query);
      }).toList();
    }

    return RefreshIndicator(
      onRefresh: _fetchHistory,
      child: _isLoadingHistory
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: TextField(
                    controller: _historySearchController,
                    decoration: InputDecoration(
                      hintText: "Search by name or roll number",
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _historySearchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _historySearchController.clear();
                                setState(() => _historySearchQuery = "");
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: (value) {
                      setState(() => _historySearchQuery = value);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    "Last 7 days \u2022 ${filtered.length} entries",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 100),
                            Center(child: Text("No leave history")),
                            SizedBox(height: 10),
                            Center(child: Text("Pull down to refresh", style: TextStyle(color: Colors.grey, fontSize: 13))),
                          ],
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            var request = filtered[index];
                            String status = request["status"] ?? "";
                            String name = request["name"] ?? "";
                            String roll = request["rollNumber"] ?? "";
                            String purpose = request["purpose"] ?? "";

                            String? actionBy;
                            DateTime? actionTime;
                            try {
                              actionBy = request["actionBy"];
                              actionTime = (request["actionAt"] as Timestamp).toDate();
                            } catch (_) {}

                            Color statusColor = status == "approved" ? Colors.green : Colors.red;
                            String statusText = status == "approved" ? "Approved" : "Rejected";

                            return _buildHistoryCard(
                              name: name,
                              roll: roll,
                              subtitle: "Purpose: $purpose",
                              actionBy: actionBy,
                              actionTime: actionTime,
                              statusColor: statusColor,
                              statusText: statusText,
                              request: request,
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildExtensionHistoryList() {
    List<DocumentSnapshot> filtered = _extensionHistoryRequests;
    if (_historySearchQuery.isNotEmpty) {
      filtered = _extensionHistoryRequests.where((req) {
        String name = (req["name"] ?? "").toString().toLowerCase();
        String roll = (req["rollNumber"] ?? "").toString().toLowerCase();
        String query = _historySearchQuery.toLowerCase();
        return name.contains(query) || roll.contains(query);
      }).toList();
    }

    return RefreshIndicator(
      onRefresh: _fetchExtensionHistory,
      child: _isLoadingExtHistory
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: TextField(
                    controller: _historySearchController,
                    decoration: InputDecoration(
                      hintText: "Search by name or roll number",
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _historySearchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _historySearchController.clear();
                                setState(() => _historySearchQuery = "");
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: (value) {
                      setState(() => _historySearchQuery = value);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    "Last 7 days \u2022 ${filtered.length} entries",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 100),
                            Center(child: Text("No extension history")),
                            SizedBox(height: 10),
                            Center(child: Text("Pull down to refresh", style: TextStyle(color: Colors.grey, fontSize: 13))),
                          ],
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            var request = filtered[index];
                            String status = request["status"] ?? "";
                            String name = request["name"] ?? "";
                            String roll = request["rollNumber"] ?? "";
                            String reason = "";
                            try { reason = request["extensionReason"] ?? ""; } catch (_) {}

                            String? actionBy;
                            DateTime? actionTime;
                            try {
                              actionBy = request["actionBy"];
                              actionTime = (request["actionAt"] as Timestamp).toDate();
                            } catch (_) {}

                            Color statusColor = status == "approved" ? Colors.green : Colors.red;
                            String statusText = status == "approved" ? "Approved" : "Rejected";

                            return _buildHistoryCard(
                              name: name,
                              roll: roll,
                              subtitle: "Reason: $reason",
                              actionBy: actionBy,
                              actionTime: actionTime,
                              statusColor: statusColor,
                              statusText: statusText,
                              request: request,
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  // ─── Shared history card widget ───

  Widget _buildHistoryCard({
    required String name,
    required String roll,
    required String subtitle,
    String? actionBy,
    DateTime? actionTime,
    required Color statusColor,
    required String statusText,
    required DocumentSnapshot request,
  }) {
    return GestureDetector(
      onTap: () => showHistoryDetails(context, request),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildStudentAvatarFromDoc(request, radius: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        Text("Roll: $roll", style: const TextStyle(fontSize: 13, color: Colors.grey)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      border: Border.all(color: statusColor),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(subtitle, style: const TextStyle(fontSize: 13)),
              if (actionBy != null) ...[
                const SizedBox(height: 4),
                Text(
                  "$statusText by: $actionBy",
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: statusColor),
                ),
              ],
              if (actionTime != null) ...[
                const SizedBox(height: 2),
                Text(
                  DateFormat('dd MMM yyyy, hh:mm a').format(actionTime),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
