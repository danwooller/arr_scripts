import asyncio
import time
from datetime import datetime
from zoneinfo import ZoneInfo
import aiohttp
from matter_server.client import MatterClient
from chip.clusters import Objects as clusters

WS_URL = "ws://localhost:5580/ws"

# Matter Epoch: 2000-01-01 00:00:00 UTC (Unix timestamp: 946684800)
MATTER_EPOCH_OFFSET = 946684800

async def main():
    # Automatically compute UK UTC offset in seconds (3600 in BST, 0 in GMT)
    uk_time = datetime.now(ZoneInfo("Europe/London"))
    tz_offset_seconds = int(uk_time.utcoffset().total_seconds())

    async with aiohttp.ClientSession() as session:
        async with MatterClient(WS_URL, session) as client:
            await client.connect()
            listen_task = asyncio.create_task(client.start_listening())
            await asyncio.sleep(1)

            now_sec = int(time.time() - MATTER_EPOCH_OFFSET)
            now_us = int((time.time() - MATTER_EPOCH_OFFSET) * 1_000_000)

            for node in client.get_nodes():
                node_id = node.node_id
                
                # Verify Endpoint 0 supports Time Synchronization (Cluster ID 56 / 0x0038)
                ep0 = node.endpoints.get(0)
                if not ep0 or 56 not in ep0.clusters:
                    print(f"Skipping Node {node_id} (No Time Synchronization cluster)")
                    continue

                print(f"=== Syncing ALPSTUGA Node {node_id} ===")

                # 1. Set Time Zone (+3600s BST or 0s GMT based on Europe/London)
                try:
                    tz_struct = clusters.TimeSynchronization.Structs.TimeZoneStruct(
                        offset=tz_offset_seconds,
                        validAt=0
                    )
                    tz_cmd = clusters.TimeSynchronization.Commands.SetTimeZone(
                        timeZone=[tz_struct]
                    )
                    await client.send_device_command(node_id, 0, tz_cmd)
                    print(f"  [✓] SetTimeZone ({tz_offset_seconds}s)")
                except Exception as e:
                    print(f"  [x] SetTimeZone failed: {e!r}")

                # 2. Set DST Offset (0s, handled via TimeZone offset)
                try:
                    dst_struct = clusters.TimeSynchronization.Structs.DSTOffsetStruct(
                        offset=0,
                        validStarting=max(0, now_sec - 3600),
                        validUntil=now_sec + 31536000
                    )
                    dst_cmd = clusters.TimeSynchronization.Commands.SetDSTOffset(
                        DSTOffset=[dst_struct]
                    )
                    await client.send_device_command(node_id, 0, dst_cmd)
                    print("  [✓] SetDSTOffset (0s)")
                except Exception as e:
                    print(f"  [x] SetDSTOffset failed: {e!r}")

                # 3. Send UTC Time (Microseconds)
                try:
                    utc_cmd = clusters.TimeSynchronization.Commands.SetUTCTime(
                        UTCTime=now_us,
                        granularity=clusters.TimeSynchronization.Enums.GranularityEnum.kSecondsGranularity,
                        timeSource=clusters.TimeSynchronization.Enums.TimeSourceEnum.kAdmin
                    )
                    await client.send_device_command(node_id, 0, utc_cmd)
                    print(f"  [✓] SetUTCTime command sent ({now_us} us)")
                except Exception as e:
                    print(f"  [x] SetUTCTime command failed: {e!r}")

            listen_task.cancel()

asyncio.run(main())
