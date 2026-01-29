import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://wunkujstxrjifcqefiju.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind1bmt1anN0eHJqaWZjcWVmaWp1Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NjM3OTQxNiwiZXhwIjoyMDgxOTU1NDE2fQ.yRXzeqTEaZtXfcUgJvRh7W_Lb0lYT7rD4H--sZKo7ww',
  );

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: BaristaKDSPage(),
  ));
}

class BaristaKDSPage extends StatefulWidget {
  const BaristaKDSPage({super.key});

  @override
  State<BaristaKDSPage> createState() => _BaristaKDSPageState();
}

class _BaristaKDSPageState extends State<BaristaKDSPage> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Map<String, String> _localStatusCache = {};

  @override
  void initState() {
    super.initState();
    _initTerminalSettings();
  }

  Future<void> _initTerminalSettings() async {
    await Future.delayed(const Duration(milliseconds: 100));
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _updateStatus(String id, String newStatus) async {
    // Update local cache immediately for instant feedback
    setState(() {
      _localStatusCache[id] = newStatus;
    });
    
    try {
      await _supabase.from('orders').update({'status': newStatus}).eq('id', id);
      // Don't remove from cache immediately - let the stream update naturally
      // The cache will be cleared when the stream confirms the change
    } catch (e) {
      debugPrint("Error updating status: $e");
      // Remove from cache on error to revert to original status
      setState(() {
        _localStatusCache.remove(id);
      });
    }
  }

  /// Logic to redeem either a Loyalty or Referral reward
  Future<void> _redeemReward(String profileId, String? loyaltyCode, String? refCode) async {
    try {
      Map<String, dynamic> updateData = {'is_redeemed': true};

      if (loyaltyCode != null) {
        updateData['loyalty_redemption_code'] = null;
        updateData['stamps_count'] = 0;
      } else if (refCode != null) {
        updateData['redemption_code'] = null;
      }

      // Add .select() at the end to force Supabase to return the updated data
      // If 'data' is empty, it means RLS blocked the update or the ID was wrong.
      final data = await _supabase
          .from('profiles')
          .update(updateData)
          .eq('id', profileId)
          .select();

      if (data.isEmpty) {
        throw Exception("No rows updated. Check RLS policies!");
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Reward Redeemed!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("Redemption Error: $e");
      // Show the actual error to the Barista so they know it didn't save
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  void _showRewardLookup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Text("ACTIVE REWARD CODES", style: TextStyle(color: Colors.amber, fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                // Listen for any user that has a code in either column
                stream: _supabase.from('profiles').stream(primaryKey: ['id']),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.amber));

                  // Filter users with at least one active (unredeemed) code
                  final eligibleUsers = snapshot.data!.where((user) {
                    bool hasLoyalty = user['loyalty_redemption_code'] != null;
                    bool hasReferral = user['redemption_code'] != null;
                    return hasLoyalty || hasReferral;
                  }).toList();

                  if (eligibleUsers.isEmpty) return const Center(child: Text("No active rewards", style: TextStyle(color: Colors.white24)));

                  return ListView.builder(
                    controller: scrollController,
                    itemCount: eligibleUsers.length,
                    itemBuilder: (context, index) {
                      final user = eligibleUsers[index];
                      final lCode = user['loyalty_redemption_code'];
                      final rCode = user['redemption_code'];

                      return Card(
                        color: Colors.white.withOpacity(0.05),
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          leading: Icon(
                              Icons.card_giftcard,
                              color: lCode != null ? Colors.brown[300] : Colors.green[300]
                          ),
                          title: Text(user['name'] ?? user['email'] ?? "Customer", style: const TextStyle(color: Colors.white)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (lCode != null) Text("LOYALTY: $lCode", style: TextStyle(color: Colors.brown[200])),
                              if (rCode != null) Text("REFERRAL: $rCode", style: TextStyle(color: Colors.green[200])),
                            ],
                          ),
                          trailing: ElevatedButton(
                            onPressed: () => _redeemReward(user['id'], lCode, rCode),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                            child: const Text("CLAIM"),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildStatsBar(),
            Expanded(child: _buildOrdersGrid()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF238636),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.coffee, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("BLISS KITCHEN DISPLAY", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              Text("Real-time Order Management", style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
            ],
          ),
          const Spacer(),
          _buildRewardsButton(),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF21262D),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                const Text("LIVE", style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _supabase.from('orders').stream(primaryKey: ['id']),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        
        final orders = snapshot.data!;
        final pendingCount = orders.where((o) => o['status'] == 'paid').length;
        final preparingCount = orders.where((o) => o['status'] == 'preparing').length;
        final readyCount = orders.where((o) => o['status'] == 'ready').length;
        
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  _buildStatCard("PENDING", pendingCount, const Color(0xFFE91E63)),
                  const SizedBox(width: 12),
                  _buildStatCard("PREPARING", preparingCount, const Color(0xFFFF9800)),
                  const SizedBox(width: 12),
                  _buildStatCard("READY", readyCount, const Color(0xFF4CAF50)),
                  const Spacer(),
                  _buildQuickActionBtn(Icons.refresh, "REFRESH", () => setState(() {})),
                ],
              ),
              const SizedBox(height: 12),
              _buildSearchBar(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          children: [
            Text(count.toString(), style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {
            _searchQuery = value.toLowerCase();
          });
        },
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: "Search by order ID, customer name, or items...",
          hintStyle: const TextStyle(color: Color(0xFF8B949E), fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: Color(0xFF8B949E), size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Color(0xFF8B949E), size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildRewardsButton() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF238636),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF238636).withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showRewardLookup,
          borderRadius: BorderRadius.circular(12),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_activity, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text("REWARDS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionBtn(IconData icon, String label, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF21262D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOrdersGrid() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _supabase
          .from('orders')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: true),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF238636)));
        }

        final activeOrders = snapshot.data!.where((order) {
          final String orderId = order['id'].toString();
          final String status = order['status']?.toString().toLowerCase() ?? 'pending';
          final bool isCorrectStatus = ['paid', 'preparing', 'ready'].contains(status);
          final bool isBulk = order['is_bulk'] == true;
          
          if (!isCorrectStatus || isBulk) return false;
          
          // Clear cache if stream status matches cached status (meaning update is confirmed)
          if (_localStatusCache.containsKey(orderId)) {
            final String cachedStatus = _localStatusCache[orderId]!;
            if (cachedStatus == status) {
              // Stream has caught up with our local change, clear the cache
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _localStatusCache.remove(orderId);
                  });
                }
              });
            }
          }
          
          return true;
        }).toList();

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _enrichOrdersWithCustomerNames(activeOrders),
          builder: (context, enrichedSnapshot) {
            if (!enrichedSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFF238636)));
            }

            // Apply search filter after enrichment for better performance
            final filteredOrders = _searchQuery.isEmpty 
                ? enrichedSnapshot.data!
                : enrichedSnapshot.data!.where((order) {
                    final String orderId = order['id'].toString().substring(0, 6).toUpperCase();
                    final String customerName = order['customer_name']?.toString().toLowerCase() ?? '';
                    final String itemsSummary = order['items_summary']?.toString().toLowerCase() ?? '';
                    
                    return orderId.toLowerCase().contains(_searchQuery) ||
                           customerName.contains(_searchQuery) ||
                           itemsSummary.contains(_searchQuery);
                  }).toList();

            if (filteredOrders.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161B22),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Icon(
                        _searchQuery.isNotEmpty ? Icons.search_off : Icons.check_circle, 
                        color: const Color(0xFF238636), 
                        size: 48
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _searchQuery.isNotEmpty ? "NO ORDERS FOUND" : "ALL ORDERS COMPLETE", 
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)
                    ),
                    Text(
                      _searchQuery.isNotEmpty ? "Try a different search term" : "Ready for new orders", 
                      style: const TextStyle(color: Color(0xFF8B949E), fontSize: 14)
                    ),
                  ],
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.all(12),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.8,
                ),
                itemCount: filteredOrders.length,
                itemBuilder: (context, index) => _buildProfessionalOrderTicket(filteredOrders[index]),
              ),
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _enrichOrdersWithCustomerNames(List<Map<String, dynamic>> orders) async {
    final List<Map<String, dynamic>> enrichedOrders = [];
    
    for (final order in orders) {
      final enrichedOrder = Map<String, dynamic>.from(order);
      
      // Try to get customer name from profiles table using user_id
      if (order['user_id'] != null) {
        try {
          final profileData = await _supabase
              .from('profiles')
              .select('name')
              .eq('id', order['user_id'])
              .maybeSingle();
          
          if (profileData != null && profileData['name'] != null) {
            enrichedOrder['customer_name'] = profileData['name'];
          }
        } catch (e) {
          debugPrint("Error fetching customer name: $e");
        }
      }
      
      enrichedOrders.add(enrichedOrder);
    }
    
    return enrichedOrders;
  }

  Widget _buildQuickActions() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF238636),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF238636).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showRewardLookup,
          borderRadius: BorderRadius.circular(16),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_activity, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text("REWARDS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfessionalOrderTicket(Map<String, dynamic> order) {
    final String orderId = order['id'].toString();
    // Use cached status if available, otherwise use database status
    String status = _localStatusCache[orderId] ?? order['status']?.toString().toLowerCase() ?? 'paid';
    
    final String timeLabel = _getTimeSinceOrder(order['created_at']);
    final String displayOrderId = "#${orderId.substring(0, 6).toUpperCase()}";

    final List<String> items = (order['items_summary']?.toString() ?? "NEW ORDER")
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    Color statusColor = status == 'preparing' ? const Color(0xFFFF9800) : 
                       (status == 'ready' ? const Color(0xFF4CAF50) : const Color(0xFFE91E63));
    String btnText = status == 'preparing' ? "MARK READY" : 
                    (status == 'ready' ? "COMPLETE" : "START PREP");
    String nextStatus = status == 'preparing' ? "ready" : 
                       (status == 'ready' ? "collected" : "preparing");
    
    bool isUrgent = DateTime.now().difference(DateTime.tryParse(order['created_at']) ?? DateTime.now()).inMinutes > 10;
    bool isUpdating = _localStatusCache.containsKey(orderId);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _updateStatus(orderId, nextStatus),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isUrgent ? const Color(0xFFE91E63).withOpacity(0.5) : Colors.white.withOpacity(0.1),
              width: isUrgent ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with status
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  border: Border(bottom: BorderSide(color: statusColor.withOpacity(0.3))),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        displayOrderId,
                        style: const TextStyle(
                          color: Colors.white, 
                          fontSize: 14, 
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (isUpdating)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          "UPDATING...",
                          style: TextStyle(
                            color: Colors.white, 
                            fontSize: 10, 
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    if (isUrgent)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE91E63),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          "URGENT",
                          style: TextStyle(
                            color: Colors.white, 
                            fontSize: 10, 
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        timeLabel,
                        style: TextStyle(
                          color: statusColor, 
                          fontSize: 12, 
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Order items
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "ORDER ITEMS",
                        style: TextStyle(
                          color: const Color(0xFF8B949E), 
                          fontSize: 10, 
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: statusColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      items[index].toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white, 
                                        fontSize: 14, 
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person, color: Color(0xFF8B949E), size: 12),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                order['customer_name'] ?? 'GUEST',
                                style: const TextStyle(
                                  color: Color(0xFF8B949E), 
                                  fontSize: 10, 
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Action button area (now just visual, click is handled by parent InkWell)
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                  border: Border(top: BorderSide(color: statusColor.withOpacity(0.3))),
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        status == 'preparing' ? Icons.check_circle : 
                        status == 'ready' ? Icons.done_all : Icons.play_arrow,
                        color: statusColor,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        btnText,
                        style: TextStyle(
                          color: statusColor, 
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getTimeSinceOrder(String? timestamp) {
    if (timestamp == null) return "0m";
    final startTime = DateTime.tryParse(timestamp) ?? DateTime.now();
    final diff = DateTime.now().difference(startTime);
    if (diff.inMinutes < 1) return "NEW";
    return "${diff.inMinutes}m ago";
  }
}