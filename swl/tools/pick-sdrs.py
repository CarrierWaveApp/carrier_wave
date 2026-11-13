#!/usr/bin/env python3
"""Pick the best available KiwiSDRs given a location hint and target frequency.

Usage:
    sdr-cli sdrs list | python3 pick-sdrs.py --location EM55 --count 3
    sdr-cli sdrs list | python3 pick-sdrs.py --location 35.4,-89.6 --count 3

Location formats:
    Maidenhead grid square: EM55, FN42ig, etc.
    Lat,lon: 35.4,-89.6

Output: one SDR ID per line (suitable for xargs / bash read loop).
"""

import argparse
import concurrent.futures
import json
import math
import re
import sys
import urllib.request


def grid_to_latlon(grid: str) -> tuple[float, float]:
    """Convert Maidenhead grid square to (lat, lon) center."""
    grid = grid.strip().upper()
    if len(grid) < 2:
        raise ValueError(f"Invalid grid: {grid}")

    lon = (ord(grid[0]) - ord("A")) * 20 - 180
    lat = (ord(grid[1]) - ord("A")) * 10 - 90

    if len(grid) >= 4:
        lon += int(grid[2]) * 2
        lat += int(grid[3]) * 1

    if len(grid) >= 6:
        lon += (ord(grid[4]) - ord("A")) * (2 / 24)
        lat += (ord(grid[5]) - ord("A")) * (1 / 24)
        # Center of subsquare
        lon += 1 / 24
        lat += 0.5 / 24
    elif len(grid) >= 4:
        # Center of square
        lon += 1
        lat += 0.5
    else:
        # Center of field
        lon += 10
        lat += 5

    return (lat, lon)


def parse_location(loc: str) -> tuple[float, float]:
    """Parse location as lat,lon or Maidenhead grid."""
    # Try lat,lon
    m = re.match(r"^(-?\d+\.?\d*)\s*,\s*(-?\d+\.?\d*)$", loc.strip())
    if m:
        return (float(m.group(1)), float(m.group(2)))
    # Try grid square
    if re.match(r"^[A-Ra-r]{2}\d{2}([A-Xa-x]{2})?$", loc.strip()):
        return grid_to_latlon(loc)
    raise ValueError(
        f"Cannot parse location: {loc!r}. Use grid square (EM55) or lat,lon (35.4,-89.6)"
    )


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance in km."""
    R = 6371
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(dlon / 2) ** 2
    )
    return R * 2 * math.asin(math.sqrt(a))


def status_from_kiwi_status(sdr: dict) -> dict | None:
    """Extract candidate info from inline kiwi_status (no network call)."""
    ks = sdr.get("kiwi_status")
    if not ks:
        return None

    lat = ks.get("lat")
    lon = ks.get("lon")
    if lat is None or lon is None:
        return None

    if ks.get("offline"):
        return None

    users = ks.get("users", 0) or 0
    users_max = ks.get("users_max", 0) or 0
    if users_max > 0 and users >= users_max:
        return None  # full

    return {
        "users": users,
        "users_max": users_max,
        "free": max(0, users_max - users),
        "lat": lat,
        "lon": lon,
        "name": sdr.get("label", ""),
        "antenna": ks.get("antenna", ""),
        "snr": ks.get("snr", ""),
    }


def fetch_status(host: str, timeout: float = 3.0) -> dict | None:
    """Fetch KiwiSDR /status and parse key fields (fallback for SDRs without kiwi_status)."""
    url = f"http://{host}:8073/status"
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            text = resp.read().decode(errors="replace")
    except Exception:
        return None

    fields = {}
    for line in text.splitlines():
        if "=" in line:
            k, _, v = line.partition("=")
            fields[k] = v

    try:
        users = int(fields.get("users", "0"))
        users_max = int(fields.get("users_max", "0"))
    except ValueError:
        return None

    if users >= users_max:
        return None  # full

    gps_match = re.match(
        r"\((-?\d+\.?\d*),\s*(-?\d+\.?\d*)\)", fields.get("gps", "")
    )
    if not gps_match:
        return None  # no location

    return {
        "users": users,
        "users_max": users_max,
        "free": users_max - users,
        "lat": float(gps_match.group(1)),
        "lon": float(gps_match.group(2)),
        "name": fields.get("name", ""),
        "antenna": fields.get("antenna", ""),
        "snr": fields.get("snr", ""),
    }


def select_sdrs(
    candidates: list[dict],
    target_lat: float,
    target_lon: float,
    count: int,
    max_distance_km: float | None,
) -> list[dict]:
    """Select SDRs balancing proximity and geographic diversity.

    Strategy: greedy selection. First pick is closest to target location.
    Each subsequent pick maximizes: closeness_to_target + diversity_from_already_selected.
    """
    if not candidates:
        return []

    # Pre-compute distances to target
    for c in candidates:
        c["dist_km"] = haversine_km(target_lat, target_lon, c["lat"], c["lon"])

    # Filter by max distance if specified
    if max_distance_km is not None:
        candidates = [c for c in candidates if c["dist_km"] <= max_distance_km]

    if not candidates:
        return []

    # Sort by distance for first pick
    candidates.sort(key=lambda c: c["dist_km"])

    selected = [candidates.pop(0)]

    while len(selected) < count and candidates:
        # Score each remaining candidate
        best_idx = 0
        best_score = -1
        max_dist = max(c["dist_km"] for c in candidates) or 1

        for i, c in enumerate(candidates):
            # Proximity score: closer to target is better (0-1)
            proximity = 1.0 - (c["dist_km"] / (max_dist + 1))

            # Diversity score: farther from already-selected is better (0-1)
            min_sep = min(
                haversine_km(c["lat"], c["lon"], s["lat"], s["lon"]) for s in selected
            )
            # Normalize: 500km separation is "good enough"
            diversity = min(1.0, min_sep / 500)

            # Free slots bonus (prefer less loaded SDRs)
            load_score = min(1.0, c["free"] / 4)

            score = 0.4 * proximity + 0.4 * diversity + 0.2 * load_score
            if score > best_score:
                best_score = score
                best_idx = i

        selected.append(candidates.pop(best_idx))

    return selected


def main():
    parser = argparse.ArgumentParser(description="Pick best available KiwiSDRs")
    parser.add_argument(
        "--location", required=True, help="Grid square (EM55) or lat,lon (35.4,-89.6)"
    )
    parser.add_argument("--count", type=int, default=3, help="Number of SDRs to pick")
    parser.add_argument(
        "--max-distance",
        type=float,
        default=None,
        help="Max distance from location in km",
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true", help="Print selection details to stderr"
    )
    args = parser.parse_args()

    target_lat, target_lon = parse_location(args.location)

    if args.verbose:
        print(
            f"Target: {target_lat:.2f}, {target_lon:.2f}",
            file=sys.stderr,
        )

    # Read SDR list from stdin
    data = json.load(sys.stdin)
    sdrs = data.get("sdrs", data) if isinstance(data, dict) else data

    # Filter to KiwiSDRs only
    kiwis = [s for s in sdrs if s.get("driver") == "kiwisdr"]

    if args.verbose:
        print(f"Checking {len(kiwis)} KiwiSDRs for availability...", file=sys.stderr)

    # Use inline kiwi_status when available (instant), fall back to network probe
    candidates = []
    need_probe = []
    for sdr in kiwis:
        sid = sdr["id"]
        status = status_from_kiwi_status(sdr)
        if status is not None:
            status["id"] = sid
            candidates.append(status)
        else:
            need_probe.append(sdr)

    if args.verbose and need_probe:
        print(
            f"  {len(candidates)} from index, probing {len(need_probe)} without status...",
            file=sys.stderr,
        )

    # Concurrent fallback probes for SDRs without kiwi_status
    if need_probe:
        with concurrent.futures.ThreadPoolExecutor(max_workers=20) as pool:
            futures = {
                pool.submit(fetch_status, sdr["id"]): sdr["id"] for sdr in need_probe
            }
            for future in concurrent.futures.as_completed(futures):
                sid = futures[future]
                status = future.result()
                if status is not None:
                    status["id"] = sid
                    candidates.append(status)

    if args.verbose:
        print(f"Found {len(candidates)} available SDRs", file=sys.stderr)

    selected = select_sdrs(candidates, target_lat, target_lon, args.count, args.max_distance)

    for s in selected:
        if args.verbose:
            print(
                f"  {s['id']:40s} {s['dist_km']:6.0f}km  "
                f"{s['users']}/{s['users_max']} users  {s['name']}",
                file=sys.stderr,
            )
        print(s["id"])


if __name__ == "__main__":
    main()
