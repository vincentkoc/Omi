import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:friend_private/utils/ble/communication.dart';
import 'package:instabug_flutter/instabug_flutter.dart';
import 'package:intl/intl.dart';
import 'package:opus_dart/opus_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tuple/tuple.dart';

class WavBytesUtil {
  BleAudioCodec codec;
  List<List<int>> frames = [];
  final SimpleOpusDecoder opusDecoder = SimpleOpusDecoder(sampleRate: 16000, channels: 1);

  WavBytesUtil({this.codec = BleAudioCodec.pcm8});

  // needed variables for `storeFramePacket`
  int lastPacketIndex = -1;
  int lastFrameId = -1;
  List<int> pending = [];
  int lost = 0;

  void storeFramePacket(value) {
    int index = value[0] + (value[1] << 8);
    int internal = value[2];
    List<int> content = value.sublist(3);

    // Start of a new frame
    if (lastPacketIndex == -1 && internal == 0) {
      lastPacketIndex = index;
      lastFrameId = internal;
      pending = content;
      return;
    }

    if (lastPacketIndex == -1) return;

    // Lost frame - reset state
    if (index != lastPacketIndex + 1 || (internal != 0 && internal != lastFrameId + 1)) {
      debugPrint('Lost frame');
      lastPacketIndex = -1;
      pending = [];
      lost += 1;
      return;
    }

    // Start of a new frame
    if (internal == 0) {
      frames.add(pending); // Save frame
      pending = content; // Start new frame
      lastFrameId = internal; // Update internal frame id
      lastPacketIndex = index; // Update packet id
      // debugPrint('Frames received: ${frames.length} && Lost: $lost');
      return;
    }

    // Continue frame
    pending.addAll(content);
    lastFrameId = internal; // Update internal frame id
    lastPacketIndex = index; // Update packet id
  }

  void removeFramesRange({
    int fromSecond = 0, // unused
    int toSecond = 0,
  }) {
    debugPrint('removing frames from ${fromSecond}s to ${toSecond}s');
    frames.removeRange(fromSecond * 100, min(toSecond * 100, frames.length));
    debugPrint('frames length: ${frames.length}');
  }

  void insertAudioBytes(List<List<int>> bytes) => frames.insertAll(0, bytes);

  void clearAudioBytes() => frames.clear();

  bool hasFrames() => frames.isNotEmpty;

  /*
  * DOUBLE CHECKING STORE FILES
  * */

  // static Future<void> printSharedPreferencesFileSize() async {
  //   final file = File(
  //       '/var/mobile/Containers/Data/Application/987446B3-3A14-4AE6-9EE7-3BBEFC4DBE04/Library/Preferences/com.friend-app-with-wearable.ios12.plist');
  //
  //   if (await file.exists()) {
  //     final fileSize = await file.length();
  //     print('SharedPreferences file size: ${formatBytes(fileSize)} bytes');
  //   } else {
  //     print('SharedPreferences file not found');
  //   }
  // }

  static Future<void> listFiles(Directory? directory) async {
    if (directory == null) return;
    final totalBytes = await _getDirectorySize(directory);

    final totalSize = formatBytes(totalBytes);
    debugPrint('Total size of $directory: $totalSize');
  }

  static Future<int> _getDirectorySize(Directory dir) async {
    int totalBytes = 0;

    try {
      if (dir.existsSync()) {
        final List<FileSystemEntity> entities = dir.listSync(recursive: true, followLinks: false);
        for (var entity in entities) {
          if (entity is File) {
            // debugPrint('File: ${entity.path}');
            totalBytes += await entity.length();
          } else if (entity is Directory) {
            // debugPrint('Directory: ${entity.path}');
            totalBytes += await _getDirectorySize(entity);
          }
        }
      }
    } catch (e) {
      debugPrint("Error calculating directory size: $e");
    }

    return totalBytes;
  }

  static String formatBytes(int bytes, {int decimals = 2}) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    var size = (bytes / pow(1024, i)).toStringAsFixed(decimals);
    return "$size ${suffixes[i]}";
  }

  static Future<Directory> getDir() => getTemporaryDirectory();

  /*
  * FINISHED TESTING LOGIC
  * */

  static clearTempWavFiles() async {
    var file0 = File('${(await getDir()).path}/temp.wav');
    if (file0.existsSync()) file0.deleteSync();

    final directory = await getApplicationDocumentsDirectory();
    file0 = File('${directory.path}/temp.wav');
    if (file0.existsSync()) file0.deleteSync();

    if (directory.existsSync()) {
      final List<FileSystemEntity> entities = directory.listSync(recursive: false, followLinks: false);
      for (var entity in entities) {
        if (entity is File && entity.path.endsWith('.wav')) {
          debugPrint('Removing file: ${entity.path}');
          await entity.delete();
        }
      }
    }

    // for (var i = 1; i < 10; i++) {
    //   var file = File('${directory.path}/temp$i.wav');
    //   if (file.existsSync()) file.deleteSync();
    // }
  }

  static tempWavExists() async {
    final directory = await getDir();
    var file0 = File('${directory.path}/temp.wav');
    return file0.existsSync();
  }

  static deleteTempWav() async {
    final directory = await getDir();
    var file0 = File('${directory.path}/temp.wav');
    if (file0.existsSync()) file0.deleteSync();
  }

  Future<Tuple2<File, List<List<int>>>> createWavFile({String? filename, int removeLastNSeconds = 0}) async {
    debugPrint('createWavFile $filename');
    List<List<int>> framesCopy;
    if (removeLastNSeconds > 0) {
      removeFramesRange(fromSecond: (frames.length ~/ 100) - removeLastNSeconds, toSecond: frames.length ~/ 100);
      framesCopy = List<List<int>>.from(frames); // after trimming, copy the frames
    } else {
      framesCopy = List<List<int>>.from(frames); // copy the frames before clearing all
      clearAudioBytes();
    }
    File file = await createWavByCodec(framesCopy, filename: filename);
    return Tuple2(file, framesCopy);
  }

  /// OPUS

  Future<File> createWavByCodec(List<List<int>> frames, {String? filename}) async {
    Uint8List wavBytes;
    if (codec == BleAudioCodec.pcm8 || codec == BleAudioCodec.pcm16) {
      Int16List samples = getPcmSamples(frames);
      // TODO: try pcm16
      wavBytes = getUInt8ListBytes(samples, codec == BleAudioCodec.pcm8 ? 8000 : 16000);
    } else if (codec == BleAudioCodec.mulaw8 || codec == BleAudioCodec.mulaw16) {
      throw UnimplementedError('mulaw codec not implemented');
      // Int16List samples = getMulawSamples(frames);
      // wavBytes = getUInt8ListBytes(samples, codec == BleAudioCodec.mulaw8 ? 8000 : 16000);
    } else if (codec == BleAudioCodec.opus) {
      List<int> decodedSamples = [];
      for (var frame in frames) {
        decodedSamples.addAll(opusDecoder.decode(input: Uint8List.fromList(frame)));
      }
      wavBytes = getUInt8ListBytes(decodedSamples, 16000);
    } else {
      CrashReporting.reportHandledCrash(UnimplementedError('unknown codec'), StackTrace.current,
          level: NonFatalExceptionLevel.error);
      throw UnimplementedError('unknown codec');
    }
    return createWav(wavBytes, filename: filename);
  }

  Future<File> createWav(Uint8List wavBytes, {String? filename}) async {
    final directory = await getDir();
    if (filename == null) {
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      filename = 'recording-$timestamp.wav';
    }
    final file = File('${directory.path}/$filename');
    await file.writeAsBytes(wavBytes);
    debugPrint('WAV file created: ${file.path}');
    return file;
  }

  Uint8List getUInt8ListBytes(List<int> audioBytes, int sampleRate) {
    // https://discord.com/channels/1192313062041067520/1231903583717425153/1256187110554341386
    // https://github.com/BasedHardware/Friend/blob/main/docs/_developer/Protocol.md
    Uint8List wavHeader = getWavHeader(audioBytes.length * 2, sampleRate);
    return Uint8List.fromList(wavHeader + WavBytesUtil.convertToLittleEndianBytes(audioBytes));
  }

  // Utility to convert audio data to little-endian format
  static Uint8List convertToLittleEndianBytes(List<int> audioData) {
    final byteData = ByteData(2 * audioData.length);
    for (int i = 0; i < audioData.length; i++) {
      byteData.setUint16(i * 2, audioData[i], Endian.little);
    }
    return byteData.buffer.asUint8List();
  }

  static Uint8List getWavHeader(int dataLength, int sampleRate, {int sampleWidth = 2, int channelCount = 1}) {
    final byteData = ByteData(44);
    final size = dataLength + 36;

    // RIFF chunk
    byteData.setUint8(0, 0x52); // 'R'
    byteData.setUint8(1, 0x49); // 'I'
    byteData.setUint8(2, 0x46); // 'F'
    byteData.setUint8(3, 0x46); // 'F'
    byteData.setUint32(4, size, Endian.little);
    byteData.setUint8(8, 0x57); // 'W'
    byteData.setUint8(9, 0x41); // 'A'
    byteData.setUint8(10, 0x56); // 'V'
    byteData.setUint8(11, 0x45); // 'E'

    // fmt chunk
    byteData.setUint8(12, 0x66); // 'f'
    byteData.setUint8(13, 0x6D); // 'm'
    byteData.setUint8(14, 0x74); // 't'
    byteData.setUint8(15, 0x20); // ' '
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little); // Audio format (1 = PCM)
    byteData.setUint16(22, channelCount, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * channelCount * sampleWidth, Endian.little);
    byteData.setUint16(32, channelCount * sampleWidth, Endian.little);
    byteData.setUint16(34, sampleWidth * 8, Endian.little);

    // data chunk
    byteData.setUint8(36, 0x64); // 'd'
    byteData.setUint8(37, 0x61); // 'a'
    byteData.setUint8(38, 0x74); // 't'
    byteData.setUint8(39, 0x61); // 'a'
    byteData.setUint32(40, dataLength, Endian.little);

    return byteData.buffer.asUint8List();
  }

  Int16List getPcmSamples(List<List<int>> frames) {
    int totalLength = frames.fold(0, (sum, frame) => sum + frame.length);

    // Create an Int16List to store the samples
    Int16List samples = Int16List(totalLength ~/ 2);
    int sampleIndex = 0;

    // Iterate through each frame and each byte in the frame
    for (int i = 0; i < frames.length; i++) {
      for (int j = 0; j < frames[i].length; j += 2) {
        int byte1 = frames[i][j];
        int byte2 = frames[i][j + 1];
        int sample = (byte2 << 8) | byte1;
        samples[sampleIndex++] = sample;
      }
    }
    return samples;
  }

  Int16List getMulawSamples(List<List<int>> frames) {
    int totalLength = frames.fold(0, (sum, frame) => sum + frame.length);
    Int16List samples = Int16List(totalLength);
    int sampleIndex = 0;
    for (List<int> frame in frames) {
      for (int i = 0; i < frame.length; i++) {
        samples[sampleIndex++] = frame[i];
      }
    }

    return samples;
  }
}

class ImageBytesUtil {
  int previousChunkId = -1;
  Uint8List _buffer = Uint8List(0);

  Uint8List? processChunk(List<int> data) {
    // debugPrint('Received chunk: ${data.length} bytes');
    if (data.isEmpty) return null;

    if (data[0] == 255 && data[1] == 255) {
      debugPrint('Received end of image');
      previousChunkId = -1;
      return _buffer;
    }

    int packetId = data[0] + (data[1] << 8);
    data = data.sublist(2);
    // debugPrint('Packet ID: $packetId - Previous ID: $previousChunkId');

    if (previousChunkId == -1) {
      if (packetId == 0) {
        debugPrint('Starting new image');
        _buffer = Uint8List(0);
      } else {
        // debugPrint('Skipping frame');
        return null;
      }
    } else {
      if (packetId != previousChunkId + 1) {
        debugPrint('Lost packet ~ lost image');
        _buffer = Uint8List(0);
        previousChunkId = -1;
        return null;
      }
    }
    previousChunkId = packetId;
    _buffer = Uint8List.fromList([..._buffer, ...data]);
    // debugPrint('Added to buffer, new size: ${_buffer.length}');
    return null;
  }
}
