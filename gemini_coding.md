# genAI Coding

## Background

Every month, I need to check about 20 webpages for their content; the relevant bits of data are stored in a database that I share with a community.

I already have [a single page scraper/comparer tool](https://github.com/ChaseJxyz/website-differ) that I use as part of my daily Bash script that runs once a day when I boot up my computer. So, I could benefit from a version that could work through multiple URLs.

While this was something that I could do myself, why not have an AI tool do it? While I know Google Gemini is *not* the best tool for generating code, it is what I have access to (and I'm already paying for the tokens as part of my cloud subscription).

## Tasks

1. Write a list of requirements
2. Prompt the AI to write the script
3. Test and verify the script

## Tools and Hardware

Once more, this will be done on my [main machine](/specs.md), utilizing the web version of the Gemini agent. I'll be using the terminal (zsh) and xed (notepad) to run/tweak the script.

## Writing Requirements

While I knew exactly what I wanted the code to do from the start, I understood that I should write out the steps so that I can give clear, specific prompts.

I wanted to have it work on the same principles as my prior script, so it would need to:

* Use curl to fetch an HTML file from a given URL
* Convert the HTML to Markdown (to minimize false positives from non-content of a site changing)
* Compare the new Markdown file to a baseline file using `diff`
* Make a new baseline file
* Clean up after itself, leaving only the baseline file

To mass-scan URLs, it would need to:

* Open/read a file of URLs
* Loop through all the URLs, doing all the steps of the prior script
* Generate a name for each baseline file based on the URL

## Prompting

I first wanted to see what I'd get with the most basic version of the request:

```
write a bash script that `curl`s multiple URLs. the URLs are in a separate file, one per line
```

It created a basic script (including the comment to make it run as an .sh)

```bash
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

# Read file line-by-line
while IFS= read -r url || [ -n "$url" ]; do
    # Trim carriage returns (handles files saved on Windows)
    url=$(echo "$url" | tr -d '\r')

    # Skip blank lines and lines starting with '#'
    [[ -z "$url" || "$url" =~ ^[[:space:]]*# ]] && continue

    echo "Fetching: $url"

    # Run curl (-s for silent mode, -L to follow redirects, -f to fail on HTTP errors)
    curl -sSL "$url" -o /dev/null -w "Status: %{http_code} | Time: %{time_total}s\n"

    echo "----------------------------------------"
done < "$url_file"
```

It explained features of the code and what it did, including things I wouldn't have thought about:

* `|| [ -n "$url" ]` to process the last line of the file, even if it didn't end with a newline
* `tr -d '\r'` to remove Windows newlines (which isn't necessary for my machines, but could be for others)
* `[[ -z "$url" || ... ]]` to skip blank and "comment" lines
* Using the `-sSL` flags with curl to hide the progress bar, show errors, and follow HTTP redirects

It also included how to run it, such as using `chmod +x` to give it execute permissions.

This script, though, wouldn't do anything with the output, sending it to the shadow realm of `/dev/null`. I decided to ask a follow up to fix it:

```
How do I modify the script to save the body of each URL to a separate file named after the URL or domain?
```

As you can see, I was still trying to figure out the best way to give prompts. I'll save you from having to look at the whole script again and only post the parts that changed.

```bash
# Directory to store the fetched responses
output_dir="outputs"
mkdir -p "$output_dir"
```

It makes a new directory for the `curl`'d content to go.

```bash
    # Generate a safe filename from the URL
    # 1. Strip protocol (http://, https://)
    # 2. Replace slashes and unsafe characters with underscores
    # 3. Trim any trailing underscore
    clean_name=$(echo "$url" | sed -E 's#^https?://##' | sed -E 's/[^a-zA-Z0-9._-]/_/g' | sed 's/_$//')

    output_path="${output_dir}/${clean_name}.html"
```

It creates a name for each file based on the URL. It would turn `https://example.com` into `example.com.html`.

```bash
    echo "Fetching: $url"

    echo "Saving to: $output_path"
    # Run curl (-s for silent mode, -L to follow redirects, -f to fail on HTTP errors)
    # Fetch and save response body
    # -o: Writes output to specified file
    # -w: Prints status code to console
    curl -sSL "$url" -o /dev/null -w "Status: %{http_code} | Time: %{time_total}s\n"
    curl -sSL "$url" -o "$output_path" -w "Status: %{http_code}\n"
```

It curls each URL  twice; once to (not) print it to the terminal, and once to write it to a file.

So now it creating each file. At this point, I carefully review the code and figure out what changes would need to be made to get the script closer to what I want it to do. I decided to give much more explicit instructions and format it in a way that should work better:

```
Add code that, at the start of the script, creates a summary file that includes the current date.

Add code that does the following for each URL:
- converts the HTML vile that was fetched with curl to a markdown file using pandoc
- check if the output directory has a markdown file named after the domain and includes the word "baseline"
- if there is a baseline file, use diff to show the differences between the new markdown file and the baseline file. write the output to a summary file and the name of the domain. If diff returns no output because there is no difference between the files, print "No changes"
- use cp to copy the new markdown file to a baseline file, replacing the old baseline file
- use rm to delete the earlier markdown file, so all that is left after the script finishes is the baseline files and the summary file.
```

I realized, while writing the prompt, that a "summary" file would be helpful, so that I could review the output in case the terminal closed. I felt it would be best to include it at the start of the prompt, as it needs to be at the start of the script. It would also be outside of the main loop, which is what I used the unordered list for.

I used the unordered list to organize the steps like they would need to go in the prompt for each loop. I referred to my previous script to pull out each step it took, including how it handled being run for the first time and how it cleaned up after itself. I specifically mentioned `diff`, `cp`, and `rm` because I knew they worked and would minimize any confusion that could be caused.

This made a script that was nearly twice the previous length. Here it is in its entirety:

```bash
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

# Directory to store the fetched responses and summary
output_dir="outputs"
mkdir -p "$output_dir"

# Initialize the summary file with the current date
summary_file="${output_dir}/summary.txt"
echo "Website Change Summary - $(date)" > "$summary_file"
echo "==================================================" >> "$summary_file"

# Read file line-by-line
while IFS= read -r url || [ -n "$url" ]; do
    url=$(echo "$url" | tr -d '\r')
    [[ -z "$url" || "$url" =~ ^[[:space:]]*# ]] && continue

    # Extract domain name
    domain=$(echo "$url" | awk -F'[/:]' '{for(i=1;i<=NF;i++) if($i ~ /\./) {print $i; break}}')
    if [ -z "$domain" ]; then
        domain=$(echo "$url" | sed -E 's#^https?://##; s#/.*##')
    fi

    # Define file paths
    html_file="${output_dir}/${domain}.html"
    md_file="${output_dir}/${domain}.md"
    baseline_file="${output_dir}/${domain}_baseline.md"

    echo "Fetching: $url"
    
    # 1. Fetch HTML and save
    curl -sSL "$url" -o "$html_file"

    # 2. Convert HTML to Markdown using pandoc
    # (Extracts the visible text and structure, dropping raw HTML tags)
    pandoc -f html -t markdown "$html_file" -o "$md_file"

    # Write domain header to the summary file
    echo -e "\nDomain: $domain" >> "$summary_file"
    echo "----------------------------------------" >> "$summary_file"

    # 3. Check for baseline and run diff
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

    # 4. Update the baseline by copying the new markdown file
    cp "$md_file" "$baseline_file"

    # 5. Clean up temporary files (HTML and the new Markdown file)
    rm "$html_file" "$md_file"

    echo "Processed $domain - Output saved to summary."
    echo "----------------------------------------"
done < "$url_file"

echo "Run complete. Check $summary_file for results."
```

This looks pretty good, and it included everything I thought to ask it! So now it was time to start testing it.

## Testing

I decided to test it with the list of URLs I would want this to be used on. This included two webpages from the same website (i.e. `example.com/page1` and `example.com/page2`). I knew how many URLs I had, so I knew how many files should be made...but a couple were missing.

I looked at the filenames and the code, and I noticed that it really was only naming the files based on the domains. This means I would only get one `example.com.html.md` file, with the second overwriting the first. I also noticed that it included `.php` in a filename, which was frankly ugly.

I studied the URLs to determine how to word what I wanted. I wrote the prompt:

```
Update the code that names the files fetched from the URLs. If the URL uses has a subdomain, include it in the name. If the URL has text after the final "/", include that in the name. Do not include the top level domain (TLD) or file extensions like ".html" or ".php"
```

I also included 3 examples: one from a site with a more complex URL, a Bluesky post URL, and a URL with no subdomain or `www`.

It ended up creating a codeblock just for this parsing:

```bash
    echo "Fetching: $url"

    # --- URL PARSING LOGIC ---
    
    # 1. Strip protocol (http:// or https://)
    url_no_proto="${url#*://}"
    
    # 2. Extract domain (everything before the first '/')
    domain="${url_no_proto%%/*}"
    
    # 3. Remove the TLD from the domain (removes everything after the last dot)
    domain_no_tld="${domain%.*}"
    
    # 4. Extract text after the final '/'
    # Check if a slash exists in the URL after the domain
    if [[ "$url_no_proto" == */* ]]; then
        last_path="${url_no_proto##*/}"
        # Strip URL query parameters (e.g., ?id=1) just in case
        last_path="${last_path%%\?*}"
    else
        last_path=""
    fi
    
    # 5. Remove file extensions (like .html, .php) and construct the final name
    if [ -n "$last_path" ]; then
        # Use sed to remove typical file extensions (a dot followed by 2-5 letters)
        last_path_no_ext=$(echo "$last_path" | sed -E 's/\.[a-zA-Z0-9]{2,5}$//')
        base_name="${domain_no_tld}.${last_path_no_ext}"
    else
        # Fallback if it's just a root domain (e.g., https://example.com)
        base_name="${domain_no_tld}"
    fi

    # --- END URL PARSING ---

        # Define file paths based on the new naming convention
    html_file="${output_dir}/${base_name}.html"
    md_file="${output_dir}/${base_name}.md"
    baseline_file="${output_dir}/${base_name}_baseline.md"
```

Honestly, I'm very glad to not have to do all this regex by myself! Before I wrote the script again, though, I took a closer look at the summary file.

I noticed the reason that two of the URLs weren't fetched was from different errors. I also noticed that the summary file was just "summary." What if I wanted to keep the files to compare things month over month? So my next prompt was to make the script more useful when I run it more than once:

```
Update the script with the following changes:
- If there is already an "outputs" directory, skip making a new one
- If curl is unable to fetch a webpage, write the error (and HTTP code, if possible) to the summary file and the terminal. Use continue to move to next item in the while loop
- Include the current date in the summary file's filename
```

The first change was a pretty obvious one:

```bash
# 1. Only create the outputs directory if it does not already exist
if [ ! -d "$output_dir" ]; then
    mkdir "$output_dir"
fi
```

After this, it starts cleaning up/deleting its step-by-step comments.

```bash
    # 3. Fetch HTML, save it, and capture the HTTP status code / exit status
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
```

It now moves some stuff around to handle `curl` errors.

It also added the `-f` flag to `rm` when cleaning up the files at the end of the loop. Which, sure! It's really interesting to A/B compare the code and see what little changes it makes, despite not being asked to.

I go back to thinking about my use case. What if I wanted to use this for multiple lists? Instead of having one output folder for everything, shouldn't it be separate for each URL file?

```
Update the code so that the "outputs" directory name includes the name of the URL file

Examples:
- "book_urls.txt" to "book_urls_outputs"
- "funny_urls" to "funny_urls_outputs"
```

Which adds:

```bash
# --- DYNAMIC OUTPUT DIRECTORY LOGIC ---
# 1. Extract just the filename (in case a path like ./folder/book_urls.txt is passed)
base_file=$(basename "$url_file")
# 2. Strip the file extension (removes everything after the last dot)
file_no_ext="${base_file%.*}"
# 3. Construct the directory name
output_dir="${file_no_ext}_outputs"
```

I'm quite happy with it at this point, so I copy/paste the code into the file I've been using to test this and run it again. But now I got an error that didn't happen before!

```
Running the code returns the following error. Please fix it:

line 40: syntax error in conditional expression
line 40: syntax error near `\vert{}\vert{}'
line 40: `    [[ -z "$url" \vert{}\vert{} "$url" =~ ^[[:space:]]*# ]] && continue'
```

Luckily, I did not need to struggle with it for untold hours.

```
This error happens when the logical OR operator (||) gets mangled into \vert{}\vert{} during copy-pasting (often caused by how chat interfaces render certain formatting characters).

To fix it, change that specific line to use two standard pipe characters (||).

Here is the fully corrected script with the proper || formatting. (When you copy this, just double-check that line 40 pastes as || in your text editor):
```

I compare the output of the script with my file, and I see that `\vert{}` made it in there. I do appreciate that there's enough awareness that chat-specific programs could create such an error.

This time, I download the actual .sh file (which you can find [here](\gemini-code-scraper-script.sh)) to copy/paste out of that. I run one final test (to ensure I have the baseline files), check all the output, and consider this complete!

## Caveats

As I was using this in the web version of the chat agent, instead of from the terminal, this was probably not the most efficient way. Change management like git wasn't involved, and this was only one file being changed.

Bash is a language that I'm comfortable with, so I can read the code and know what it's doing and make changes, if needed. I can see if mistakes were made, and I know what I can reasonably ask to be done within the bounds of the language.

This would likely be much faster if it was rewritten in another language, especially a compiled one, but I likely wouldn't be able to follow what the code is doing. My C++ course starts in 2 weeks, and I've never heard Java mentioned when it comes to the speediest languages lol.

But for something with a small number of URLs that I run once a month, while I'm doing lots of other things? It taking a couple seconds is no big deal for me.

My original script also uses regex to cut from the file parts that aren't relevant, like the header and footer. This script does not have that, but it would *also* require me to look at every single website and figure out what it is I'd want to cut out. Again, the number of URLs is pretty small, so I think I'll live with the false positives (especially since converting HTML to Markdown cuts some of it out). I can always further edit the script if needed (and that could make an interesting part 2!)

## Final Thoughts

This was a good introduction in using generative AI for coding. I definitely want to put more practice into this to see what I can do. This also makes me want to learn other, faster languages so I can start prompting code written in those.