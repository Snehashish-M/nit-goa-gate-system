import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'package:nit_goa_gate_app/services/user_cache.dart';

import 'login_screen.dart';

class VehicleAuthorityDashboard extends StatefulWidget {
  const VehicleAuthorityDashboard({super.key});

  @override
  State<VehicleAuthorityDashboard> createState() => _VehicleAuthorityDashboardState();
}

class _VehicleAuthorityDashboardState extends State<VehicleAuthorityDashboard> {

  List<DocumentSnapshot> _pendingRequests = [];
  bool _isLoading = true;
  String _searchQuery = "";
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchPendingRequests();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchPendingRequests() async {
    setState(() => _isLoading = true);

    try {
      var snapshot = await FirebaseFirestore.instance
          .collection("vehicle_requests")
          .where("status", isEqualTo: "pending")
          .get();

      if (mounted) {
        setState(() {
          _pendingRequests = snapshot.docs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching vehicle requests: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future _approveRequest(DocumentSnapshot request) async {
    String authorityName = FirebaseAuth.instance.currentUser?.displayName ?? "Authority";
    Timestamp now = Timestamp.now();

    await FirebaseFirestore.instance
        .collection("vehicle_requests")
        .doc(request.id)
        .update({
      "status": "approved",
      "approvedBy": authorityName,
      "approvedAt": now,
    });

    _fetchPendingRequests();
  }

  Future _rejectRequest(DocumentSnapshot request, {String? reason}) async {
    String authorityName = FirebaseAuth.instance.currentUser?.displayName ?? "Authority";
    Timestamp now = Timestamp.now();

    Map<String, dynamic> updateData = {
      "status": "rejected",
      "rejectedBy": authorityName,
      "rejectedAt": now,
    };
    if (reason != null && reason.trim().isNotEmpty) {
      updateData["rejectionReason"] = reason.trim();
    }

    await FirebaseFirestore.instance
        .collection("vehicle_requests")
        .doc(request.id)
        .update(updateData);

    _fetchPendingRequests();
  }

  void _showApproveConfirmation(DocumentSnapshot request) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Approval"),
        content: Text("Approve vehicle entry for ${request["visitorName"]} (${request["vehicleNumber"]})?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _approveRequest(request);
            },
            child: const Text("Approve"),
          ),
        ],
      ),
    );
  }

  void _showRejectConfirmation(DocumentSnapshot request) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reject Request"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Reject vehicle entry for ${request["visitorName"]}?"),
            const SizedBox(height: 15),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: "Reason (optional)",
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
              _rejectRequest(request, reason: reasonController.text);
            },
            child: const Text("Reject", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showRequestDetails(DocumentSnapshot request) {
    Timestamp? visitDate = request["visitDate"];
    String formattedDate = visitDate != null
        ? DateFormat('EEE, dd MMM yyyy').format(visitDate.toDate())
        : "N/A";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(request["visitorName"] ?? ""),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow("Student", request["name"] ?? ""),
              _detailRow("Roll No.", request["rollNumber"] ?? ""),
              _detailRow("Student Phone", request["phone"] ?? ""),
              _detailRow("Hostel", request["hostel"] ?? ""),
              const Divider(height: 20),
              _detailRow("Visitor", request["visitorName"] ?? ""),
              _detailRow("Visitor Phone", request["visitorPhone"] ?? ""),
              _detailRow("Relationship", request["relationship"] ?? ""),
              const Divider(height: 20),
              _detailRow("Vehicle Type", request["vehicleType"] ?? ""),
              _detailRow("Vehicle No.", request["vehicleNumber"] ?? ""),
              _detailRow("Members", "${request["numberOfMembers"] ?? ""}"),
              const Divider(height: 20),
              _detailRow("Visit Date", formattedDate),
              _detailRow("Purpose", request["purpose"] ?? ""),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showRejectConfirmation(request);
            },
            child: const Text("Reject", style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showApproveConfirmation(request);
            },
            child: const Text("Approve"),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  IconData _vehicleIcon(String? type) {
    if (type == null) return Icons.directions_car;
    String lower = type.toLowerCase();
    if (lower.contains("two wheeler")) return Icons.two_wheeler;
    if (lower.contains("auto")) return Icons.electric_rickshaw;
    if (lower.contains("car")) return Icons.directions_car;
    if (lower.contains("van")) return Icons.airport_shuttle;
    return Icons.local_shipping;
  }

  @override
  Widget build(BuildContext context) {
    // Filter
    List<DocumentSnapshot> filtered = _pendingRequests;
    if (_searchQuery.isNotEmpty) {
      filtered = _pendingRequests.where((req) {
        String name = (req["name"] ?? "").toString().toLowerCase();
        String roll = (req["rollNumber"] ?? "").toString().toLowerCase();
        String vehicle = (req["vehicleNumber"] ?? "").toString().toLowerCase();
        String query = _searchQuery.toLowerCase();
        return name.contains(query) || roll.contains(query) || vehicle.contains(query);
      }).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Vehicle Approval"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchPendingRequests,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final shouldLogout = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Confirm Logout"),
                  content: const Text("Are you sure you want to log out?"),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text("Cancel"),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text("Log Out"),
                    ),
                  ],
                ),
              );
              if (shouldLogout != true) return;

              UserCache().clear();
              try {
                await GoogleSignIn().signOut();
              } catch (e) {
                debugPrint("GoogleSignIn signOut error: $e");
              }
              await FirebaseAuth.instance.signOut();
              if (!mounted) return;
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
            : Column(
                children: [
                  // Search bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: "Search by name, roll no. or vehicle no.",
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = "");
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onChanged: (value) {
                        setState(() => _searchQuery = value);
                      },
                    ),
                  ),

                  // Request count
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "${filtered.length} pending request${filtered.length != 1 ? 's' : ''}",
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ),
                  ),

                  // List
                  Expanded(
                    child: filtered.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 150),
                              Center(child: Text("No Pending Vehicle Requests")),
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
                              Timestamp? visitDate = request["visitDate"];
                              String formattedDate = visitDate != null
                                  ? DateFormat('dd MMM yyyy').format(visitDate.toDate())
                                  : "N/A";

                              return GestureDetector(
                                onTap: () => _showRequestDetails(request),
                                child: Card(
                                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  child: Padding(
                                    padding: const EdgeInsets.all(15),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Student + Vehicle info
                                        Row(
                                          children: [
                                            Icon(
                                              _vehicleIcon(request["vehicleType"]),
                                              size: 36,
                                              color: const Color(0xFF0A192F),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    "${request["name"]}",
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                                  ),
                                                  Text("Roll: ${request["rollNumber"]}"),
                                                  Text("${request["degree"]} • ${request["hostel"]}"),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),

                                        const SizedBox(height: 10),

                                        // Vehicle details
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                "${request["vehicleType"]} • ${request["vehicleNumber"]}",
                                                style: const TextStyle(fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                            Text(
                                              formattedDate,
                                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                            ),
                                          ],
                                        ),

                                        const SizedBox(height: 4),

                                        Text(
                                          "Visitor: ${request["visitorName"]} (${request["relationship"]})",
                                          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                                        ),

                                        const SizedBox(height: 12),

                                        // Action buttons
                                        Row(
                                          children: [
                                            ElevatedButton(
                                              onPressed: () => _showApproveConfirmation(request),
                                              child: const Text("Approve"),
                                            ),
                                            const SizedBox(width: 10),
                                            ElevatedButton(
                                              onPressed: () => _showRejectConfirmation(request),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.grey.shade200,
                                                foregroundColor: Colors.red,
                                                elevation: 0,
                                              ),
                                              child: const Text("Reject"),
                                            ),
                                          ],
                                        ),
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
      ),
    );
  }
}
