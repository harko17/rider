import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:rider/secrets.dart';

 // Replace with your actual Google Maps API key

final List<Map<String, dynamic>> pickups = [
  {
    "id": 1,
    "location": const LatLng(25.433213, 81.79122 ),
    "time_slot": "9AM-10AM",
    "inventory": 3,
  },
  {
    "id": 2,
    "location": const LatLng(25.433891, 81.794054),
    "time_slot": "9AM-10AM",
    "inventory": 2,
  },
  {
    "id": 3,
    "location": const LatLng(25.438097, 81.793935),
    "time_slot": "9AM-10AM",
    "inventory": 1,
  },
  {
    "id": 4,
    "location": const LatLng(25.438736, 81.798302),
    "time_slot": "10AM-11AM",
    "inventory": 7,
  },
  {
    "id": 5,
    "location": const LatLng(25.438836, 81.801707),
    "time_slot": "10AM-11AM",
    "inventory": 7,
  },
];
final warehouseLocation = const LatLng(25.441506, 81.806044);

class JobRouteScreen extends StatefulWidget {
  const JobRouteScreen({super.key});

  @override
  _JobRouteScreenState createState() => _JobRouteScreenState();
}

class _JobRouteScreenState extends State<JobRouteScreen> {
  late GoogleMapController mapController;
  LatLng? currentLocation;
  final List<Marker> _markers = [];
  final Set<Polyline> _polylines = {};
  List<LatLng> routeCoordinates = [];
  bool isMapLoaded = false;
  Timer? locationTimer;
  int currentRouteIndex = 0;
  bool isNavigating = false;
  double distanceToNextPoint = 0.0;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Location permission is required to show your location and route.'),
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      currentLocation = LatLng(position.latitude, position.longitude);
      if (isMapLoaded) {
        mapController.animateCamera(CameraUpdate.newLatLng(currentLocation!));
      }
      _updateMarkers();
      _drawRoute();
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error getting location: ${e.toString()}'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _updateMarkers() {
    _markers.clear();
    if (currentLocation != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: currentLocation!,
          infoWindow: const InfoWindow(title: 'Your Location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    }

    for (var pickup in pickups) {
      _markers.add(
        Marker(
          markerId: MarkerId('pickup_${pickup['id']}'),
          position: pickup['location'],
          infoWindow: InfoWindow(
              title: 'Pickup ${pickup['id']}',
              snippet:
              'Time: ${pickup['time_slot']}, Inventory: ${pickup['inventory']}'),
        ),
      );
    }

    _markers.add(
      Marker(
        markerId: const MarkerId('warehouse_location'),
        position: warehouseLocation,
        infoWindow: const InfoWindow(title: 'Warehouse'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
    );
  }

  Future<void> _drawRoute() async {
    if (currentLocation == null) return;

    final List<List<double>> coordinates = [
      [currentLocation!.longitude, currentLocation!.latitude],
      ...pickups.map((p) => [p['location'].longitude, p['location'].latitude]),
      [warehouseLocation.longitude, warehouseLocation.latitude],
    ];

    final url = Uri.parse('https://api.openrouteservice.org/v2/directions/driving-car/geojson');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': apiKey,  // Replace with your OpenRouteService API key
        },
        body: jsonEncode({'coordinates': coordinates}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        final List coords = data['features'][0]['geometry']['coordinates'];

        final List<LatLng> routePoints = coords
            .map<LatLng>((c) => LatLng(c[1] as double, c[0] as double))
            .toList();

        _polylines.clear();
        _polylines.add(
          Polyline(
            polylineId: PolylineId('route'),
            points: routePoints,
            color: Colors.blue,
            width: 5,
          ),
        );

        setState(() {});
      } else {
        print('Failed to load route: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('Error fetching route: $e');
    }
  }

  void _startNavigation() {
    if (currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait while we get your current location...'),
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    setState(() {
      isNavigating = true;
      currentRouteIndex = 0;
    });

    locationTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _getCurrentLocation();
      if (isNavigating && currentLocation != null) {
        distanceToNextPoint = Geolocator.distanceBetween(
          currentLocation!.latitude,
          currentLocation!.longitude,
          routeCoordinates[currentRouteIndex].latitude,
          routeCoordinates[currentRouteIndex].longitude,
        );

        if (distanceToNextPoint < 20) {
          if (currentRouteIndex < routeCoordinates.length - 1) {
            currentRouteIndex++;
            mapController.animateCamera(
              CameraUpdate.newLatLng(routeCoordinates[currentRouteIndex]),
            );
          } else {
            setState(() {
              isNavigating = false;
              locationTimer?.cancel();
            });
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Navigation Complete'),
                content: const Text('You have reached your destination!'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
        }
      }
    });
  }

  @override
  void dispose() {
    mapController.dispose();
    locationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Job Route'),
        centerTitle: true,
      ),
      body: currentLocation == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) {
              mapController = controller;
              isMapLoaded = true;
            },
            initialCameraPosition: CameraPosition(
              target: currentLocation!,
              zoom: 12.0,
            ),
            myLocationEnabled: true,
            markers: Set<Marker>.from(_markers),
            polylines: _polylines,
          ),
          Positioned(
            bottom: 16.0,
            left: 16.0,
            right: 16.0,
            child: ElevatedButton(
              onPressed: isNavigating ? null : _startNavigation,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.0),
                ),
                backgroundColor: isNavigating ? Colors.grey : Colors.blue,
              ),
              child: Text(
                isNavigating ? 'Navigating...' : 'Navigate',
                style:
                const TextStyle(fontSize: 18.0, color: Colors.white),
              ),
            ),
          ),
          if (isNavigating)
            Positioned(
              top: 20,
              left: 20,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.5),
                      spreadRadius: 2,
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Navigating to: ${currentRouteIndex < pickups.length ? 'Pickup ${pickups[currentRouteIndex]['id']}' : 'Warehouse'}",
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "Distance to next: ${distanceToNextPoint.toStringAsFixed(2)} meters",
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}/*
Google Route fetching
Future<void> _drawRoute() async {
    if (currentLocation == null) return;

    routeCoordinates.clear();
    routeCoordinates.add(currentLocation!);

    for (var pickup in pickups) {
      routeCoordinates.add(pickup['location']);
    }
    routeCoordinates.add(warehouseLocation);

    _polylines.clear();

    for (int i = 0; i < routeCoordinates.length - 1; i++) {
      LatLng origin = routeCoordinates[i];
      LatLng destination = routeCoordinates[i + 1];

      final url =
          'https://maps.googleapis.com/maps/api/directions/json?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&key=$googleMapsApiKey';

      final response = await http.get(Uri.parse(url));
      final data = json.decode(response.body);

      if (data['status'] == 'OK') {
        List<PointLatLng> result = PolylinePoints()
            .decodePolyline(data['routes'][0]['overview_polyline']['points']);

        List<LatLng> polylinePoints = result
            .map((point) => LatLng(point.latitude, point.longitude))
            .toList();

        _polylines.add(
          Polyline(
            polylineId: PolylineId('route_$i'),
            points: polylinePoints,
            color: Colors.blue,
            width: 5,
          ),
        );
      } else {
        print("Directions API error: ${data['status']}");
      }
    }

    setState(() {});
  }
*/