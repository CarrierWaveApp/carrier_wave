#!/usr/bin/env python3
"""Import equipment catalog from TSV file into PostgreSQL.

Reads equipment-catalog.tsv and generates SQL for upserting into the
equipment_catalog table. Handles comma-separated arrays for bands, modes,
and aliases columns.

Usage:
    # Preview SQL:
    python3 scripts/import-equipment-tsv.py equipment-catalog.tsv

    # Import directly (staging):
    python3 scripts/import-equipment-tsv.py equipment-catalog.tsv | \
        psql -h 5.78.183.241 -U activities_staging -d activities_staging

    # Import directly (production):
    python3 scripts/import-equipment-tsv.py equipment-catalog.tsv | \
        psql -h 5.78.183.241 -U activities -d activities
"""

import csv
import sys


def escape_sql(value: str) -> str:
    """Escape single quotes for SQL string literals."""
    return value.replace("'", "''")


def to_pg_array(csv_value: str | None) -> str:
    """Convert comma-separated string to PostgreSQL array literal."""
    if not csv_value or not csv_value.strip():
        return "'{}'::TEXT[]"
    items = [escape_sql(item.strip()) for item in csv_value.split(",")]
    inner = ",".join(f'"{item}"' for item in items)
    return "'{" + inner + "}'::TEXT[]"


def to_sql_str(value: str | None) -> str:
    """Convert a TSV cell to a SQL string literal or NULL."""
    if not value or not value.strip():
        return "NULL"
    return f"'{escape_sql(value.strip())}'"


def to_sql_int(value: str | None) -> str:
    """Convert a TSV cell to a SQL integer or NULL."""
    if not value or not value.strip():
        return "NULL"
    return value.strip()


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <tsv-file>", file=sys.stderr)
        sys.exit(1)

    tsv_path = sys.argv[1]

    print("-- Equipment catalog import")
    print("-- Generated from:", tsv_path)
    print("BEGIN;")
    print()

    with open(tsv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        count = 0
        for row in reader:
            rid = escape_sql(row["id"].strip())
            name = to_sql_str(row["name"])
            manufacturer = to_sql_str(row["manufacturer"])
            category = to_sql_str(row["category"])
            bands = to_pg_array(row.get("bands", ""))
            modes = to_pg_array(row.get("modes", ""))
            max_power = to_sql_int(row.get("max_power_watts", ""))
            portability = to_sql_str(row.get("portability", "portable"))
            weight = to_sql_int(row.get("weight_grams", ""))
            description = to_sql_str(row.get("description", ""))
            aliases = to_pg_array(row.get("aliases", ""))
            antenna_conn = to_sql_str(row.get("antenna_connector", ""))
            power_conn = to_sql_str(row.get("power_connector", ""))
            key_jack = to_sql_str(row.get("key_jack", ""))
            mic_jack = to_sql_str(row.get("mic_jack", ""))

            print(f"INSERT INTO equipment_catalog (")
            print(f"    id, name, manufacturer, category, bands, modes,")
            print(f"    max_power_watts, portability, weight_grams, description,")
            print(f"    aliases, antenna_connector, power_connector, key_jack, mic_jack")
            print(f") VALUES (")
            print(f"    '{rid}', {name}, {manufacturer}, {category}, {bands}, {modes},")
            print(f"    {max_power}, {portability}, {weight}, {description},")
            print(f"    {aliases}, {antenna_conn}, {power_conn}, {key_jack}, {mic_jack}")
            print(f") ON CONFLICT (id) DO UPDATE SET")
            print(f"    name = EXCLUDED.name,")
            print(f"    manufacturer = EXCLUDED.manufacturer,")
            print(f"    category = EXCLUDED.category,")
            print(f"    bands = EXCLUDED.bands,")
            print(f"    modes = EXCLUDED.modes,")
            print(f"    max_power_watts = EXCLUDED.max_power_watts,")
            print(f"    portability = EXCLUDED.portability,")
            print(f"    weight_grams = EXCLUDED.weight_grams,")
            print(f"    description = EXCLUDED.description,")
            print(f"    aliases = EXCLUDED.aliases,")
            print(f"    antenna_connector = EXCLUDED.antenna_connector,")
            print(f"    power_connector = EXCLUDED.power_connector,")
            print(f"    key_jack = EXCLUDED.key_jack,")
            print(f"    mic_jack = EXCLUDED.mic_jack,")
            print(f"    updated_at = now();")
            print()
            count += 1

    print("COMMIT;")
    print()
    print(f"-- Imported {count} equipment entries", file=sys.stderr)


if __name__ == "__main__":
    main()
