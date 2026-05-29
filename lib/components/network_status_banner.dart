import 'package:flutter/material.dart';
import 'package:viora/Services/network_service.dart';
import 'package:viora/constants.dart';

/// Banner that shows network status (offline/slow connection warning)
class NetworkStatusBanner extends StatefulWidget {
  const NetworkStatusBanner({Key? key}) : super(key: key);

  @override
  State<NetworkStatusBanner> createState() => _NetworkStatusBannerState();
}

class _NetworkStatusBannerState extends State<NetworkStatusBanner> {
  final _networkService = NetworkService();
  bool _isConnected = true;
  bool _isCheckingQuality = false;
  NetworkQuality? _networkQuality;

  @override
  void initState() {
    super.initState();
    _isConnected = _networkService.isConnected;
    
    // Listen for connectivity changes
    _networkService.addConnectivityListener(_onConnectivityChanged);
    
    // Check initial network quality
    _checkNetworkQuality();
  }

  @override
  void dispose() {
    _networkService.removeConnectivityListener(_onConnectivityChanged);
    super.dispose();
  }

  void _onConnectivityChanged(bool isConnected) {
    if (mounted) {
      setState(() {
        _isConnected = isConnected;
      });
      
      if (isConnected) {
        _checkNetworkQuality();
      }
    }
  }

  Future<void> _checkNetworkQuality() async {
    if (_isCheckingQuality) return;
    
    setState(() {
      _isCheckingQuality = true;
    });

    final quality = await _networkService.getNetworkQuality();
    
    if (mounted) {
      setState(() {
        _networkQuality = quality;
        _isCheckingQuality = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Don't show banner if connected with good quality
    if (_isConnected && 
        _networkQuality != null && 
        _networkQuality != NetworkQuality.poor &&
        _networkQuality != NetworkQuality.offline) {
      return const SizedBox.shrink();
    }

    // Show banner for offline or poor connection
    final bool isOffline = !_isConnected || _networkQuality == NetworkQuality.offline;
    final bool isPoor = _networkQuality == NetworkQuality.poor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: isOffline || isPoor ? 40 : 0,
      child: Container(
        color: isOffline ? Colors.red : Colors.orange,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              isOffline ? Icons.wifi_off : Icons.signal_wifi_statusbar_connected_no_internet_4,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isOffline 
                    ? 'No internet connection' 
                    : 'Slow connection - some features may be delayed',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!isOffline && isPoor)
              TextButton(
                onPressed: _checkNetworkQuality,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(40, 24),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
