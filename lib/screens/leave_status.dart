import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

class LeaveStatus extends StatefulWidget {
  const LeaveStatus({super.key});

  @override
  State<LeaveStatus> createState() => _LeaveStatusState();
}

class _LeaveStatusState extends State<LeaveStatus> {

  List<DocumentSnapshot> _leaveRequests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchLeaveRequests();
  }

  Future<void> _fetchLeaveRequests() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      var snapshot = await FirebaseFirestore.instance
          .collection("leave_requests")
          .where("studentId", isEqualTo: user.uid)
          .get();

      var docs = snapshot.docs;

      // Sort by createdAt descending
      docs.sort((a, b) {
        Timestamp aTime = a["createdAt"] ?? Timestamp.now();
        Timestamp bTime = b["createdAt"] ?? Timestamp.now();
        return bTime.compareTo(aTime);
      });

      if (mounted) {
        setState(() {
          _leaveRequests = docs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching leave requests: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void showLeaveDetails(BuildContext context, DocumentSnapshot leaveRequest) {
    DateTime? leavingDate;
    DateTime? returnDate;

    try {
      if (leaveRequest["leavingDate"] is Timestamp) {
        leavingDate = (leaveRequest["leavingDate"] as Timestamp).toDate();
      }
      if (leaveRequest["returnDate"] is Timestamp) {
        returnDate = (leaveRequest["returnDate"] as Timestamp).toDate();
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
              Text("Name: ${leaveRequest["name"]}"),
              Text("Roll Number: ${leaveRequest["rollNumber"]}"),
              Text("Degree: ${leaveRequest["degree"]}"),
              Text("Hostel: ${leaveRequest["hostel"]}"),
              Text("Room: ${leaveRequest["roomNumber"]}"),
              Text("Phone: ${leaveRequest["phone"]}"),
              const SizedBox(height: 10),
              if (leavingDate != null)
                Text("Leaving Date: ${DateFormat('yyyy-MM-dd').format(leavingDate)}"),
              if (returnDate != null)
                Text("Return Date: ${DateFormat('yyyy-MM-dd').format(returnDate)}"),
              Text("Duration: ${leaveRequest["durationDays"]} days"),
              const SizedBox(height: 10),
              Text("Mode of Transport: ${leaveRequest["modeOfTransport"]}"),
              Text("Purpose: ${leaveRequest["purpose"]}"),
              Text("Address During Leave: ${leaveRequest["addressDuringLeave"]}"),
              Text("Parent Phone: ${leaveRequest["parentPhone"]}"),
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

    User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Leave Status")),
        body: const Center(child: Text("Not logged in")),
      );
    }

    return Scaffold(

      appBar: AppBar(
        title: const Text("Leave Application Status"),
      ),

      body: RefreshIndicator(
        onRefresh: _fetchLeaveRequests,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _leaveRequests.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 200),
                      Center(child: Text("No leave applications submitted")),
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

                    itemCount: _leaveRequests.length,
                    padding: const EdgeInsets.all(10),

                    itemBuilder: (context, index) {

                      var leaveRequest = _leaveRequests[index];
                      String status = leaveRequest["status"] ?? "pending";

                      DateTime? leavingDate;
                      DateTime? returnDate;

                      try {
                        if (leaveRequest["leavingDate"] is Timestamp) {
                          leavingDate = (leaveRequest["leavingDate"] as Timestamp).toDate();
                        }
                        if (leaveRequest["returnDate"] is Timestamp) {
                          returnDate = (leaveRequest["returnDate"] as Timestamp).toDate();
                        }
                      } catch (e) {
                        debugPrint("Error parsing dates: $e");
                      }

                      String purpose = leaveRequest["purpose"] ?? "N/A";

                      Color statusColor;
                      String statusText;

                      if (status == "pending") {
                        statusColor = Colors.orange;
                        statusText = "Pending";
                      } else if (status == "approved") {
                        statusColor = Colors.green;
                        statusText = "Approved";
                      } else {
                        statusColor = Colors.red;
                        statusText = "Rejected";
                      }

                      return GestureDetector(
                        onTap: () => showLeaveDetails(context, leaveRequest),
                        child: Card(

                          margin: const EdgeInsets.all(10),

                          child: Padding(
                            padding: const EdgeInsets.all(15),

                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,

                              children: [

                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,

                                  children: [

                                    Text(
                                      "Leave Request",
                                      style: Theme.of(context).textTheme.headlineSmall,
                                    ),

                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.2),
                                        border: Border.all(color: statusColor),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        statusText,
                                        style: TextStyle(
                                          color: statusColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),

                                  ],
                                ),

                                const SizedBox(height: 15),

                                if (leavingDate != null)
                                  Text(
                                    "From: ${DateFormat('yyyy-MM-dd').format(leavingDate)}",
                                    style: const TextStyle(fontSize: 14),
                                  ),

                                if (returnDate != null)
                                  Text(
                                    "To: ${DateFormat('yyyy-MM-dd').format(returnDate)}",
                                    style: const TextStyle(fontSize: 14),
                                  ),

                                Text(
                                  "Purpose: $purpose",
                                  style: const TextStyle(fontSize: 14),
                                ),

                                const SizedBox(height: 15),

                                const Center(
                                  child: Text(
                                    "Tap to view full details",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 20),

                                if (status == "approved")
                                  _ApprovedLeaveWidget(passId: leaveRequest.id)

                                else if (status == "rejected")
                                  const Padding(
                                    padding: EdgeInsets.all(20),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: Center(
                                        child: Text(
                                          "Your leave request has been rejected.",
                                          style: TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  )

                                else
                                  const Padding(
                                    padding: EdgeInsets.all(20),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: Center(
                                        child: Text(
                                          "Awaiting warden approval...",
                                          style: TextStyle(
                                            color: Colors.orange,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

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

class _ApprovedLeaveWidget extends StatefulWidget {

  final String passId;

  const _ApprovedLeaveWidget({required this.passId});

  @override
  State<_ApprovedLeaveWidget> createState() => _ApprovedLeaveWidgetState();
}

class _ApprovedLeaveWidgetState extends State<_ApprovedLeaveWidget> {

  StreamSubscription? _passListener;
  bool _isDeleted = false;

  @override
  void initState() {
    super.initState();
    _watchPass();
  }

  @override
  void dispose() {
    _passListener?.cancel();
    super.dispose();
  }

  void _watchPass() {
    _passListener = FirebaseFirestore.instance
        .collection("leave_requests")
        .doc(widget.passId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists && mounted) {
        setState(() => _isDeleted = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {

    if (_isDeleted) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: Text(
            "Gate pass has been used.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      );
    }

    return Center(

      child: Column(
        children: [

          const Text(
            "Your QR Code:",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 20),

          QrImageView(
            data: widget.passId,
            size: 250,
          ),

        ],
      ),

    );

  }

}
