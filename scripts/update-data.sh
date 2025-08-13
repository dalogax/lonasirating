#!/bin/bash

# Lonas iRacing Data Fetcher
# Fetches iRacing statistics for team members and saves to JSON files

# Note: Not using set -e to allow graceful error handling

# Team members array (name:id format)
declare -A TEAM_MEMBERS=(
    ["Luis"]="918399"
    ["Samu"]="1096007"
    ["Porta"]="900904"
    ["Marcos"]="1094362"
    ["Rubén"]="1301050"
    ["Dalogax"]="305408"
)

# Categories to fetch
CATEGORIES=("sports_car" "formula_car")

# API base URL
API_BASE="https://iracing6-backend.herokuapp.com/api/member-career-stats/career"

# Data directory
DATA_DIR="data"

# Ensure data directory exists
mkdir -p "$DATA_DIR"

# Current timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "Starting data fetch at $TIMESTAMP"

# Function to fetch member data
fetch_member_data() {
    local member_name="$1"
    local member_id="$2"
    local temp_file="/tmp/member_${member_id}.json"
    
    echo "🔄 Fetching data for $member_name (ID: $member_id)..." >&2
    echo "   🌐 URL: $API_BASE/$member_id" >&2
    
    # Test connectivity first
    echo "   🔍 Testing connectivity to: $API_BASE/$member_id" >&2
    if ! curl -s --max-time 5 --head "$API_BASE/$member_id" > /dev/null 2>&1; then
        echo "❌ Connectivity test failed for $member_name" >&2
        return 1
    fi
    echo "   ✅ Connectivity test passed" >&2
    
    # Fetch data with curl, capture HTTP status and handle errors gracefully
    local http_status
    echo "   ⏳ Making API request to: $API_BASE/$member_id" >&2
    http_status=$(curl -s -w "%{http_code}" --max-time 30 --connect-timeout 10 "$API_BASE/$member_id" -o "$temp_file" 2>/dev/null)
    local curl_exit_code=$?
    
    echo "   📊 Curl exit code: $curl_exit_code, HTTP status: $http_status" >&2
    
    if [[ $curl_exit_code -eq 0 && "$http_status" == "200" ]]; then
        local file_size=$(stat -c%s "$temp_file" 2>/dev/null || echo "unknown")
        echo "✅ Successfully fetched data for $member_name (HTTP $http_status, ${file_size} bytes)" >&2
        echo "$temp_file"  # This is the only output to stdout
    else
        if [[ $curl_exit_code -ne 0 ]]; then
            case $curl_exit_code in
                6) echo "❌ Could not resolve host for $member_name" >&2 ;;
                7) echo "❌ Failed to connect to host for $member_name" >&2 ;;
                28) echo "❌ Timeout reached for $member_name" >&2 ;;
                *) echo "❌ Network error fetching data for $member_name (curl exit code: $curl_exit_code)" >&2 ;;
            esac
        else
            echo "❌ API error for $member_name (HTTP $http_status)" >&2
        fi
        [[ -f "$temp_file" ]] && rm -f "$temp_file"
        return 1
    fi
}

# Function to extract category data from member JSON
extract_category_data() {
    local member_file="$1"
    local member_name="$2"
    local member_id="$3"
    local category="$4"
    
    # Check if file exists and category exists in the data
    if [[ -f "$member_file" ]] && jq -e ".${category}" "$member_file" > /dev/null 2>&1; then
        # Extract the category data and add member info
        jq --arg name "$member_name" --arg id "$member_id" \
           --arg category "$category" \
           '{
               name: $name,
               id: ($id | tonumber),
               category: $category,
               currentRating: (.[$category].iRating.value // 0),
               chartData: (.[$category].iRating_chart.data // []),
               stats: .[$category],
               memberSince: .member_since,
               lastLogin: .last_login,
               lastUpdate: (.last_update // "")
           }' "$member_file" 2>/dev/null
    else
        echo "null"
    fi
}

# Fetch data for all team members
echo "📡 Starting API data fetch for ${#TEAM_MEMBERS[@]} team members..."
echo "📍 API endpoint: $API_BASE"
echo "🔍 Testing API connectivity..."

# Test API endpoint connectivity first
if curl -s --max-time 10 --head "$API_BASE/305408" > /dev/null 2>&1; then
    echo "✅ API endpoint is reachable"
else
    echo "❌ API endpoint appears to be unreachable. Continuing anyway..." >&2
fi

# Load existing data if available
existing_data_file="$DATA_DIR/team-data.json"
existing_data="{}"
if [[ -f "$existing_data_file" ]]; then
    echo "📄 Loading existing data from $existing_data_file"
    existing_data=$(cat "$existing_data_file")
    echo "   ✓ Existing data loaded"
else
    echo "📄 No existing data file found, starting fresh"
fi

temp_files=()
successful_fetches=0
failed_fetches=0

for member_name in "${!TEAM_MEMBERS[@]}"; do
    member_id="${TEAM_MEMBERS[$member_name]}"
    echo ""
    echo "👤 Processing member $((successful_fetches + failed_fetches + 1))/${#TEAM_MEMBERS[@]}: $member_name"
    
    temp_file=$(fetch_member_data "$member_name" "$member_id")
    fetch_exit_code=$?
    
    if [[ $fetch_exit_code -eq 0 && -n "$temp_file" && -f "$temp_file" ]]; then
        temp_files+=("$temp_file")
        ((successful_fetches++))
        echo "   ✓ Added to processing queue"
    else
        ((failed_fetches++))
        echo "   ✗ Failed to fetch, skipping"
    fi
    
    # Small delay to be respectful to the API
    echo "   ⏱️  Waiting 2 seconds before next request..."
    sleep 2
done

echo ""
echo "📊 API Fetch Summary:"
echo "   ✅ Successful: $successful_fetches/${#TEAM_MEMBERS[@]}"
echo "   ❌ Failed: $failed_fetches/${#TEAM_MEMBERS[@]}"

if [[ ${#temp_files[@]} -eq 0 ]]; then
    echo "💥 No data fetched successfully. Exiting." >&2
    exit 1
fi

# Build team members JSON more efficiently
echo ""
echo "🏗️  Building data structure..."
team_members_json="["
first=true
for member_name in "${!TEAM_MEMBERS[@]}"; do
    member_id="${TEAM_MEMBERS[$member_name]}"
    if [ "$first" = true ]; then
        team_members_json+="{\"name\":\"$member_name\",\"id\":$member_id}"
        first=false
    else
        team_members_json+=",{\"name\":\"$member_name\",\"id\":$member_id}"
    fi
done
team_members_json+="]"

combined_data=$(jq -n \
    --arg timestamp "$TIMESTAMP" \
    --argjson categories '["sports_car", "formula_car"]' \
    --argjson teamMembers "$team_members_json" \
    '{
        lastUpdate: $timestamp,
        categories: $categories,
        teamMembers: $teamMembers,
        totalMembers: ($teamMembers | length),
        data: {}
    }')

# Initialize category data arrays with existing data
declare -A category_data_arrays
declare -A category_member_counts
for category in "${CATEGORIES[@]}"; do
    # Start with existing data for this category if available
    if echo "$existing_data" | jq -e ".data.${category}.teamMembers" > /dev/null 2>&1; then
        existing_category_data=$(echo "$existing_data" | jq ".data.${category}.teamMembers")
        category_data_arrays[$category]="$existing_category_data"
        category_member_counts[$category]=$(echo "$existing_category_data" | jq 'length')
        echo "   📋 Loaded ${category_member_counts[$category]} existing members for $category"
    else
        category_data_arrays[$category]="[]"
        category_member_counts[$category]=0
        echo "   📋 No existing data for $category, starting empty"
    fi
done

# Process each member's data once for all categories
echo "🔧 Processing member data for all categories..."
processed_members=0
updated_members=0

# Create a list of member IDs that were successfully fetched
declare -A fetched_member_ids
for temp_file in "${temp_files[@]}"; do
    if [[ -f "$temp_file" ]]; then
        member_id=$(basename "$temp_file" | sed 's/member_\([0-9]*\)\.json/\1/')
        fetched_member_ids[$member_id]=1
    fi
done

# Update data for successfully fetched members
for temp_file in "${temp_files[@]}"; do
    if [[ -f "$temp_file" ]]; then
        # Extract member info from filename
        member_id=$(basename "$temp_file" | sed 's/member_\([0-9]*\)\.json/\1/')
        
        # Find member name by ID
        member_name=""
        for name in "${!TEAM_MEMBERS[@]}"; do
            if [[ "${TEAM_MEMBERS[$name]}" == "$member_id" ]]; then
                member_name="$name"
                break
            fi
        done
        
        if [[ -n "$member_name" ]]; then
            echo "   📋 Processing $member_name (updating with fresh data)..."
            ((processed_members++))
            
            # Remove existing data for this member from all categories first
            for category in "${CATEGORIES[@]}"; do
                category_data_arrays[$category]=$(echo "${category_data_arrays[$category]}" | jq --arg id "$member_id" 'map(select(.id != ($id | tonumber)))')
            done
            
            # Add fresh data for all categories for this member
            categories_found=0
            for category in "${CATEGORIES[@]}"; do
                member_category_data=$(extract_category_data "$temp_file" "$member_name" "$member_id" "$category")
                
                if [[ "$member_category_data" != "null" ]]; then
                    # Add to category data array
                    category_data_arrays[$category]=$(echo "${category_data_arrays[$category]}" | jq --argjson member "$member_category_data" '. + [$member]')
                    ((categories_found++))
                fi
            done
            
            if [[ $categories_found -gt 0 ]]; then
                ((updated_members++))
                echo "      ✓ Updated data for $categories_found categories"
            else
                echo "      ⚠️ No category data found for $member_name"
            fi
        else
            echo "   ⚠️  Unknown member ID: $member_id"
        fi
    fi
done

# Update final member counts
for category in "${CATEGORIES[@]}"; do
    category_member_counts[$category]=$(echo "${category_data_arrays[$category]}" | jq 'length')
done

echo ""
echo "📊 Processing Summary:"
echo "   📥 Members with fresh data: $updated_members"
echo "   📄 Members with preserved data: $(($(echo "$existing_data" | jq -r '.teamMembers // [] | length') - updated_members))"

# Add all category data to combined structure
echo ""
echo "📦 Assembling final data structure..."
for category in "${CATEGORIES[@]}"; do
    combined_data=$(echo "$combined_data" | jq \
        --arg category "$category" \
        --argjson members "${category_data_arrays[$category]}" \
        '.data[$category] = {
            teamMembers: $members,
            memberCount: ($members | length)
        }')
    
    echo "   📊 $category: ${category_member_counts[$category]} members"
done

# Save combined data to single file
output_file="$DATA_DIR/team-data.json"
echo ""
echo "💾 Saving data to $output_file..."
echo "$combined_data" > "$output_file"

# Get file size for logging
if [[ -f "$output_file" ]]; then
    file_size=$(stat -c%s "$output_file" 2>/dev/null || echo "unknown")
    echo "   ✅ File saved successfully (${file_size} bytes)"
else
    echo "   ❌ Failed to save file" >&2
    exit 1
fi

# Clean up temp files
echo ""
echo "🧹 Cleaning up temporary files..."
cleaned_files=0
for temp_file in "${temp_files[@]}"; do
    if [[ -f "$temp_file" ]]; then
        rm -f "$temp_file"
        ((cleaned_files++))
    fi
done
echo "   🗑️  Removed $cleaned_files temporary files"

echo ""
echo "🎉 Data fetch completed successfully at $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo ""
echo "📈 Final Summary:"
echo "   📡 API calls made: $successful_fetches"
echo "   👥 Members with fresh data: $updated_members"
echo "   📄 Total members in dataset: $(echo "$combined_data" | jq '.teamMembers | length')"
echo "   📂 Categories: ${#CATEGORIES[@]} ($(IFS=', '; echo "${CATEGORIES[*]}"))"
echo "   📄 Output file: $output_file"
echo ""
