import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http; 

class MapFilterPage extends StatefulWidget {
  final double initialRadius; // KM
  final LatLng? initialCenter; 

  const MapFilterPage({super.key, this.initialRadius = 5, this.initialCenter});

  @override
  State<MapFilterPage> createState() => _MapFilterPageState();
}

class _MapFilterPageState extends State<MapFilterPage> {
  final MapController _mapCtrl = MapController();
  final TextEditingController _searchCtrl = TextEditingController();
  
  late LatLng _center;
  late double _radiusKm;
  bool _isLoading = false;

  // Search Variables
  List<dynamic> _suggestions = [];
  Timer? _debounce;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _center = widget.initialCenter ?? const LatLng(-6.200, 106.816); // Default Jakarta
    _radiusKm = widget.initialRadius;
    if (widget.initialCenter == null) _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoading = true);
    Location location = Location();
    try {
      var loc = await location.getLocation();
      if (loc.latitude != null) {
        setState(() {
          _center = LatLng(loc.latitude!, loc.longitude!);
        });
        _mapCtrl.move(_center, 13);
      }
    } catch (e) {}
    finally { setState(() => _isLoading = false); }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      if (query.length > 3) {
        _fetchSuggestions(query);
      } else {
        setState(() => _suggestions = []);
      }
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    setState(() => _isSearching = true);
    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$query&format=json&addressdetails=1&limit=5&countrycodes=id');
      final response = await http.get(url, headers: {'User-Agent': 'com.example.smart_marketplace'});
      if (response.statusCode == 200) {
        setState(() => _suggestions = json.decode(response.body));
      }
    } catch (_) {} 
    finally { setState(() => _isSearching = false); }
  }

  void _selectSuggestion(Map<String, dynamic> place) {
    final lat = double.parse(place['lat']);
    final lon = double.parse(place['lon']);
    setState(() {
      _center = LatLng(lat, lon);
      _suggestions = [];
      _searchCtrl.clear();
    });
    _mapCtrl.move(_center, 13);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(title: const Text("Pilih Area Pencarian")),
      body: Column(
        children: [
          // SEARCH BAR
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: "Cari Kota / Kecamatan...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isSearching ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2)) : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey[100]
              ),
            ),
          ),
          
          if (_suggestions.isNotEmpty)
            Container(
              height: 200,
              color: Colors.white,
              child: ListView.separated(
                itemCount: _suggestions.length,
                separatorBuilder: (_,__) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final place = _suggestions[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on, color: Colors.red),
                    title: Text(place['display_name']),
                    onTap: () => _selectSuggestion(place),
                  );
                },
              ),
            ),

          // PETA
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapCtrl,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: 13.0,
                    onPositionChanged: (pos, hasGesture) {
                      if (hasGesture && pos.center != null) {
                        setState(() => _center = pos.center!);
                      }
                    },
                  ),
                  children: [
                    TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.smart_marketplace'),
                    CircleLayer(circles: [
                      CircleMarker(point: _center, color: Colors.blue.withOpacity(0.3), borderStrokeWidth: 2, borderColor: Colors.blue, useRadiusInMeter: true, radius: _radiusKm * 1000)
                    ]),
                    const Center(child: Icon(Icons.location_pin, color: Colors.red, size: 40)),
                  ],
                ),
                
                Positioned(
                  bottom: 20, right: 20,
                  child: FloatingActionButton(
                    onPressed: _getCurrentLocation,
                    backgroundColor: Colors.white,
                    child: _isLoading ? const CircularProgressIndicator() : const Icon(Icons.my_location, color: Colors.blue),
                  ),
                )
              ],
            ),
          ),

          // PANEL BAWAH (ADA TOMBOL RESET)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Jarak Radius:", style: TextStyle(fontWeight: FontWeight.bold)), Text("${_radiusKm.toStringAsFixed(1)} KM", style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor))]),
                Slider(value: _radiusKm, min: 1, max: 500, divisions: 499, label: "${_radiusKm.toInt()} km", onChanged: (val) => setState(() => _radiusKm = val)),
                const SizedBox(height: 10),
                
                // --- UPDATE: DUA TOMBOL (RESET & TERAPKAN) ---
                Row(
                  children: [
                    // Tombol Reset
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          // Kirim sinyal reset
                          Navigator.pop(context, {'reset': true});
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          minimumSize: const Size(0, 50),
                        ),
                        child: const Text("Reset (Semua)"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Tombol Terapkan
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () { 
                          Navigator.pop(context, {'center': _center, 'radius': _radiusKm}); 
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 50),
                        ),
                        child: const Text("Terapkan"),
                      ),
                    ),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}