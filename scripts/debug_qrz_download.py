#!/usr/bin/env python3
"""
QRZ Download Debug Script

Emulates Carrier Wave's QRZ download logic with detailed debugging output.
Use this to diagnose QRZ sync issues.

Usage:
    python debug_qrz_download.py <API_KEY>

    # Or with environment variable:
    QRZ_API_KEY=xxx python debug_qrz_download.py
"""

import sys
import os
import re
import html
import time
import urllib.request
import urllib.parse
from datetime import datetime
from dataclasses import dataclass
from typing import Optional


# Configuration
BASE_URL = "https://logbook.qrz.com/api"
USER_AGENT = "CarrierWave/1.0 (Debug Script)"
PAGE_SIZE = 2000  # Same as app


@dataclass
class QRZStatusResponse:
    callsign: str
    book_id: Optional[str]
    qso_count: int
    confirmed_count: int


@dataclass
class QRZFetchedQSO:
    callsign: str
    band: str
    mode: str
    timestamp: datetime
    log_id: Optional[int]  # APP_QRZLOG_LOGID for pagination
    raw_adif: str


def log(level: str, message: str):
    """Log with timestamp"""
    ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]
    print(f"[{ts}] [{level}] {message}")


def log_debug(message: str):
    log("DEBUG", message)


def log_info(message: str):
    log("INFO", message)


def log_error(message: str):
    log("ERROR", message)


def log_warn(message: str):
    log("WARN", message)


def form_encode(data: dict) -> str:
    """URL-encode form data"""
    return urllib.parse.urlencode(data)


def parse_response(response: str) -> dict:
    """
    Parse QRZ API response.
    Mirrors QRZClient.parseResponse() logic.
    ADIF field needs special handling as it contains & characters.
    """
    result = {}

    # Check if there's an ADIF field
    adif_marker = "ADIF="
    adif_pos = response.find(adif_marker)

    if adif_pos != -1:
        # Parse everything before ADIF normally
        before_adif = response[:adif_pos]
        for pair in before_adif.split("&"):
            if not pair:
                continue
            parts = pair.split("=", 1)
            if len(parts) >= 2:
                result[parts[0]] = parts[1]

        # The ADIF value is everything after "ADIF="
        result["ADIF"] = response[adif_pos + len(adif_marker):]
    else:
        # No ADIF field, parse normally
        for pair in response.split("&"):
            parts = pair.split("=", 1)
            if len(parts) >= 2:
                result[parts[0]] = parts[1]

    return result


def decode_adif(encoded: str) -> str:
    """Decode HTML entities in ADIF string"""
    return html.unescape(encoded)


def parse_adif_records(adif: str) -> list[QRZFetchedQSO]:
    """Parse ADIF string into QSO records"""
    qsos = []

    # Split by <eor> (end of record)
    records = re.split(r'<eor>', adif, flags=re.IGNORECASE)

    for record in records:
        if not record.strip():
            continue

        # Parse fields
        fields = {}
        pattern = r'<(\w+):(\d+)(?::[^>]*)?>([^<]*)'
        for match in re.finditer(pattern, record, re.IGNORECASE):
            field_name = match.group(1).upper()
            field_len = int(match.group(2))
            field_value = match.group(3)[:field_len]
            fields[field_name] = field_value

        # Extract key fields
        callsign = fields.get("CALL", "")
        band = fields.get("BAND", "")
        mode = fields.get("MODE", "")

        # Parse timestamp
        qso_date = fields.get("QSO_DATE", "")
        time_on = fields.get("TIME_ON", "")
        timestamp = None
        if qso_date:
            try:
                if time_on:
                    # Normalize time to 6 digits (HHMMSS)
                    time_on = time_on.ljust(6, '0')[:6]
                    timestamp = datetime.strptime(f"{qso_date}{time_on}", "%Y%m%d%H%M%S")
                else:
                    timestamp = datetime.strptime(qso_date, "%Y%m%d")
            except ValueError:
                pass

        # Extract log_id for pagination (APP_QRZLOG_LOGID)
        log_id_str = fields.get("APP_QRZLOG_LOGID", "")
        log_id = int(log_id_str) if log_id_str.isdigit() else None

        if callsign and band and mode:
            qsos.append(QRZFetchedQSO(
                callsign=callsign,
                band=band,
                mode=mode,
                timestamp=timestamp or datetime.now(),
                log_id=log_id,
                raw_adif=record.strip()
            ))

    return qsos


def make_request(url: str, data: dict) -> bytes:
    """Make POST request to QRZ API, return raw bytes"""
    encoded_data = form_encode(data).encode('utf-8')

    req = urllib.request.Request(url, data=encoded_data, method='POST')
    req.add_header('User-Agent', USER_AGENT)
    req.add_header('Content-Type', 'application/x-www-form-urlencoded')

    with urllib.request.urlopen(req, timeout=60) as response:
        return response.read()


def decode_response(data: bytes) -> str:
    """
    Decode response bytes to string.
    Mirrors QRZClient.decodeResponseData() - tries UTF-8 first, then Latin-1.
    """
    try:
        return data.decode('utf-8')
    except UnicodeDecodeError:
        log_debug("UTF-8 decode failed, falling back to Latin-1")
        return data.decode('latin-1')


def validate_api_key(api_key: str) -> QRZStatusResponse:
    """Validate API key and get account status"""
    log_info("Validating API key...")
    log_debug(f"POST {BASE_URL} ACTION=STATUS")

    data = {
        "KEY": api_key,
        "ACTION": "STATUS"
    }

    response_bytes = make_request(BASE_URL, data)
    log_debug(f"Response length: {len(response_bytes)} bytes")
    response = decode_response(response_bytes)
    log_debug(f"Response preview: {response[:200]}...")

    parsed = parse_response(response)
    log_debug(f"Parsed keys: {list(parsed.keys())}")

    result = parsed.get("RESULT", "")
    if result != "OK":
        if result == "AUTH":
            raise Exception("QRZ XML Logbook Data subscription required")
        reason = parsed.get("REASON", f"Unknown error, RESULT={result}")
        raise Exception(f"API validation failed: {reason}")

    callsign = parsed.get("CALLSIGN", "")
    if not callsign:
        raise Exception("No callsign in response")

    return QRZStatusResponse(
        callsign=callsign,
        book_id=parsed.get("BOOKID"),
        qso_count=int(parsed.get("COUNT", "0")),
        confirmed_count=int(parsed.get("CONFIRMED", "0"))
    )


def fetch_qsos(api_key: str, since: Optional[datetime] = None) -> list[QRZFetchedQSO]:
    """
    Fetch QSOs from QRZ logbook with pagination.

    FIXED: Uses AFTERLOGID for pagination instead of OFFSET.
    QRZ API requires AFTERLOGID:<highest_logid+1> for subsequent pages.
    """
    all_qsos = []
    after_log_id = 0  # Start from beginning
    page_num = 1

    while True:
        log_info(f"Fetching page {page_num} (afterLogId={after_log_id}, pageSize={PAGE_SIZE})...")

        # Build options - use AFTERLOGID for pagination (not OFFSET!)
        option_parts = [f"MAX:{PAGE_SIZE}", f"AFTERLOGID:{after_log_id}"]
        if since:
            option_parts.append(f"MODSINCE:{since.strftime('%Y-%m-%d')}")

        data = {
            "KEY": api_key,
            "ACTION": "FETCH",
            "OPTION": ",".join(option_parts)
        }

        log_debug(f"POST {BASE_URL} ACTION=FETCH OPTION={data['OPTION']}")

        start_time = time.time()
        response_bytes = make_request(BASE_URL, data)
        elapsed = time.time() - start_time

        log_debug(f"Response received in {elapsed:.2f}s, {len(response_bytes)} bytes")
        response = decode_response(response_bytes)

        parsed = parse_response(response)
        result = parsed.get("RESULT", "")
        reason = parsed.get("REASON", "").lower()
        response_count = int(parsed.get("COUNT", "0"))

        log_debug(f"RESULT={result}, COUNT={response_count}, REASON={parsed.get('REASON', 'N/A')}")

        # Show full response if it's short (likely an error)
        if len(response_bytes) < 500:
            log_debug(f"Full response: {response}")

        # Handle "no log entries found" case
        if "no log entries found" in reason:
            log_info("No (more) QSOs found (reason: no log entries)")
            break

        # FAIL with count=0 means no more records
        if result == "FAIL" and response_count == 0:
            log_info("No more QSOs (RESULT=FAIL, COUNT=0)")
            break

        if result != "OK":
            if result == "AUTH":
                raise Exception("Session expired")
            raise Exception(f"Fetch failed: {parsed.get('REASON', result)}")

        encoded_adif = parsed.get("ADIF", "")
        if not encoded_adif:
            log_warn("No ADIF field in response")
            break

        adif = decode_adif(encoded_adif)
        page_qsos = parse_adif_records(adif)

        log_info(f"Page {page_num}: parsed {len(page_qsos)} QSOs (API COUNT={response_count})")

        if len(page_qsos) != response_count:
            log_warn(f"Mismatch: parsed {len(page_qsos)} but API COUNT={response_count}")

        # Find the highest log_id in this batch for next pagination
        max_log_id = 0
        missing_log_ids = 0
        for qso in page_qsos:
            if qso.log_id:
                max_log_id = max(max_log_id, qso.log_id)
            else:
                missing_log_ids += 1

        if missing_log_ids > 0:
            log_warn(f"{missing_log_ids} QSOs missing APP_QRZLOG_LOGID field")

        log_debug(f"Max log_id in this batch: {max_log_id}")

        all_qsos.extend(page_qsos)

        # Check if we should continue pagination
        if len(page_qsos) < PAGE_SIZE:
            log_debug(f"Last page (got {len(page_qsos)} < {PAGE_SIZE})")
            break

        if max_log_id == 0:
            log_error("Cannot paginate: no log_id values found in QSOs")
            break

        # Next page starts after highest log_id
        after_log_id = max_log_id + 1
        page_num += 1

        # Rate limiting delay
        log_debug("Sleeping 200ms before next page...")
        time.sleep(0.2)

    return all_qsos


def analyze_qsos(qsos: list[QRZFetchedQSO]):
    """Analyze and print statistics about downloaded QSOs"""
    if not qsos:
        log_info("No QSOs to analyze")
        return

    log_info(f"\n{'='*60}")
    log_info(f"QSO ANALYSIS ({len(qsos)} total)")
    log_info(f"{'='*60}")

    # Date range
    dates = [q.timestamp for q in qsos if q.timestamp]
    if dates:
        earliest = min(dates)
        latest = max(dates)
        log_info(f"Date range: {earliest.strftime('%Y-%m-%d')} to {latest.strftime('%Y-%m-%d')}")

    # Band breakdown
    bands = {}
    for q in qsos:
        bands[q.band] = bands.get(q.band, 0) + 1
    log_info(f"\nBands:")
    for band, count in sorted(bands.items(), key=lambda x: -x[1]):
        log_info(f"  {band}: {count}")

    # Mode breakdown
    modes = {}
    for q in qsos:
        modes[q.mode] = modes.get(q.mode, 0) + 1
    log_info(f"\nModes:")
    for mode, count in sorted(modes.items(), key=lambda x: -x[1]):
        log_info(f"  {mode}: {count}")

    # Sample QSOs
    log_info(f"\nSample QSOs (first 5):")
    for q in qsos[:5]:
        log_info(f"  {q.timestamp.strftime('%Y-%m-%d %H:%M')} {q.callsign:10} {q.band:6} {q.mode}")


def main():
    print(f"""
{'='*60}
QRZ Download Debug Script
Emulates Carrier Wave's QRZ download logic
{'='*60}
""")

    # Get API key from argument or environment
    api_key = None
    if len(sys.argv) > 1:
        api_key = sys.argv[1]
    else:
        api_key = os.environ.get("QRZ_API_KEY")

    if not api_key:
        print("Usage: python debug_qrz_download.py <API_KEY>")
        print("   or: QRZ_API_KEY=xxx python debug_qrz_download.py")
        sys.exit(1)

    log_info(f"API key: {api_key[:4]}...{api_key[-4:]}")

    try:
        # Step 1: Validate API key
        status = validate_api_key(api_key)
        log_info(f"Authenticated as: {status.callsign}")
        log_info(f"Book ID: {status.book_id or 'N/A'}")
        log_info(f"QSO count (from STATUS): {status.qso_count}")
        log_info(f"Confirmed count: {status.confirmed_count}")

        # Step 2: Fetch all QSOs
        log_info(f"\n{'='*60}")
        log_info("Starting QSO download...")
        log_info(f"{'='*60}")

        start_time = time.time()
        qsos = fetch_qsos(api_key)
        elapsed = time.time() - start_time

        log_info(f"\nDownload complete!")
        log_info(f"Total QSOs fetched: {len(qsos)}")
        log_info(f"Total time: {elapsed:.1f}s")
        log_info(f"Expected from STATUS: {status.qso_count}")

        if len(qsos) != status.qso_count:
            log_warn(f"MISMATCH: Fetched {len(qsos)} but STATUS reported {status.qso_count}")
            log_warn("This may indicate pagination issues or API inconsistencies")

        # Step 3: Analyze
        analyze_qsos(qsos)

    except Exception as e:
        log_error(f"Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
