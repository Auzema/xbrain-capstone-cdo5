#!/usr/bin/env python3
import os
import sys
import json
import httpx
import asyncio
import hashlib
import argparse
from typing import Dict, List, Any, Optional

DEFAULT_SIMULATOR_URL = "http://localhost:8080/dumbproxy/inject-batch"

def clean_id(raw_id: Any, length: int) -> Optional[str]:
    if not raw_id:
        return None
    raw_str = str(raw_id)
    # Check if already a valid hex of the correct length
    if len(raw_str) == length and all(c in "0123456789abcdefABCDEF" for c in raw_str):
        return raw_str.lower()
    # Otherwise generate a stable hex by hashing
    hashed = hashlib.md5(raw_str.encode("utf-8")).hexdigest()
    return hashed[:length]

def parse_metrics(data: Any, tenant: str, env: str) -> List[Dict[str, Any]]:
    if not data:
        return []
    if isinstance(data, dict):
        data = [data]
    
    payloads = []
    for item in data:
        points = item.get("points", [])
        value = float(points[-1]["value"]) if points else 0.0
        
        labels = {
            "tenant_id": item.get("tenant_id") or tenant,
            "service": item.get("service") or "unknown",
            "environment": item.get("environment") or env,
        }
        if "labels" in item and isinstance(item["labels"], dict):
            labels.update(item["labels"])
            
        payloads.append({
            "name": item.get("metric_name") or "custom_metric",
            "type": "gauge",
            "value": value,
            "labels": labels
        })
    return payloads

def parse_logs(data: Any, tenant: str, env: str) -> List[Dict[str, Any]]:
    if not data:
        return []
    if isinstance(data, dict):
        data = [data]
        
    payloads = []
    for item in data:
        labels = {}
        if "labels" in item and isinstance(item["labels"], dict):
            labels.update(item["labels"])
            
        payloads.append({
            "tenant_id": item.get("tenant_id") or tenant,
            "service": item.get("service") or "unknown",
            "environment": item.get("environment") or env,
            "level": item.get("level") or "info",
            "message": item.get("message") or "",
            "trace_id": item.get("trace_id"),
            "timestamp": item.get("ts") or item.get("timestamp"),
            "labels": labels
        })
    return payloads

def parse_traces(data: Any, tenant: str, env: str) -> List[Dict[str, Any]]:
    if not data:
        return []
    if isinstance(data, dict):
        data = [data]
        
    payloads = []
    for item in data:
        trace_id = clean_id(item.get("trace_id"), 32)
        span_id = clean_id(item.get("span_id"), 16)
        parent_span_id = clean_id(item.get("parent_span_id"), 16)
        
        labels = {}
        if "labels" in item and isinstance(item["labels"], dict):
            labels.update(item["labels"])
            
        payloads.append({
            "tenant_id": item.get("tenant_id") or tenant,
            "service": item.get("service") or "unknown",
            "environment": item.get("environment") or env,
            "trace_id": trace_id,
            "span_id": span_id,
            "parent_span_id": parent_span_id,
            "operation": item.get("operation") or "span",
            "duration_ms": float(item.get("duration_ms", 10.0)),
            "status_code": str(item.get("status_code", "200")),
            "timestamp": item.get("ts") or item.get("timestamp"),
            "labels": labels
        })
    return payloads

def locate_fake_data_dir() -> str:
    # Try local workspace simulator
    script_dir = os.path.dirname(os.path.abspath(__file__))
    local_sim_dir = os.path.abspath(os.path.join(script_dir, "..", "apps", "simulator", "fake-data"))
    if os.path.exists(local_sim_dir):
        return local_sim_dir
    # Try alternative paths or parent folders
    alternative = os.path.abspath(os.path.join(script_dir, "..", "fake-data"))
    if os.path.exists(alternative):
        return alternative
    # User's other path
    user_state_path = r"c:\Users\THANH TRUNG\Desktop\Xbrain\App_captone_phase2\Xbrain_fake_data\fake-data"
    if os.path.exists(user_state_path):
        return user_state_path
    return ""

async def send_payload(url: str, payload: dict):
    print(f"\n🚀 Sending payload to: {url}...")
    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(url, json=payload, timeout=10.0)
            print(f"🔹 Status Code: {response.status_code}")
            print(f"🔹 Response Body: {json.dumps(response.json(), indent=2)}")
            if response.status_code in [200, 202]:
                print("✅ Telemetry batch injected successfully!")
            else:
                print("⚠️ Injection completed but received non-success status code.")
        except Exception as e:
            print(f"❌ Failed to send request: {e}")

def load_json_file(path: str) -> Any:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"⚠️ Error reading/parsing {path}: {e}")
        return None

def process_and_build_batch(
    metrics_files: List[str], 
    logs_files: List[str], 
    traces_files: List[str], 
    tenant: str, 
    env: str
) -> Dict[str, Any]:
    batch = {
        "metrics": [],
        "logs": [],
        "traces": []
    }
    
    # Process Metrics
    for f_path in metrics_files:
        data = load_json_file(f_path)
        if data:
            batch["metrics"].extend(parse_metrics(data, tenant, env))
            
    # Process Logs
    for f_path in logs_files:
        data = load_json_file(f_path)
        if data:
            batch["logs"].extend(parse_logs(data, tenant, env))
            
    # Process Traces
    for f_path in traces_files:
        data = load_json_file(f_path)
        if data:
            batch["traces"].extend(parse_traces(data, tenant, env))
            
    return batch

def get_files_recursively(directory: str, extensions=[".json"]) -> List[str]:
    files_list = []
    if not os.path.exists(directory):
        return files_list
    for root, _, files in os.walk(directory):
        for file in files:
            if any(file.endswith(ext) for ext in extensions):
                files_list.append(os.path.join(root, file))
    return files_list

def select_scenario(fake_data_dir: str) -> Optional[str]:
    scenarios_dir = os.path.join(fake_data_dir, "scenarios")
    if not os.path.exists(scenarios_dir):
        print(f"❌ Scenarios directory not found at: {scenarios_dir}")
        return None
        
    scenarios = [d for d in os.listdir(scenarios_dir) if os.path.isdir(os.path.join(scenarios_dir, d))]
    scenarios.sort()
    
    if not scenarios:
        print("❌ No scenarios found!")
        return None
        
    print("\nSelect a Scenario to inject:")
    for idx, s in enumerate(scenarios, 1):
        print(f" [{idx}] {s}")
    print(f" [{len(scenarios)+1}] Custom file or folder path...")
    
    try:
        choice = input("\nEnter selection number: ").strip()
        if not choice:
            return None
        choice_idx = int(choice)
        if 1 <= choice_idx <= len(scenarios):
            return os.path.join(scenarios_dir, scenarios[choice_idx - 1])
        elif choice_idx == len(scenarios) + 1:
            return "custom"
    except ValueError:
        pass
    print("Invalid choice.")
    return None

def main():
    parser = argparse.ArgumentParser(description="Inject fake scenario telemetry (metrics, logs, traces) to Dumbproxy")
    parser.add_argument("--url", default=DEFAULT_SIMULATOR_URL, help=f"Dumbproxy endpoint URL (default: {DEFAULT_SIMULATOR_URL})")
    parser.add_argument("--scenario", help="Path or directory name of a scenario")
    parser.add_argument("--metrics", nargs="+", help="Specific metrics JSON file path(s)")
    parser.add_argument("--logs", nargs="+", help="Specific logs JSON file path(s)")
    parser.add_argument("--traces", nargs="+", help="Specific traces JSON file path(s)")
    parser.add_argument("--tenant", default="tenant-a", help="Default tenant ID if missing (default: tenant-a)")
    parser.add_argument("--env", default="prod", help="Default environment if missing (default: prod)")
    parser.add_argument("--dir", help="Force a specific fake-data directory location")
    args = parser.parse_args()

    fake_data_dir = args.dir or locate_fake_data_dir()
    if not fake_data_dir or not os.path.exists(fake_data_dir):
        print(f"❌ Could not automatically locate fake-data directory.")
        fake_data_dir = input("Please enter the absolute path to 'fake-data' directory: ").strip()
        if not fake_data_dir or not os.path.exists(fake_data_dir):
            print("❌ Invalid directory. Exiting.")
            sys.exit(1)
            
    print(f"📂 Using fake-data directory: {fake_data_dir}")
    
    scenario_path = args.scenario
    metrics_files = args.metrics or []
    logs_files = args.logs or []
    traces_files = args.traces or []
    
    # If no specific files are provided and no scenario path, go interactive
    if not scenario_path and not (metrics_files or logs_files or traces_files):
        selected = select_scenario(fake_data_dir)
        if not selected:
            sys.exit(0)
        if selected == "custom":
            custom_path = input("Enter path to a file or directory containing fake data: ").strip()
            if not os.path.exists(custom_path):
                print(f"❌ Path {custom_path} does not exist.")
                sys.exit(1)
            if os.path.isdir(custom_path):
                # Search for files recursively
                metrics_files = get_files_recursively(os.path.join(custom_path, "metrics"))
                logs_files = get_files_recursively(os.path.join(custom_path, "logs"))
                traces_files = get_files_recursively(os.path.join(custom_path, "traces"))
                if not (metrics_files or logs_files or traces_files):
                    # Try scanning the folder itself
                    all_json = get_files_recursively(custom_path)
                    for f in all_json:
                        if "metric" in f.lower():
                            metrics_files.append(f)
                        elif "log" in f.lower():
                            logs_files.append(f)
                        elif "trace" in f.lower():
                            traces_files.append(f)
                        else:
                            # Prompt user
                            fname = os.path.basename(f)
                            print(f"\nUnidentified file type for: {fname}")
                            t = input("Treat as [m]etric, [l]og, [t]race or [s]kip? ").strip().lower()
                            if t == 'm':
                                metrics_files.append(f)
                            elif t == 'l':
                                logs_files.append(f)
                            elif t == 't':
                                traces_files.append(f)
            else:
                fname = os.path.basename(custom_path)
                if "metric" in fname.lower():
                    metrics_files = [custom_path]
                elif "log" in fname.lower():
                    logs_files = [custom_path]
                elif "trace" in fname.lower():
                    traces_files = [custom_path]
                else:
                    t = input("Treat file as [m]etric, [l]og, [t]race? ").strip().lower()
                    if t == 'm':
                        metrics_files = [custom_path]
                    elif t == 'l':
                        logs_files = [custom_path]
                    elif t == 't':
                        traces_files = [custom_path]
                    else:
                        print("Skipping file.")
                        sys.exit(0)
        else:
            scenario_path = selected

    # If scenario path is set, find metrics, logs, traces in that scenario
    if scenario_path:
        # Check if it is a directory name or full path
        if not os.path.isabs(scenario_path):
            full_path = os.path.join(fake_data_dir, "scenarios", scenario_path)
            if os.path.exists(full_path):
                scenario_path = full_path
            else:
                full_path = os.path.join(fake_data_dir, scenario_path)
                if os.path.exists(full_path):
                    scenario_path = full_path
                    
        print(f"\n🎬 Processing scenario: {os.path.basename(scenario_path)}")
        metrics_files = get_files_recursively(os.path.join(scenario_path, "evidence", "metrics"))
        logs_files = get_files_recursively(os.path.join(scenario_path, "evidence", "logs"))
        traces_files = get_files_recursively(os.path.join(scenario_path, "evidence", "traces"))
        
        # Check if there are raw files at the root of evidence if subdirectories are empty
        if not (metrics_files or logs_files or traces_files):
            evidence_root = os.path.join(scenario_path, "evidence")
            if os.path.exists(evidence_root):
                for f in get_files_recursively(evidence_root):
                    if "metric" in f.lower():
                        metrics_files.append(f)
                    elif "log" in f.lower():
                        logs_files.append(f)
                    elif "trace" in f.lower():
                        traces_files.append(f)
        
        # Also print alerts info if found
        alerts_dir = os.path.join(scenario_path, "alerts")
        if os.path.exists(alerts_dir):
            alerts = get_files_recursively(alerts_dir)
            if alerts:
                print(f"📌 Found associated Alert definition(s):")
                for a in alerts:
                    print(f"  - {os.path.basename(a)}")

    print(f"\n📊 Summary of files to process:")
    print(f"  - Metrics files ({len(metrics_files)}): {[os.path.basename(f) for f in metrics_files]}")
    print(f"  - Logs files ({len(logs_files)}): {[os.path.basename(f) for f in logs_files]}")
    print(f"  - Traces files ({len(traces_files)}): {[os.path.basename(f) for f in traces_files]}")
    
    if not (metrics_files or logs_files or traces_files):
        print("❌ No telemetry files to process. Exiting.")
        sys.exit(0)
        
    # Build batch
    payload = process_and_build_batch(metrics_files, logs_files, traces_files, args.tenant, args.env)
    
    total_metrics = len(payload["metrics"])
    total_logs = len(payload["logs"])
    total_traces = len(payload["traces"])
    
    print(f"\n📦 Prepared Batch Payload:")
    print(f"  - Metrics to inject: {total_metrics}")
    print(f"  - Logs to inject: {total_logs}")
    print(f"  - Traces to inject: {total_traces}")
    
    if total_metrics == 0 and total_logs == 0 and total_traces == 0:
        print("❌ No items to inject.")
        sys.exit(0)
        
    # Ask confirmation
    confirm = input("\nDo you want to inject this telemetry batch? (y/n): ").strip().lower()
    if confirm != 'y':
        print("Cancelled.")
        sys.exit(0)
        
    # Send
    asyncio.run(send_payload(args.url, payload))

if __name__ == "__main__":
    main()
