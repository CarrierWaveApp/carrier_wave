#!/bin/bash
# Static import checker for Swift files.
# Catches missing imports by mapping known types/functions to their modules.
# Not a compiler — but catches the most common class of cloud-edit errors.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only process Swift files
[[ "$FILE_PATH" =~ \.swift$ ]] || exit 0
[ -f "$FILE_PATH" ] || exit 0

# Read file content
CONTENT=$(cat "$FILE_PATH")

# Extract existing imports (handles both `import Foo` and `@_exported import Foo`)
IMPORTS=$(echo "$CONTENT" | grep -oP '^\s*(@_exported\s+)?import\s+\K\w+' | sort -u)

has_import() {
    echo "$IMPORTS" | grep -qx "$1"
}

ERRORS=""

# --- Foundation types ---
FOUNDATION_TYPES='FileManager|ISO8601DateFormatter|DateFormatter|DateComponents|Calendar|TimeZone|JSONEncoder|JSONDecoder|PropertyListEncoder|PropertyListDecoder|URLSession|URLRequest|URLComponents|URLQueryItem|HTTPURLResponse|Notification\.Name|NotificationCenter|UserDefaults|ProcessInfo|Bundle|Locale|NSLock|NSRecursiveLock|DispatchSemaphore|NumberFormatter|MeasurementFormatter|ByteCountFormatter|RelativeDateTimeFormatter|PersonNameComponentsFormatter|ListFormatter|UUID|NSRegularExpression|NSPredicate|NSSortDescriptor|NSError|NSCoder|NSKeyedArchiver|NSKeyedUnarchiver|Timer|RunLoop|OperationQueue|BlockOperation|Data\(|NSAttributedString|NSMutableAttributedString|CharacterSet|NSRange|NSString|NSURL|NSCache|NSOrderedSet'

# Check for Foundation types but NOT if SwiftUI/UIKit is imported (they re-export Foundation)
if ! has_import "Foundation" && ! has_import "SwiftUI" && ! has_import "UIKit"; then
    # Also check for standalone uses of URL and Date that aren't just substrings
    FOUND_FOUNDATION=$(echo "$CONTENT" | grep -v '^\s*//' | grep -v '^\s*import ' | \
        grep -oP "(?<![.\w])($FOUNDATION_TYPES)(?!\w)" | head -5)

    # Check URL as a type (not inside a word)
    FOUND_URL=$(echo "$CONTENT" | grep -v '^\s*//' | grep -v '^\s*import ' | \
        grep -oP '\bURL\s*[(:?]|:\s*URL\b|-> URL\b|\[URL\]' | head -1)

    # Check Date as a type
    FOUND_DATE=$(echo "$CONTENT" | grep -v '^\s*//' | grep -v '^\s*import ' | \
        grep -oP '\bDate\s*[(:?]|:\s*Date\b|-> Date\b|\[Date\]|Date\(\)' | head -1)

    if [ -n "$FOUND_FOUNDATION" ] || [ -n "$FOUND_URL" ] || [ -n "$FOUND_DATE" ]; then
        MATCHED=$(echo "$FOUND_FOUNDATION $FOUND_URL $FOUND_DATE" | xargs)
        if [[ "$FILE_PATH" == */CarrierWave/*.swift ]] && [[ "$FILE_PATH" != */CarrierWaveCore/* ]] && [[ "$FILE_PATH" != */CarrierWaveData/* ]]; then
            ERRORS="${ERRORS}Missing 'import UIKit' (not Foundation — UIKit re-exports Foundation and is required for archive builds) — uses: ${MATCHED}\n"
        else
            ERRORS="${ERRORS}Missing 'import Foundation' — uses: ${MATCHED}\n"
        fi
    fi
fi

# Check .localizedDescription (requires Foundation)
if ! has_import "Foundation" && ! has_import "SwiftUI" && ! has_import "UIKit"; then
    if echo "$CONTENT" | grep -v '^\s*//' | grep -qP '\.localizedDescription'; then
        ERRORS="${ERRORS}Missing 'import Foundation' — uses .localizedDescription\n"
    fi
fi

# Check SortDescriptor (requires Foundation)
if ! has_import "Foundation" && ! has_import "SwiftUI" && ! has_import "UIKit"; then
    if echo "$CONTENT" | grep -v '^\s*//' | grep -qP '\bSortDescriptor\b'; then
        ERRORS="${ERRORS}Missing 'import Foundation' — uses SortDescriptor\n"
    fi
fi

# Check .userDomainMask / .libraryDirectory (Foundation search path constants)
if ! has_import "Foundation" && ! has_import "SwiftUI" && ! has_import "UIKit"; then
    if echo "$CONTENT" | grep -v '^\s*//' | grep -qP '\.(userDomainMask|libraryDirectory|documentDirectory|cachesDirectory|applicationSupportDirectory)\b'; then
        ERRORS="${ERRORS}Missing 'import Foundation' — uses FileManager search path constants\n"
    fi
fi

# --- SwiftData types ---
SWIFTDATA_TYPES='ModelContainer|ModelContext|ModelConfiguration|FetchDescriptor|@Model|@Attribute|@Relationship|@Query|Schema\b'

if ! has_import "SwiftData"; then
    FOUND_SD=$(echo "$CONTENT" | grep -v '^\s*//' | grep -v '^\s*import ' | \
        grep -oP "(?<![.\w])($SWIFTDATA_TYPES)" | head -3)
    if [ -n "$FOUND_SD" ]; then
        ERRORS="${ERRORS}Missing 'import SwiftData' — uses: $(echo "$FOUND_SD" | xargs)\n"
    fi
fi

# --- SwiftUI types ---
SWIFTUI_TYPES='@State\b|@Binding\b|@Environment\b|@EnvironmentObject\b|@ObservedObject\b|@StateObject\b|@Published\b|@ViewBuilder\b|@AppStorage\b|@SceneStorage\b|@FocusState\b|NavigationStack|NavigationLink|NavigationSplitView|TabView|ScrollView|LazyVStack|LazyHStack|LazyVGrid|LazyHGrid|GeometryReader|VStack|HStack|ZStack|Spacer\(\)|Divider\(\)|Toggle\b.*isOn|Slider\b|Picker\b|ProgressView|TextField|TextEditor|SecureField|DatePicker|ColorPicker|ToolbarItem|ToolbarItemGroup'

if ! has_import "SwiftUI"; then
    # Only flag if the file looks like it has UI code (views conforming to View)
    if echo "$CONTENT" | grep -qP ':\s*(some\s+)?View\b|@ViewBuilder'; then
        FOUND_SUI=$(echo "$CONTENT" | grep -v '^\s*//' | grep -v '^\s*import ' | \
            grep -oP "($SWIFTUI_TYPES)" | head -3)
        if [ -n "$FOUND_SUI" ]; then
            ERRORS="${ERRORS}Missing 'import SwiftUI' — uses: $(echo "$FOUND_SUI" | xargs)\n"
        fi
    fi
fi

# --- UIKit types ---
UIKIT_TYPES='UIImage\b|UIColor\b|UIFont\b|UIApplication\b|UIDevice\b|UIViewController\b|UIView\b|UIScreen\b|UIPasteboard\b|UIActivityViewController|UIDocumentPickerViewController|UIImagePickerController|UINavigationController'

if ! has_import "UIKit" && ! has_import "SwiftUI"; then
    FOUND_UIK=$(echo "$CONTENT" | grep -v '^\s*//' | grep -v '^\s*import ' | \
        grep -oP "(?<![.\w])($UIKIT_TYPES)" | head -3)
    if [ -n "$FOUND_UIK" ]; then
        ERRORS="${ERRORS}Missing 'import UIKit' — uses: $(echo "$FOUND_UIK" | xargs)\n"
    fi
fi

# --- OSLog ---
# Flag `import os` / `import os.log` / `import os.signpost` — the Darwin
# `os` module (and its submodules) shadow Foundation across the entire target,
# making Foundation types invisible even when Foundation is explicitly imported.
if has_import "os"; then
    ERRORS="${ERRORS}Replace 'import os' (or os.log/os.signpost) with 'import OSLog' — the os module shadows Foundation and breaks type resolution\n"
fi

if ! has_import "OSLog" && ! has_import "os"; then
    if echo "$CONTENT" | grep -v '^\s*//' | grep -v '^\s*import ' | grep -qP '\bLogger\s*\('; then
        ERRORS="${ERRORS}Missing 'import OSLog' — uses Logger\n"
    fi
fi

# --- CoreLocation ---
if ! has_import "CoreLocation"; then
    CORELOCATION_TYPES='CLLocationCoordinate2D|CLLocation\b|CLGeocoder|CLLocationManager|CLAuthorizationStatus'
    FOUND_CL=$(echo "$CONTENT" | grep -v '^\s*//' | grep -v '^\s*import ' | \
        grep -oP "(?<![.\w])($CORELOCATION_TYPES)" | head -3)
    if [ -n "$FOUND_CL" ]; then
        ERRORS="${ERRORS}Missing 'import CoreLocation' — uses: $(echo "$FOUND_CL" | xargs)\n"
    fi
fi

# --- MapKit ---
if ! has_import "MapKit"; then
    if echo "$CONTENT" | grep -v '^\s*//' | grep -v '^\s*import ' | grep -qP '\bMap\s*\{|MKCoordinateRegion|MKMapView|MapAnnotation|Annotation\s*\('; then
        ERRORS="${ERRORS}Missing 'import MapKit' — uses Map/MapKit types\n"
    fi
fi

# --- Combine ---
if ! has_import "Combine" && ! has_import "SwiftUI"; then
    COMBINE_TYPES='AnyCancellable|PassthroughSubject|CurrentValueSubject|AnyPublisher|Just\(|Future\('
    FOUND_CB=$(echo "$CONTENT" | grep -v '^\s*//' | grep -v '^\s*import ' | \
        grep -oP "(?<![.\w])($COMBINE_TYPES)" | head -3)
    if [ -n "$FOUND_CB" ]; then
        ERRORS="${ERRORS}Missing 'import Combine' — uses: $(echo "$FOUND_CB" | xargs)\n"
    fi
fi

# --- Report ---
if [ -n "$ERRORS" ]; then
    echo "Import check failed for $FILE_PATH:" >&2
    echo -e "$ERRORS" >&2
    echo "" >&2
    echo "Add the missing import(s) at the top of the file." >&2
    exit 2
fi

exit 0
