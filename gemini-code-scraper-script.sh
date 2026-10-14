#!/bin/bash

# Check if a file path was provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <urls_file.txt>"
    exit 1
fi

url_file="$1"

# Check if the file exists
if [ ! -f "$url_file" ]; then
    echo "Error: File '$url_file' not found."
    exit 1
fi

# --- DYNAMIC OUTPUT DIRECTORY LOGIC ---
# 1. Extract just the filename
base_file=$(basename "$url_file")
# 2. Strip the file extension
file_no_ext="${base_file%.*}"
# 3. Construct the directory name
output_dir="${file_no_ext}_outputs"

# Only create the outputs directory if it does not already exist
if [ ! -d "$output_dir" ]; then
    mkdir "$output_dir"
fi

# Initialize the summary file with the current date in the filename
current_date=$(date +%Y-%m-%d)
summary_file="${output_dir}/summary_${current_date}.txt"

echo "Website Change Summary - $(date)" > "$summary_file"
echo "==================================================" >> "$summary_file"

# Read file line-by-line
while IFS= read -r url || [ -n "$url" ]; do
    url=$(echo "$url" | tr -d '\r')
    
    # Skip blank lines and lines starting with '#'
    [[ -z "$url" || "$url" =~ ^[[:space:]]*# ]] && continue

    echo "Fetching: $url"

    # --- URL PARSING LOGIC ---
    url_no_proto="${url#*://}"
    domain="${url_no_proto%%/*}"
    domain_no_tld="${domain%.*}"
    
    if [[ "$url_no_proto" == */* ]]; then
        last_path="${url_no_proto##*/}"
        last_path="${last_path%%\?*}"
    else
        last_path=""
    fi
    
    if [ -n "$last_path" ]; then
        last_path_no_ext=$(echo "$last_path" | sed -E 's/\.[a-zA-Z0-9]{2,5}$//')
        base_name="${domain_no_tld}.${last_path_no_ext}"
    else
        base_name="${domain_no_tld}"
    fi
    # --- END URL PARSING ---

    # Define file paths
    html_file="${output_dir}/${base_name}.html"
    md_file="${output_dir}/${base_name}.md"
    baseline_file="${output_dir}/${base_name}_baseline.md"
    
    # Write header to the summary file before attempting the fetch
    echo -e "\nSource: $base_name" >> "$summary_file"
    echo "----------------------------------------" >> "$summary_file"

    # Fetch HTML, save it, and capture the HTTP status code / exit status
    http_code=$(curl -sSL -w "%{http_code}" -o "$html_file" "$url")
    curl_status=$?

    # Check if curl failed (network/DNS) OR returned an HTTP error (4xx/5xx)
    if [ $curl_status -ne 0 ] || [ "$http_code" -ge 400 ]; then
        error_msg="Error: Fetch failed. HTTP Code: $http_code (Curl Exit Code: $curl_status)"
        
        # Log to terminal
        echo "$error_msg"
        # Log to summary file
        echo "$error_msg" >> "$summary_file"
        
        # Clean up the potentially empty/broken HTML file
        rm -f "$html_file"
        echo "----------------------------------------"
        
        # Skip the rest of this loop iteration and move to the next URL
        continue
    fi

    # Convert HTML to Markdown using pandoc
    pandoc -f html -t markdown "$html_file" -o "$md_file"

    # Check for baseline and run diff
    if [ -f "$baseline_file" ]; then
        # Capture the output of diff
        diff_output=$(diff "$baseline_file" "$md_file")
        
        if [ -z "$diff_output" ]; then
            echo "No changes" >> "$summary_file"
        else
            echo "$diff_output" >> "$summary_file"
        fi
    else
        echo "Initial fetch. No previous baseline exists to compare." >> "$summary_file"
    fi

    # Update the baseline by copying the new markdown file over it
    cp "$md_file" "$baseline_file"

    # Clean up temporary files
    rm -f "$html_file" "$md_file"

    echo "Processed $base_name - Output saved to summary."
    echo "----------------------------------------"
done < "$url_file"

echo "Run complete. Check $summary_file for results."