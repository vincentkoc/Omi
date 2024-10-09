import uuid
from datetime import datetime, timezone, timedelta
from enum import Enum

import opuslib
import webrtcvad
from fastapi import APIRouter
from fastapi.websockets import WebSocketDisconnect, WebSocket
from pydub import AudioSegment
from starlette.websockets import WebSocketState

import database.memories as memories_db
from database import redis_db
from models.memory import Memory, TranscriptSegment, MemoryStatus, Structured
from models.message_event import MemoryEvent, MessageEvent, MemoryBackwardSycnedEvent
from utils.memories.process_memory import process_memory
from utils.plugins import trigger_external_integrations
from utils.stt.streaming import *

router = APIRouter()


# Minor script generate wav from raw audio bytes
# import wave
# import os
#
# # Parameters for the WAV file
# sample_rate = 16000  # Assuming a sample rate of 16000 Hz
# channels = 1  # Mono audio
# sample_width = 2  # Assuming 16-bit audio (2 bytes per sample)
#
# # Read the raw audio data from the file
# with open("audio.raw", "rb") as raw_file:
#     raw_audio_data = raw_file.read()
#
# if __name__ == '__main__':
#     with wave.open("output.wav", "wb") as wav_file:
#         wav_file.setnchannels(channels)  # Set mono/stereo
#         wav_file.setsampwidth(sample_width)  # Set sample width to 16 bits (2 bytes)
#         wav_file.setframerate(sample_rate)  # Set sample rate to 16000 Hz
#         wav_file.writeframes(raw_audio_data)  # Write raw audio data to WAV

class STTService(str, Enum):
    deepgram = "deepgram"
    soniox = "soniox"
    speechmatics = "speechmatics"

    # auto = "auto"

    @staticmethod
    def get_model_name(value):
        if value == STTService.deepgram:
            return 'deepgram_streaming'
        elif value == STTService.soniox:
            return 'soniox_streaming'
        elif value == STTService.speechmatics:
            return 'speechmatics_streaming'


def retrieve_in_progress_memory(uid):
    memory_id = redis_db.get_in_progress_memory_id(uid)
    existing = None

    if memory_id:
        existing = memories_db.get_memory(uid, memory_id)
        if existing and existing['status'] != 'in_progress':
            existing = None

    if not existing:
        existing = memories_db.get_in_progress_memory(uid)
    return existing


async def _websocket_util(
        websocket: WebSocket, uid: str, language: str = 'en', sample_rate: int = 8000, codec: str = 'pcm8',
        channels: int = 1, include_speech_profile: bool = True
):
    print('_websocket_util', uid, language, sample_rate, codec, include_speech_profile)

    # Not when comes from the phone, and only Friend's with 1.0.4
    if language == 'en' and sample_rate == 16000 and codec == 'opus':
        stt_service = STTService.soniox
    else:
        stt_service = STTService.deepgram

    try:
        await websocket.accept()
    except RuntimeError as e:
        print(e)
        return

    # Initiate a separate vad for each websocket
    w_vad = webrtcvad.Vad()
    w_vad.set_mode(1)

    # Stream transcript
    loop = asyncio.get_event_loop()
    memory_creation_timeout = 120

    async def _send_message_event(msg: MessageEvent):
        print(f"Message: type ${msg.event_type}")
        try:
            await websocket.send_json(msg.to_json())
            return True
        except WebSocketDisconnect:
            print("WebSocket disconnected")
        except RuntimeError as e:
            print(f"Can not send message event, error: {e}")

        return False

    async def _trigger_create_memory_with_delay(delay_seconds: int):
        # print('memory_creation_timer', delay_seconds)
        try:
            await asyncio.sleep(delay_seconds)
            await _create_current_memory()
        except asyncio.CancelledError:
            pass

    async def _create_memory(memory: dict):
        memory = Memory(**memory)
        if memory.status != MemoryStatus.processing:
            asyncio.create_task(_send_message_event(MemoryEvent(event_type="memory_processing_started", memory=memory)))
            memories_db.update_memory_status(uid, memory.id, MemoryStatus.processing)
            memory.status = MemoryStatus.processing

        try:
            memory = process_memory(uid, language, memory)
            messages = trigger_external_integrations(uid, memory)
        except Exception as e:
            print(f"Error processing memory: {e}")
            memories_db.set_memory_as_discarded(uid, memory.id)
            memory.discarded = True
            messages = []

        asyncio.create_task(
            _send_message_event(MemoryEvent(event_type="memory_created", memory=memory, messages=messages))
        )

    async def finalize_processing_memories(processing: List[dict]):
        # handle edge case of memory was actually processing? maybe later, doesn't hurt really anyway.
        # also fix from getMemories endpoint?
        print('finalize_processing_memories len(processing):', len(processing))
        for memory in processing:
            await _create_memory(memory)

    processing = memories_db.get_processing_memories(uid)
    asyncio.create_task(finalize_processing_memories(processing))

    async def _create_current_memory():
        print("_create_current_memory")
        # Reset state variables
        nonlocal seconds_to_trim
        nonlocal seconds_to_add
        seconds_to_trim = None
        seconds_to_add = None

        memory = retrieve_in_progress_memory(uid)
        if not memory or not memory['transcript_segments']:
            return
        await _create_memory(memory)

    memory_creation_task_lock = False
    memory_creation_task = None
    seconds_to_trim = None
    seconds_to_add = None

    # Determine previous disconnected socket seconds to add + start processing timer if a memory in progress
    if existing_memory := retrieve_in_progress_memory(uid):
        # segments seconds alignment
        started_at = datetime.fromisoformat(existing_memory['started_at'].isoformat())
        seconds_to_add = (datetime.now(timezone.utc) - started_at).total_seconds()

        # processing if needed logic
        finished_at = datetime.fromisoformat(existing_memory['finished_at'].isoformat())
        seconds_since_last_segment = (datetime.now(timezone.utc) - finished_at).total_seconds()
        if seconds_since_last_segment >= memory_creation_timeout:
            asyncio.create_task(_create_current_memory())
        else:
            memory_creation_task = asyncio.create_task(
                _trigger_create_memory_with_delay(memory_creation_timeout - seconds_since_last_segment)
            )

    def _get_or_create_in_progress_memory(segments: List[dict]):
        if existing := retrieve_in_progress_memory(uid):
            # print('_get_or_create_in_progress_memory existing', existing['id'])
            memory = Memory(**existing)
            memory.transcript_segments = TranscriptSegment.combine_segments(
                memory.transcript_segments, [TranscriptSegment(**segment) for segment in segments]
            )
            redis_db.set_in_progress_memory_id(uid, memory.id)
            return memory

        started_at = datetime.now(timezone.utc) - timedelta(seconds=segments[0]['end'] - segments[0]['start'])
        memory = Memory(
            id=str(uuid.uuid4()),
            uid=uid,
            structured=Structured(),
            language=language,
            created_at=started_at,
            started_at=started_at,
            finished_at=datetime.now(timezone.utc),
            transcript_segments=[TranscriptSegment(**segment) for segment in segments],
            status=MemoryStatus.in_progress,
        )
        print('_get_in_progress_memory new', memory)
        memories_db.upsert_memory(uid, memory_data=memory.dict())
        redis_db.set_in_progress_memory_id(uid, memory.id)
        return memory

    async def create_memory_creation_task():
        nonlocal memory_creation_task
        nonlocal memory_creation_task_lock

        if memory_creation_task_lock:
            return

        memory_creation_task_lock = True
        try:
            if memory_creation_task is not None:
                memory_creation_task.cancel()
                try:
                    await memory_creation_task
                except asyncio.CancelledError:
                    print("memory_creation_task is cancelled now")
            memory_creation_task = asyncio.create_task(_trigger_create_memory_with_delay(memory_creation_timeout))

        finally:
            memory_creation_task_lock = False

    def stream_transcript(segments, _):
        nonlocal websocket
        nonlocal seconds_to_trim

        if not segments or len(segments) == 0:
            return

        # Align the start, end segment
        if seconds_to_trim is None:
            seconds_to_trim = segments[0]["start"]

        asyncio.run_coroutine_threadsafe(create_memory_creation_task(), loop)

        # Segments aligning duration seconds.
        if seconds_to_add:
            for i, segment in enumerate(segments):
                segment["start"] += seconds_to_add
                segment["end"] += seconds_to_add
                segments[i] = segment
        elif seconds_to_trim:
            for i, segment in enumerate(segments):
                segment["start"] -= seconds_to_trim
                segment["end"] -= seconds_to_trim
                segments[i] = segment

        asyncio.run_coroutine_threadsafe(websocket.send_json(segments), loop)

        memory = _get_or_create_in_progress_memory(segments)  # can trigger race condition? increase soniox utterance?
        memories_db.update_memory_segments(uid, memory.id, [s.dict() for s in memory.transcript_segments])
        memories_db.update_memory_finished_at(uid, memory.id, datetime.now(timezone.utc))

        # threading.Thread(target=process_segments, args=(uid, segments)).start() # restore when plugins work

    soniox_socket = None
    speechmatics_socket = None
    deepgram_socket = None
    deepgram_socket2 = None

    speech_profile_duration = 0
    try:
        file_path, speech_profile_duration = None, 0
        # TODO: how bee does for recognizing other languages speech profile
        if language == 'en' and (codec == 'opus' or codec == 'pcm16') and include_speech_profile:
            file_path = get_profile_audio_if_exists(uid)
            speech_profile_duration = AudioSegment.from_wav(file_path).duration_seconds + 5 if file_path else 0

        # DEEPGRAM
        if stt_service == STTService.deepgram:
            deepgram_socket = await process_audio_dg(
                stream_transcript, 1, language, sample_rate, 1, preseconds=speech_profile_duration
            )
            if speech_profile_duration:
                deepgram_socket2 = await process_audio_dg(
                    stream_transcript, 2, language, sample_rate, 1
                )

                async def deepgram_socket_send(data):
                    return deepgram_socket.send(data)

                await send_initial_file_path(file_path, deepgram_socket_send)
        # SONIOX
        elif stt_service == STTService.soniox:
            soniox_socket = await process_audio_soniox(
                stream_transcript, 1, sample_rate, language,
                uid if include_speech_profile else None
            )
        # SPEECHMATICS
        elif stt_service == STTService.speechmatics:
            speechmatics_socket = await process_audio_speechmatics(
                stream_transcript, 1, sample_rate, language, preseconds=speech_profile_duration
            )
            if speech_profile_duration:
                await send_initial_file_path(file_path, speechmatics_socket.send)
                print('speech_profile speechmatics duration', speech_profile_duration)

    except Exception as e:
        print(f"Initial processing error: {e}")
        websocket_close_code = 1011
        await websocket.close(code=websocket_close_code)
        return

    decoder = opuslib.Decoder(sample_rate, 1)
    websocket_active = True
    websocket_close_code = 1001  # Going Away, don't close with good from backend

    async def receive_audio(dg_socket1, dg_socket2, soniox_socket, speechmatics_socket1):
        nonlocal websocket_active
        nonlocal websocket_close_code

        timer_start = time.time()
        # f = open("audio.bin", "ab")
        try:
            while websocket_active:
                data = await websocket.receive_bytes()
                # save the data to a file
                # data_length = len(data)
                # f.write(struct.pack('I', data_length))  # Write length as 4 bytes
                # f.write(data)

                if codec == 'opus' and sample_rate == 16000:
                    data = decoder.decode(bytes(data), frame_size=160)
                if uid not in ['QnwpAf9QjLg5taNlT5OZ4kVnOLH3']:
                    if include_speech_profile:
                        vad_sample_size = 320 if sample_rate == 16000 else 160
                        vad_sample = data[:vad_sample_size]
                        if len(vad_sample) < vad_sample_size:
                            # print('VAD sample is less than 320 bytes', len(vad_sample))
                            vad_sample = vad_sample + bytes([0x00] * (vad_sample_size - len(vad_sample)))
                        has_speech = w_vad.is_speech(vad_sample, sample_rate)
                        if not has_speech:
                            continue

                # TODO: is the VAD slowing down the STT service? specially soniox?
                # - but from write data, it feels faster, but the processing is having issues
                # - and soniox after missingn a couple filtered bytes get's slower
                # - specially after waiting for like a couple seconds.

                if soniox_socket is not None:
                    await soniox_socket.send(data)

                if speechmatics_socket1 is not None:
                    await speechmatics_socket1.send(data)

                if dg_socket1 is not None:
                    elapsed_seconds = time.time() - timer_start
                    if elapsed_seconds > speech_profile_duration or not dg_socket2:
                        dg_socket1.send(data)
                        if dg_socket2:
                            print('Killing socket2')
                            dg_socket2.finish()
                            dg_socket2 = None
                    else:
                        dg_socket2.send(data)

        except WebSocketDisconnect:
            print("WebSocket disconnected")
        except Exception as e:
            print(f'Could not process audio: error {e}')
            websocket_close_code = 1011
        finally:
            websocket_active = False
            if dg_socket1:
                dg_socket1.finish()
            if dg_socket2:
                dg_socket2.finish()
            if soniox_socket:
                await soniox_socket.close()
            if speechmatics_socket:
                await speechmatics_socket.close()

    # heart beat
    started_at = time.time()
    timeout_seconds = 420  # 7m # Soft timeout, should < MODAL_TIME_OUT - 3m

    async def send_heartbeat():
        nonlocal websocket_active
        nonlocal websocket_close_code
        nonlocal started_at
        try:
            while websocket_active:
                await asyncio.sleep(30)
                # print('send_heartbeat')
                if websocket.client_state == WebSocketState.CONNECTED:
                    await websocket.send_json({"type": "ping"})
                else:
                    break

                # timeout
                if time.time() - started_at >= timeout_seconds:
                    print(f"Session timeout is hit by soft timeout {timeout_seconds}")
                    websocket_close_code = 1001
                    websocket_active = False
        except WebSocketDisconnect:
            print("WebSocket disconnected")
        except Exception as e:
            print(f'Heartbeat error: {e}')
            websocket_close_code = 1011
        finally:
            websocket_active = False

    try:
        receive_task = asyncio.create_task(
            receive_audio(deepgram_socket, deepgram_socket2, soniox_socket, speechmatics_socket)
        )
        heartbeat_task = asyncio.create_task(send_heartbeat())
        await asyncio.gather(receive_task, heartbeat_task)

    except Exception as e:
        print(f"Error during WebSocket operation: {e}")
    finally:
        websocket_active = False
        if websocket.client_state == WebSocketState.CONNECTED:
            try:
                await websocket.close(code=websocket_close_code)
            except Exception as e:
                print(f"Error closing WebSocket: {e}")


@router.websocket("/v2/listen")
async def websocket_endpoint(
        websocket: WebSocket, uid: str, language: str = 'en', sample_rate: int = 8000, codec: str = 'pcm8',
        channels: int = 1, include_speech_profile: bool = True,
):
    await _websocket_util(websocket, uid, language, sample_rate, codec, include_speech_profile)


#
# Listen backward
#


async def _websocket_util_backward(
        websocket: WebSocket, uid: str, language: str = 'en', file_names: List[str] = [],
):
    print('websocket_endpoint_backward', uid, language, file_names)

    try:
        await websocket.accept()
    except RuntimeError as e:
        print(e)
        return

    async def _send_message_event(msg: MessageEvent):
        print(f"Message: type ${msg.event_type}")
        try:
            await websocket.send_json(msg.to_json())
            return True
        except WebSocketDisconnect:
            print("WebSocket disconnected")
        except RuntimeError as e:
            print(f"Can not send message event, error: {e}")

        return False

    websocket_close_code = 1011
    websocket_active = True
    try:
        while websocket_active:
            try:
                data = await websocket.receive_bytes()
                head = int.from_bytes(data[:4])
                if head == 0:  # 0000, end
                    print(f"Sync end {len(file_names)}")
                    websocket_active = False
                    break
                if head != 1:  # 0001, new file
                    print(f"Not new file head {head}")
                    continue

                # file name
                file_idx = int.from_bytes(data[4:8])  # index
                if file_idx < 0 or file_idx > len(file_names):
                    print(f"File index is invalid {file_idx}, file names: {len(file_names)}")
                    continue
                file_name = file_names[file_idx]
                content_length = int.from_bytes(data[8:12])  # length
                print(f"sync backward head: {head} index: {file_idx} file_name: {file_name} length: {content_length}")

                content = data[12:]  # format: frames, [4 first bytes is the length then frame bytes]
                # print(list(content[:100]))

                # TODO: FIXME, sync to file or do transcribe

                asyncio.create_task(
                    _send_message_event(MemoryBackwardSycnedEvent(event_type="memory_backward_synced", name=file_name)))

            except Exception as e:
                print(e)
                websocket_active = False
                return
    finally:
        websocket_active = False
        if websocket.client_state == WebSocketState.CONNECTED:
            try:
                await websocket.close(code=websocket_close_code)
            except Exception as e:
                print(f"Error closing WebSocket: {e}")


@router.websocket("/v2/listen/backward")
async def websocket_endpoint_backward(
        websocket: WebSocket, uid: str, language: str = 'en', file_names: str = '',
):
    await _websocket_util_backward(websocket, uid, language, file_names.split(",") if len(file_names) > 0 else [])
