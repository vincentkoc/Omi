import 'dart:async';
import 'dart:convert';

import 'package:friend_private/backend/database/geolocation.dart';
import 'package:friend_private/env/env.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;

class LocationService {
  Location location = Location();

  Future<bool> enableService() async {
    bool serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        return false;
      } else {
        return true;
      }
    } else {
      return true;
    }
  }

  Future<bool> isServiceEnabled() async {
    return await location.serviceEnabled();
  }

  Future<PermissionStatus> requestPermission() async {
    PermissionStatus permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
    }
    return permissionGranted;
  }

  Future<PermissionStatus> permissionStatus() async {
    return await location.hasPermission();
  }

  Future hasPermission() async {
    return await location.hasPermission() == PermissionStatus.granted;
  }

  Future<Geolocation?> getGeolocationDetails() async {
    if (await hasPermission()) {
      LocationData locationData = await location.getLocation();
      var res = await http.get(
        Uri.parse(
            "https://maps.googleapis.com/maps/api/geocode/json?latlng=${locationData.latitude},${locationData.longitude}&key=${Env.googleMapsApiKey}"),
      );
      if (res.statusCode == 200) {
        var data = json.decode(res.body);
        Geolocation geolocation = Geolocation(
          latitude: locationData.latitude,
          longitude: locationData.longitude,
          address: data['results'][0]['formatted_address'],
          locationType: data['results'][0]['types'][0],
          googlePlaceId: data['results'][0]['place_id'],
        );
        return geolocation;
      }
      return Geolocation(
        latitude: locationData.latitude,
        longitude: locationData.longitude,
      );
    } else {
      return null;
    }
  }
}
