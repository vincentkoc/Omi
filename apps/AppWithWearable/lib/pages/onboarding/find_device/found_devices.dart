import 'dart:async';

import 'package:flutter/material.dart';
import 'package:friend_private/backend/schema/bt_device.dart';
import 'package:friend_private/backend/preferences.dart';
import 'package:friend_private/backend/mixpanel.dart';
import 'package:friend_private/pages/home/page.dart';
import 'package:friend_private/utils/ble/communication.dart';
import 'package:friend_private/utils/ble/connect.dart';
import 'package:gradient_borders/gradient_borders.dart';

class FoundDevices extends StatefulWidget {
  final List<BTDeviceStruct?> deviceList;

  const FoundDevices({
    Key? key,
    required this.deviceList,
  }) : super(key: key);

  @override
  _FoundDevicesState createState() => _FoundDevicesState();
}

class _FoundDevicesState extends State<FoundDevices> with TickerProviderStateMixin {
  bool _isConnected = false;
  int batteryPercentage = -1;
  String deviceName = '';
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 1, end: 1.3).animate(_controller);
    super.initState();
  }

  Future<void> getBatteryPercentage(BTDeviceStruct deviceId) async {
    StreamSubscription<List<int>>? batteryLevelListener;
    try {
      batteryLevelListener = await getBleBatteryLevelListener(deviceId, onBatteryLevelChange: (int value) {
        debugPrint("Battery Level: $value%");
        setState(() {
          deviceName = deviceId.id;
          _isConnected = true;
          batteryPercentage = value;
        });
        // We cancel the listener, as we only needed the value once.
        batteryLevelListener?.cancel();
      });
      await Future.delayed(const Duration(seconds: 2));
      SharedPreferencesUtil().onboardingCompleted = true;
      MixpanelManager().onboardingCompleted();
      Navigator.of(context)
          .pushReplacement(MaterialPageRoute(builder: (c) => HomePageWrapper(btDevice: deviceId.toJson())));
    } catch (e) {
      print("Error fetching battery level: $e");
      batteryLevelListener?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    var screenSize = MediaQuery.of(context).size;
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 400,
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.asset(
                    "assets/images/stars.png",
                  ),
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      return Image.asset(
                        "assets/images/blob.png",
                        height: 300 * _animation.value,
                        width: 300 * _animation.value,
                      );
                    },
                  ),
                  // Image.asset("assets/images/blob.png"),
                  Image.asset("assets/images/herologo.png")
                ],
              ),
            ),
          ),
          !_isConnected
              ? Container(
                  margin: const EdgeInsets.fromLTRB(0, 0, 4, 12),
                  child: Text(
                    widget.deviceList.isEmpty
                        ? 'Searching for devices...'
                        : '${widget.deviceList.length} ${widget.deviceList.length == 1 ? "DEVICE" : "DEVICES"} FOUND NEARBY',
                    style: const TextStyle(
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      color: Color(0x66FFFFFF),
                    ),
                  ),
                )
              : Container(
                  margin: const EdgeInsets.fromLTRB(0, 0, 4, 12),
                  child: const Text(
                    'PAIRING SUCCESSFUL',
                    style: TextStyle(
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      color: Color(0x66FFFFFF),
                    ),
                  ),
                ),
          !_isConnected
              ? Expanded(
                  // Create a scrollable list of devices
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.deviceList.length,
                    itemBuilder: (context, index) {
                      final device = widget.deviceList[index];
                      if (device == null) return Container(); // If device is null, return an empty container

                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        padding: EdgeInsets.symmetric(horizontal: screenSize.width * 0, vertical: 0),
                        decoration: BoxDecoration(
                          border: const GradientBoxBorder(
                            gradient: LinearGradient(colors: [
                              Color.fromARGB(127, 208, 208, 208),
                              Color.fromARGB(127, 188, 99, 121),
                              Color.fromARGB(127, 86, 101, 182),
                              Color.fromARGB(127, 126, 190, 236)
                            ]),
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          color: const Color.fromARGB(0, 0, 0, 0),
                        ),
                        child: ListTile(
                          title: Text(
                            device.id.split('-').last.substring(0, 6),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 18,
                              color: Color(0xCCFFFFFF),
                            ),
                          ),
                          onTap: () async {
                            await bleConnectDevice(device.id);
                            await getBatteryPercentage(device);
                          },
                        ),
                      );
                    },
                  ),
                )
              : Text(
                  deviceName.split('-').last.substring(0, 6),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 18,
                    color: Color(0xCCFFFFFF),
                  ),
                ),
          if (_isConnected)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  '🔋 ${batteryPercentage.toString()}%',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 18,
                    color: batteryPercentage <= 25
                        ? Colors.red
                        : batteryPercentage > 25 && batteryPercentage <= 50
                            ? Colors.orange
                            : Colors.green,
                  ),
                ))
        ],
      ),
    );
  }
}
