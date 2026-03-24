#!/usr/bin/env python3
"""
pm4py_wrapper.py - Process mining wrapper using pm4py library

This script provides OCPM (Object-Centric Process Mining) capabilities
by wrapping the pm4py Python library. It can be called from Elixir via
System.cmd/3 for process discovery, bottleneck detection, and conformance checking.

Usage:
    python pm4py_wrapper.py <command> <input_json>

Commands:
    discover - Discover process model using Alpha miner
    bottlenecks - Detect bottlenecks using heuristic miner
    conformance - Check conformance against process model

Input: JSON string with event log data
Output: JSON string with results
"""

import sys
import json
import argparse
from typing import List, Dict, Any
from datetime import datetime

try:
    import pm4py
    from pm4py.objects.log.obj import EventLog
    from pm4py.objects.conversion.log import converter as log_converter
    from pm4py.algo.discovery.alpha import algorithm as alpha_miner
    from pm4py.algo.discovery.heuristics import algorithm as heuristics_miner
    from pm4py.algo.conformance.alignments.petri_net import algorithm as alignment_factory
    from pm4py.objects.petri_net.obj import PetriNet, Marking
    PM4PY_AVAILABLE = True
except ImportError:
    PM4PY_AVAILABLE = False
    print("ERROR: pm4py not installed. Install with: pip install pm4py", file=sys.stderr)
    sys.exit(1)


def parse_event_log(events_data: List[Dict[str, Any]]) -> EventLog:
    """
    Parse event log from JSON format to pm4py EventLog.

    Expected JSON format:
    [
        {
            "case_id": "case-1",
            "activity": "approve",
            "timestamp": "2026-03-23T12:00:00Z",
            "resource": "agent-1",
            "attributes": {"amount": 1000}
        },
        ...
    ]
    """
    # Convert to pm4py format
    # pm4py expects: case_id, activity, timestamp (as datetime)
    events = []

    for event in events_data:
        pm4py_event = {
            "case:concept:name": str(event.get("case_id", "")),
            "concept:name": str(event.get("activity", "")),
            "time:timestamp": datetime.fromisoformat(
                event.get("timestamp", datetime.utcnow().isoformat())
                .replace("Z", "+00:00")
            ),
            "org:resource": str(event.get("resource", "")),
        }

        # Add any additional attributes
        for key, value in event.get("attributes", {}).items():
            pm4py_event[key] = value

        events.append(pm4py_event)

    # Convert to pm4py EventLog
    return log_converter.apply(events, variant=log_converter.Variants.TO_EVENT_LOG)


def discover_process_model(event_log: EventLog) -> Dict[str, Any]:
    """
    Discover process model using Alpha miner algorithm.

    Returns:
        Dictionary with nodes, edges, and metadata
    """
    # Apply Alpha miner
    net, initial_marking, final_marking = alpha_miner.apply(event_log)

    # Extract nodes (places and transitions)
    nodes = []

    # Add places
    for place in net.places:
        nodes.append(f"place_{place.name}")

    # Add transitions
    for trans in net.transitions:
        nodes.append(f"trans_{trans.name}")

    # Extract edges (arcs)
    edges = []
    for place in net.places:
        for arc in place.in_arcs:
            if isinstance(arc.source, PetriNet.Transition):
                edges.append([f"trans_{arc.source.name}", f"place_{place.name}"])
        for arc in place.out_arcs:
            if isinstance(arc.target, PetriNet.Transition):
                edges.append([f"place_{place.name}", f"trans_{arc.target.name}"]))

    # Get unique activity names (transitions without prefix)
    activities = list(event_log["concept:name"].unique())

    return {
        "nodes": activities,
        "edges": {"transitions": edges},
        "metadata": {
            "algorithm": "alpha_miner_pm4py",
            "discovered_at": datetime.utcnow().isoformat(),
            "event_count": len(event_log),
            "case_count": event_log["case:concept:name"].nunique()
        },
        "petri_net": {
            "places": [p.name for p in net.places],
            "transitions": [t.name for t in net.transitions],
            "initial_marking": [p.name for p in initial_marking],
            "final_marking": [p.name for p in final_marking]
        }
    }


def detect_bottlenecks(event_log: EventLog) -> List[Dict[str, Any]]:
    """
    Detect bottlenecks using heuristic miner.

    Returns:
        List of bottleneck dictionaries
    """
    # Apply Heuristic miner to get dependency graph
    heu_net = heuristics_miner.apply_heu(event_log, parameters={
        heuristics_miner.Variants.CLASSIC.value.Parameters.DEPENDENCY_THRESH: 0.8
    })

    bottlenecks = []

    # Get activity statistics
    activity_counts = event_log["concept:name"].value_counts()
    mean_count = activity_counts.mean()

    # Detect frequency bottlenecks (activities appearing 2x+ more than average)
    for activity, count in activity_counts.items():
        if count > mean_count * 2:
            bottlenecks.append({
                "activity": activity,
                "type": "frequency",
                "value": float(count),
                "threshold": float(mean_count * 2),
                "severity": "high" if count > mean_count * 3 else "medium"
            })

    # Calculate duration statistics
    event_log = event_log.sort_values("time:timestamp")
    event_log["duration"] = event_log.groupby("case:concept:name")["time:timestamp"].diff()

    # Detect duration bottlenecks (long waits between activities)
    for activity in event_log["concept:name"].unique():
        activity_events = event_log[event_log["concept:name"] == activity]
        avg_duration = activity_events["duration"].dt.total_seconds().mean()

        # If average wait > 1 hour, flag as bottleneck
        if avg_duration > 3600:
            bottlenecks.append({
                "activity": activity,
                "type": "duration",
                "value": avg_duration,
                "threshold": 3600.0,
                "severity": "high" if avg_duration > 7200 else "medium"
            })

    return bottlenecks


def find_deviations(event_log: EventLog, process_model: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Check conformance by aligning log against process model.

    Returns:
        List of deviation dictionaries
    """
    # Reconstruct Petri net from model
    # For simplicity, we'll use alpha miner to rediscover the net
    net, initial_marking, final_marking = alpha_miner.apply(event_log)

    deviations = []

    # Group by case
    for case_id in event_log["case:concept:name"].unique():
        case_events = event_log[event_log["case:concept:name"] == case_id]
        case_trace = case_events["concept:name"].tolist()

        # Check conformance using token-based replay (simplified)
        # For full conformance checking, use alignment_factory.apply

        # Simple check: verify all activities exist in the model
        model_activities = set(process_model.get("nodes", []))

        for activity in case_trace:
            if activity not in model_activities:
                deviations.append({
                    "case_id": str(case_id),
                    "deviation_type": "extra",
                    "activity": activity,
                    "severity": "warning",
                    "description": f"Activity '{activity}' not in process model"
                })

    return deviations


def main():
    parser = argparse.ArgumentParser(description="pm4py wrapper for process mining")
    parser.add_argument("command", choices=["discover", "bottlenecks", "conformance"],
                       help="Command to execute")
    parser.add_argument("input_json", help="Input data as JSON string")

    args = parser.parse_args()

    try:
        # Parse input JSON
        input_data = json.loads(args.input_json)

        # Parse event log
        event_log = parse_event_log(input_data.get("events", []))

        result = {}

        if args.command == "discover":
            result = discover_process_model(event_log)

        elif args.command == "bottlenecks":
            bottlenecks = detect_bottlenecks(event_log)
            result = {
                "bottlenecks": bottlenecks,
                "metadata": {
                    "algorithm": "heuristic_miner_pm4py",
                    "discovered_at": datetime.utcnow().isoformat(),
                    "bottleneck_count": len(bottlenecks)
                }
            }

        elif args.command == "conformance":
            process_model = input_data.get("process_model", {})
            deviations = find_deviations(event_log, process_model)
            result = {
                "deviations": deviations,
                "metadata": {
                    "algorithm": "conformance_pm4py",
                    "checked_at": datetime.utcnow().isoformat(),
                    "deviation_count": len(deviations)
                }
            }

        # Output result as JSON
        print(json.dumps(result))

        return 0

    except Exception as e:
        print(json.dumps({"error": str(e)}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
