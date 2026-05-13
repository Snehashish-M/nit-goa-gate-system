import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class VehicleStatus extends StatefulWidget {
  final bool embedded;
  const VehicleStatus({super.key, this.embedded = false});

  @override
  State<VehicleStatus> createState() => _VehicleStatusState();
}

class _VehicleStatusState extends State<VehicleStatus> {

  StreamSubscription? _listener;
  Map<String, dynamic>? _requestData;
  String? _requestId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _watchVehicleRequest();
  }

  @override
  void dispose() {
    _listener?.cancel();
    super.dispose();
  }

  void _watchVehicleRequest() {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    _listener = FirebaseFirestore.instance
        .collection("vehicle_requests")
        .where("studentId", isEqualTo: user.uid)
        .where("status", whereIn: ["pending", "approved"])
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        if (snapshot.docs.isNotEmpty) {
          setState(() {
            _requestData = snapshot.docs.first.data();
            _requestId = snapshot.docs.first.id;
            _isLoading = false;
          });
        } else {
          setState(() {
            _requestData = null;
            _requestId = null;
            _isLoading = false;
          });
        }
      }
    });
  }

  Future<void> _cancelRequest() async {
    if (_requestId == null) return;

    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cancel Vehicle Request"),
        content: const Text("Are you sure you want to cancel this vehicle entry request? This action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("No"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Yes, Cancel"),
          ),
        ],
      ),
    );

    if (shouldCancel != true) return;

    try {
      await FirebaseFirestore.instance
          .collection("vehicle_requests")
          .doc(_requestId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Vehicle request cancelled")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.toString()}")),
        );
      }
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case "approved":
        return Colors.green;
      case "rejected":
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case "approved":
        return Icons.check_circle;
      case "rejected":
        return Icons.cancel;
      default:
        return Icons.hourglass_top;
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _requestData == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.directions_car_outlined, size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 20),
                      const Text(
                        "No Active Vehicle Request",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0A192F),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "You can apply for a vehicle entry from the Application tab.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [

                  // ─── STATUS BANNER ──────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: _statusColor(_requestData!["status"]).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _statusColor(_requestData!["status"]).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _statusIcon(_requestData!["status"]),
                          color: _statusColor(_requestData!["status"]),
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Status",
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                            Text(
                              (_requestData!["status"] as String).toUpperCase(),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _statusColor(_requestData!["status"]),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  if (_requestData!["status"] == "approved") ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "Approved by ${_requestData!["approvedBy"] ?? "Authority"}",
                        style: TextStyle(fontSize: 13, color: Colors.green.shade800),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // ─── VISITOR INFO ────────────────────────
                  const Text(
                    "Visitor Details",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0A192F)),
                  ),
                  const SizedBox(height: 12),

                  _buildInfoRow("Visitor Name", _requestData!["visitorName"] ?? ""),
                  _buildInfoRow("Visitor Phone", _requestData!["visitorPhone"] ?? ""),
                  _buildInfoRow("Relationship", _requestData!["relationship"] ?? ""),

                  const SizedBox(height: 20),

                  // ─── VEHICLE INFO ────────────────────────
                  const Text(
                    "Vehicle Details",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0A192F)),
                  ),
                  const SizedBox(height: 12),

                  _buildInfoRow("Vehicle Type", _requestData!["vehicleType"] ?? ""),
                  _buildInfoRow("Vehicle Number", _requestData!["vehicleNumber"] ?? ""),
                  _buildInfoRow("Members", "${_requestData!["numberOfMembers"] ?? ""}"),

                  const SizedBox(height: 20),

                  // ─── VISIT INFO ──────────────────────────
                  const Text(
                    "Visit Details",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0A192F)),
                  ),
                  const SizedBox(height: 12),

                  _buildInfoRow("Visit Date", _requestData!["visitDate"] != null
                      ? DateFormat('EEE, dd MMM yyyy').format((_requestData!["visitDate"] as Timestamp).toDate())
                      : ""),
                  _buildInfoRow("Purpose", _requestData!["purpose"] ?? ""),

                  // ─── CANCEL BUTTON ───────────────────────
                  const SizedBox(height: 30),

                  SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _cancelRequest,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "Cancel Request",
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Vehicle Status"),
      ),
      body: body,
    );
  }
}
