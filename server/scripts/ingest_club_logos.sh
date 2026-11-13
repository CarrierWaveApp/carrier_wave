#!/usr/bin/env bash
#
# Ingest club logos from known URLs into the database via the admin API.
#
# Usage:
#   ADMIN_TOKEN=xxx ./scripts/ingest_club_logos.sh [BASE_URL]
#
# BASE_URL defaults to https://activities.carrierwave.app

set -euo pipefail

BASE_URL="${1:-https://activities.carrierwave.app}"

if [ -z "${ADMIN_TOKEN:-}" ]; then
    echo "Error: ADMIN_TOKEN environment variable is required"
    exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Club name -> logo URL mapping
# Format: "CLUB_NAME|LOGO_URL"
LOGOS=(
    "CWops|https://cwops.org/wp-content/uploads/2018/04/cropped-CWOps_logo_250x250px.png"
    "FISTS|https://fists.co.uk/style/knfists_50.png"
    "QRP Amateur Radio Club International|https://www.qrparci.org/images/qrparci_color_logo.png"
    "First Class Operators' Club|https://www.g4foc.org/wp-content/uploads/2024/01/foclogotrans.png"
    "First Class Operators' Club Nominees|https://www.g4foc.org/wp-content/uploads/2024/01/foclogotrans.png"
    "Arbeitsgemeinschaft CW|https://www.agcw.de/wp-content/uploads/2020/07/agcwsvg.svg"
    "North American QRP CW Club|https://naqcc.info/pix/pix_naqcc_logo_mini.jpg"
    "High Speed Club|https://www.morsecode.nl/images/hsclogo.gif"
    "Very High Speed Club|https://www.morsecode.nl/vhsclogo.png"
    "A1 Club|https://a1club.org/a1logo.gif"
    "Extremely High Speed Club|https://www.eucw.org/ehsc.gif"
    "Super High Speed Club|https://www.eucw.org/shsc.gif"
    "Second Class Operators' Club|https://www.qsl.net/soc/pics/logo.jpg"
    "EA CW Club|https://www.eucw.org/eacw.gif"
    "Essex CW ARC|https://essexcw.uk/wp-content/uploads/2021/10/cropped-62338981_2095251580774924_4012876640022429696_n-2.jpg"
    "Union Française des Télégraphistes|https://www.uft.net/wp-content/uploads/2026/01/Accueil.jpg"
    "Club Francophone des Télégraphistes|https://www.on5cft.com/wp-content/uploads/2025/02/13.jpg"
    "Die Österreichische CW Group|https://oecwg.at/OECWG_Bilder/oecwg.gif"
    "Helvetia Telegraphy Club|https://www.hb9htc.ch/fileservlet?type=image&id=1005134&s=djEtV99gyB2V147AG2gPQN1gKerWBTKp_HK8DnIkzlGBd2w=&imageFormat=_2048x2048"
    "Netherlands Telegraphy Club|https://pi4ntc.nl/wp-content/uploads/2022/05/NTC-logo.png"
    "Polski Klub Radiotelegrafistów|https://spcwc.pzk.pl/wp-content/uploads/logospcwc.jpg"
    "Russian CW Club|https://rcwc.ru/templates/work/images/shapka-nadpis.png"
    "Marconi Club dell'A.R.I. di Loano|https://www.marconiclub.it/images/logo/logomarconiclubariloanoridotta.png"
    "Marinefunker|https://mf-runde.de/wp-content/uploads/2018/11/header_2018.gif"
    "Novice Rig Round-Up|https://www.novicerigroundup.org/imag/NRR.jpg"
    "Four State QRP Group|https://www.4sqrp.com/incld/4State_logo_BLUE_300dpi.gif"
    "Grupo Juizforano de CW|https://site.cwjf.com.br/assets/cwjf/img/logo-cwjf-bandeiras.png"
    "Grupo Português de CW|https://gpcw.pt/wp/wp-content/uploads/2021/03/cropped-1200x400-1.png"
    "International CW Club U-QRQ|https://u-qrq-c.ru/wp-content/uploads/2023/02/cropped-qrq.jpg"
    "Tortugas CW Club|https://tortugascw.com/wp-content/uploads/2022/02/Logo_new_350-1.jpg"
    "QRQ Crew Club|https://www.qrqcrew.club/logo.png"
)

# First, fetch the list of clubs to get name->ID mapping
echo "Fetching club list..."
CLUBS_JSON=$(curl -sf "$BASE_URL/v1/admin/clubs" \
    -H "Authorization: Bearer $ADMIN_TOKEN")

success=0
failed=0
skipped=0

for entry in "${LOGOS[@]}"; do
    CLUB_NAME="${entry%%|*}"
    LOGO_URL="${entry#*|}"

    # Find the club ID by name
    CLUB_ID=$(echo "$CLUBS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
clubs = data.get('data', [])
for c in clubs:
    if c['name'] == '''$CLUB_NAME''':
        print(c['id'])
        break
" 2>/dev/null || true)

    if [ -z "$CLUB_ID" ]; then
        echo "SKIP: '$CLUB_NAME' - club not found in database"
        ((skipped++)) || true
        continue
    fi

    # Download the logo
    LOGO_FILE="$TMPDIR/logo_$(echo "$CLUB_ID" | tr -d '-')"
    echo -n "  $CLUB_NAME ($CLUB_ID)... "

    HTTP_CODE=$(curl -sf -o "$LOGO_FILE" -w "%{http_code}" \
        -L --max-time 15 "$LOGO_URL" 2>/dev/null || echo "000")

    if [ "$HTTP_CODE" != "200" ] || [ ! -s "$LOGO_FILE" ]; then
        echo "FAIL (download: HTTP $HTTP_CODE)"
        ((failed++)) || true
        continue
    fi

    # Detect content type from the file
    CONTENT_TYPE=$(file --mime-type -b "$LOGO_FILE")

    # Map common types
    case "$CONTENT_TYPE" in
        image/png|image/jpeg|image/gif|image/webp|image/svg+xml)
            ;;
        application/xml|text/xml)
            CONTENT_TYPE="image/svg+xml"
            ;;
        *)
            # Try to infer from URL extension
            case "$LOGO_URL" in
                *.png) CONTENT_TYPE="image/png" ;;
                *.jpg|*.jpeg) CONTENT_TYPE="image/jpeg" ;;
                *.gif) CONTENT_TYPE="image/gif" ;;
                *.svg) CONTENT_TYPE="image/svg+xml" ;;
                *.webp) CONTENT_TYPE="image/webp" ;;
                *) echo "FAIL (unknown type: $CONTENT_TYPE)"; ((failed++)) || true; continue ;;
            esac
            ;;
    esac

    # Upload via admin API
    UPLOAD_CODE=$(curl -sf -o /dev/null -w "%{http_code}" \
        -X PUT "$BASE_URL/v1/admin/clubs/$CLUB_ID/logo" \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -F "image=@$LOGO_FILE;type=$CONTENT_TYPE" 2>/dev/null || echo "000")

    if [ "$UPLOAD_CODE" = "204" ]; then
        echo "OK ($CONTENT_TYPE)"
        ((success++)) || true
    else
        echo "FAIL (upload: HTTP $UPLOAD_CODE)"
        ((failed++)) || true
    fi
done

echo ""
echo "Done: $success uploaded, $failed failed, $skipped skipped"
