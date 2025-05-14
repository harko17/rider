import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'dart:async';
import 'package:flutter/services.dart';

const String googleMapsApiKey =
    'YOUR_API_KEY'; // Replace with your actual Google Maps API key

final List<Map<String, dynamic>> pickups = [
  {
    "id": 1,
    "location": const LatLng(25.438736, 81.798302),
    "time_slot": "9AM-10AM",
    "inventory": 5,
  },
  {
    "id": 2,
    "location": const LatLng(25.433891, 81.794054),
    "time_slot": "9AM-10AM",
    "inventory": 3,
  },
  {
    "id": 3,
    "location": const LatLng(25.433213, 81.791221),
    "time_slot": "10AM-11AM",
    "inventory": 7,
  },
];
final warehouseLocation = const LatLng(25.426334, 81.788496);

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
  final PolylinePoints polylinePoints = PolylinePoints();
  List<LatLng> routeCoordinates = [];
  bool isMapLoaded = false;
  Timer? locationTimer;
  int currentRouteIndex = 0;
  bool isNavigating = false;
  double totalDistance = 0.0;
  double distanceToNextPoint = 0.0;
  String? _mapStyle;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _getCurrentLocation().then((_) {});
  }

  Future<void> _loadMapStyle() async {
    try {
      _mapStyle = await DefaultAssetBundle.of(context)
          .loadString('assets/map_style.json');
    } catch (e) {
      print("Error loading map style: $e");
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        print("Location permission denied.");
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
    } on PlatformException catch (e) {
      print("PlatformException getting location: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error getting location: ${e.message}'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      print("Error getting location: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error getting location: ${e.toString()}'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _setMapStyle() async {
    if (isMapLoaded && _mapStyle != null) {
      mapController.setMapStyle(_mapStyle!);
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
          icon: BitmapDescriptor.defaultMarker,
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

    routeCoordinates.clear();
    routeCoordinates.add(currentLocation!);

    for (var pickup in pickups) {
      routeCoordinates.add(pickup['location']);
    }
    routeCoordinates.add(warehouseLocation);

    List<PointLatLng> polylinePointsList =
    routeCoordinates.map((e) => PointLatLng(e.latitude, e.longitude)).toList();

    _polylines.clear();

    Polyline polyline = Polyline(
      polylineId: const PolylineId('route'),
      color: Colors.blue,
      points: routeCoordinates,
      width: 5,
    );

    _polylines.add(polyline);
    totalDistance = _calculateRouteDistance(routeCoordinates);
    setState(() {});
  }

  double _calculateRouteDistance(List<LatLng> points) {
    double distance = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      distance += Geolocator.distanceBetween(
        points[i].latitude,
        points[i].longitude,
        points[i + 1].latitude,
        points[i + 1].longitude,
      );
    }
    return distance;
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
              _setMapStyle();
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
                backgroundColor: isNavigating
                    ? Colors.grey
                    : Colors.blue,
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
          Positioned(
            top: 70,
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
              child: Text(
                "Total Distance: ${totalDistance.toStringAsFixed(2)} meters",
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

