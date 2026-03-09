# Copyright Hewlett Packard Enterprise Development LP.

import otf2
import time

def read_otf2_events_only(archive_name):
    start_time = time.time()
    data = {'events': []}

    # Open the OTF2 archive
    with otf2.reader.open(archive_name) as trace:
        print("Trace Clock Properties:")
        print(f"  Timer Resolution.   : {trace.definitions.clock_properties.timer_resolution}")
        print(f"  Global Offset       : {trace.definitions.clock_properties.global_offset}")
        print(f"  Trace Length        : {trace.definitions.clock_properties.trace_length}")
        print(f"  Realtime Timestamp. : {trace.definitions.clock_properties.realtime_timestamp}")
        # Measure time taken to open the OTF2 archive
        open_end = time.time()
        print(f"Time taken to open OTF2 archive: {open_end - start_time:.2f} seconds")

        for location, event in trace.events:
            event_info = {}

            event_info['location'] = location.name
            if isinstance(event, otf2.events.ProgramBegin):
                print(f"Program Begin Event at location {location.name} with time {event.time}")
                print(f"Time from clock properties: {trace.definitions.clock_properties.global_offset}")
            if isinstance(event, otf2.events.Enter):
                event_info['event'] = 'Enter'
                event_info['region'] = event.region.name
            elif isinstance(event, otf2.events.Leave):
                event_info['event'] = 'Leave'
                event_info['region'] = event.region.name
            elif isinstance(event, otf2.events.Metric):
                event_info['event'] = 'Metric'
                event_info['metric'] = event.member.name
                event_info['value'] = event.value
            else:
                event_info['event'] = 'Unknown'

            data['events'].append(event_info)

        read_end_time = time.time()
        print(f"Time taken to read and process events: {read_end_time - open_end:.2f} seconds")
    total_time = time.time() - start_time
    print(f"Total time: {total_time:.2f} seconds")
    return data


# archive_name = "/workspace/scorep-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2"
archive_name = "/workspace/scorep-traces/simple-mi300-example-run/traces.otf2"

start_time = time.time()
data = read_otf2_events_only(archive_name)

end_time = time.time()
print(f"Total execution time: {end_time - start_time:.2f} seconds")

# Count and describe events
event_counts = {}
for event in data['events']:
    event_type = event.get('event', 'Unknown')
    event_counts[event_type] = event_counts.get(event_type, 0) + 1

total_events = len(data['events'])
print("\nEvent Summary:")
print(f"Total number of events: {total_events}")
print("Event types and their counts:")
for event_type, count in event_counts.items():
    print(f"  {event_type}: {count} events")


unique_locations = set(event.get('location', 'Unknown') for event in data['events'])
print(f"Total unique locations: {len(unique_locations)}")
# print("Unique locations:")
# for location in unique_locations:
    # print(f"  {location}")

unique_regions = set(event.get('region', 'Unknown') for event in data['events'])
print(f"Total unique regions: {len(unique_regions)}")
# print("Unique regions:")
# for region in unique_regions:
#     print(f"  {region}")

all_metrics = [event.get('metric', 'Unknown') for event in data['events'] if event.get('event') == 'Metric']
metrics = set(all_metrics)
print(f"Total metric events: {len(all_metrics)}")
print(f"Total unique metrics: {len(metrics)}")
print("Unique metrics:")
for metric in metrics:
    print(f"  {metric}")
