# Anubis Bypass 𓃩 Part 2

## Background

Not that long ago, I made a script to get around the Anubis WAF for one of my webscrapers (which you can read about [here](/anubis_bypass.md)). While it worked initially, new issues were cropping up, so I knew I needed to make some updates.

I tweaked the code a little, but, notably, noticed that running lines of code as their own commands in the terminal worked, but not when they were included in the script. It also seemed like the cookies were either not being read *or* not working. I was manually navigating to the webpage and exporting them, but there has to be a better way to do so.

## Tasks

In order to make this work better-er, I needed to:

1. Know if/when a cookie is expired
2. Figure out why commands work in the terminal, but not the script
3. Figure out a semi-automated way to get new cookies

## Tools and Hardware

This will be done on my [main machine](/specs.md), utilizing the web version of the Gemini agent. I'll be using the terminal (zsh) and xed (notepad) to run/tweak the script. I'll be using the Vivaldi web browser and the Get cookies.txt LOCALLY browser extension as well.

## Cookie Expiration

While I could give Gemini my whole script and ask it to add stuff in for me, that would be unnesecearry using up my tokens. I only need specific blocks of code that I can make minor tweaks to and then add into my script.

First, I open up my cookie file to figure out what fields are relevant. I need the date (which is in unix time, so I need it to be human readable), and it would be good to have the cookie's name as well. I looked up the standard format for Netscape cookie files to find the names of these fields to better word my prompt.

I'll be having the name of the cookie file elsewhere in the script, so I want to skip any use of arguments. Also, if a cookie is expired, then the rest of the main script won't work right, so the code should exit if that happens.

```
Write Bash code to open a Netscape HTTP Cookie File, look at the expiration date for each entry, and prints a message with the cookie's name if the cookie has expired and exits the script. If the cookie is not expired, print the cookie's name and say it is not expired. The name of the cookie file is hardcoded in the script, it is not passed as an arugment.
```

This produces:

```bash
#!/usr/bin/env bash

# Hardcoded cookie file path
COOKIE_FILE="cookies.txt"

# Check if the file exists
if [[ ! -f "$COOKIE_FILE" ]]; then
    echo "Error: Cookie file '$COOKIE_FILE' not found." >&2
    exit 1
fi

# Get the current Unix timestamp
CURRENT_TIME=$(date +%s)

# Read the file line by line
while IFS=$'\t' read -r domain flag path secure expiration name value || [[ -n "$domain" ]]; do
    # Skip empty lines and comments (including header comments starting with '#')
    [[ -z "$domain" || "$domain" =~ ^# ]] && continue

    # Netscape Cookie Format Fields:
    # 1: domain
    # 2: flag (TRUE/FALSE)
    # 3: path
    # 4: secure (TRUE/FALSE)
    # 5: expiration (Unix timestamp)
    # 6: name
    # 7: value

    # Check if expiration date is past current timestamp
    # Note: Expiration timestamp of 0 means session cookie (never expires during session)
    if (( expiration > 0 && expiration < CURRENT_TIME )); then
        echo "Cookie '$name' HAS EXPIRED."
        exit 0
    else
        echo "Cookie '$name' is NOT EXPIRED."
    fi
done < "$COOKIE_FILE"
```

I download the script as-is, open it to put in the name of the cookie file, `chmod +x` it, and then run it. It prints the expected output...but wouldn't it be more helpful if I tells me *when* it'll expire? Then I'll know when I need to get a new one.

```
Add that, if the cookie is not expired, it prints how many days and hours until the cookie is expired.
```

Which produces:

```bash
#!/usr/bin/env bash

# Hardcoded cookie file path
COOKIE_FILE="cookies.txt"

# Check if the file exists
if [[ ! -f "$COOKIE_FILE" ]]; then
    echo "Error: Cookie file '$COOKIE_FILE' not found." >&2
    exit 1
fi

# Get current Unix timestamp
CURRENT_TIME=$(date +%s)

# Read the file line by line using tab delimiter
while IFS=$'\t' read -r domain flag path secure expiration name value || [[ -n "$domain" ]]; do
    # Skip empty lines and comment lines (starting with '#')
    [[ -z "$domain" || "$domain" =~ ^# ]] && continue

    # Session cookies (expiration = 0) do not have a fixed expiration date
    if (( expiration == 0 )); then
        echo "Cookie '$name' is NOT EXPIRED (Session cookie)."
        continue
    fi

    if (( expiration < CURRENT_TIME )); then
        echo "Cookie '$name' HAS EXPIRED."
        exit 0
    else
        # Calculate time remaining
        diff=$(( expiration - CURRENT_TIME ))
        days=$(( diff / 86400 ))
        hours=$(( (diff % 86400) / 3600 ))

        echo "Cookie '$name' is NOT EXPIRED. Expires in ${days} days, ${hours} hours."
    fi
done < "$COOKIE_FILE"
```

I re-test this, and I get that one of the cookies expires in a week, and another in 0 days and 0 hours...so, it's a very short-lived cookie. And since my goal is to run this once a day first thing in the morning, it means I'll need to get a new cookie before I can run the script each time. Which sucks, but I'll figure out how to do that later. I need to make sure the script *works* first, so that'll be my next task.

I add this output to my main script, with some minor tweaks/rearrangement to make it fit in the greater script.

## Command Debugging

In my testing over the previous week, I figured out a `curl-impersonate` command that always works (assuming the cookies were good). Copying the exact line into the script does not work, so what the heck. So I'll ask Gemini like someone might ask a more experienced programmer:

```
I have the following code to pass a session cookie to bypass the Anubis WAF `curl-impersonate-ff -s -L --location-trusted https://example.com/ -b example_cookies.txt >> today.html`. When I run the code as its own command in the terminal, it successfully bypasses the WAF, but when I run it as part of an .sh script, it can't get past Anubis. Why can this happen, and how can I make it work in an .sh script?
```

It tells me that "This behavior typically occurs due to differences in how commands run inside an interactive shell environment versus a non-interactive script executed by `bash` or `sh`." and gives a 3 part answer.

The first is that either `curl-impersonate-ff` is an alias or that there's an issue with the path. In my terminal I run `which curl-impersonate-ff` to find that it's located at `/usr/local/bin/curl-impersonate-ff`. I edit my script to call that specifically, just in case that's the issue. To check the alias, I also run `alias curl-impersonate-ff`, but get nothing. I use zsh and oh-my-zsh, so a lot of commands are secretly aliases (like `grep` is `grep='grep --color=auto --exclude-dir={.bzr,CVS,.git,.hg,.svn,.idea,.tox,.venv,venv}'`), but that's not the case here.

The second suggestion is that maybe it can't find the cookie because of relative paths. So, to be super-duper-sure this isn't an issue, I edit my script to have the absolute path of the cookie (this ends up being a good choice, for a later change).

Finally, it says that Anubis might be checking the headers/TLS fingerprints that might be different in a shell script vs as a command. However, it does *not* tell me which ones to set, or how. The example code it offers putting all three of these changes together is quite unhelpful. Again, just to be sure, I save my changes to the script, run it, and it doesn't work.

I do recall that, when setting environment variables, you need to export them to make them "permanent" (last longer than that one terminal's session). So let's kill two birds with one stone: have my exact code looked over, and also get the commands on what commands I need to run to set/export the env vars.

```
This is the full bash script that is having the previously mentioned issue. I added the full path for `curl-impersonate-ff`, I added the absolute path of the cookie file, but it still is not working. If there are specific environment variables that I should set to make `curl-impersonate-ff` work in the .sh script, be explicit in which variables I should set, to which values, and how to make them be permanent (and not only lasting for the single terminal session)
```

First, it points out I made some mistakes with the command that I've been running in the terminal to test when I pasted it into the script file. I think I typed over the `-b` flag, so no cookies are being sent, which is causing me issues, of course. I also left in the `today.html` output, which I was using just for testing, when it should have been `"$timestamp".html`. Gemini recognizes that that's the file name being worked on in the rest of the script and surmises (correctly) that this is where it should have been made.

For the env vars, it explains how `curl-impersonate` uses `nss` and/or `gnutls` (which it didn't before), the specific variables that should be set, and code on how to do so:

```bash
# Append to ~/.bashrc
echo 'export LD_LIBRARY_PATH="/usr/local/lib:$LD_LIBRARY_PATH"' >> ~/.bashrc
echo 'export LC_ALL="en_US.UTF-8"' >> ~/.bashrc
echo 'export LANG="en_US.UTF-8"' >> ~/.bashrc

# Apply changes to current session
source ~/.bashrc
```

But, as I'm using zsh, it's `~/.zshrc`, so I tweak the names and run the commands. And, just to be super-duper-sure, I open a new terminal window to do my subsequent test runs of the script.

It does return the full "fixed" script, but I don't need it. Notably, it sets/exports the variables *every time the script is run*, which is absolutely unnesecearry. So I make the two, explicitly-mentioned changes instead of blindly downloading the full script.

When I was doing previous write-ups and doing direct compares of the code to pull out what's been changed, I do notice that it'll make random changes that aren't actually needed. Like adding an `-f` flag to `rm`, deleting its own comments, subtle things that have nothing to do with the actual code that's causing me problems. So, I'm wary of blindly copying the entire file of code.

In this case, it made a subtle change that it does not call out, but makes quite a difference in how the code works. I test my script, and it still fails. Confused, I look at the output file.

What I see is that, as I'm `>>`ing the output, it's appending it to the output file. As the file is today's date, it means it's making 1 file per day and tacking on subsequent `curl`'s outputs. What I use to check if Anubis was bypassed or not (and determining if the rest of the script should run) is `grep`ing a specific line of text that would only be on an Anubis webpage.

So you can see where this is going. If my script fails just once in a day, every subsequent run will come out as failing, because the Anubis page output is in the output file...even if it's pulling everything correctly. I discovered this by opening the output file in Vivaldi, and it was a weirdly formatted series of columns of both Anubis and the target's webpages.

Gemini had (correctly) changed the `>>` to `>`, but didn't mention it. But what if I actually wanted to log every time's output? If I blindly accepted the output, would I even notice that the operator had changed? Luckily, this whole project is small enough that I can notice these changes, but that's not always going to be the case, so this will be important to keep in mind in the future.

But the script works now, hooray! There's just one more part to build, and this should be much easier.

## Getting New Cookies

This one took some thinking before I wrote the prompt. Previously, when I was first trying to find my way around Anubis, I found (and tried) a couple suggested fixes. One was having a C++ program that does the "proof of work", then you POST it to the WAF and get the cookie in return. Honestly, I might try that in the near-future, as my next class is C++, but I don't really need to go *that* far at this point.

Since what I'm doing is already pretty hacky, and this is being done as I start up for the day, I'll be opening up my web browser anyways...so why not just. Open the page for me, then I can wait the second or two for the work to be done, then I can take the 2 clicks to save/export the cookie? That's a good stop gap for now. I'll need it to "wait" until I get the cookie, then I can request the script to continue

```
write a Bash script that opens a hard-coded URL in a web browser window and waits for the user to input a confirmation in the terminal before continuing
```

Which produces:

```bash
#!/usr/bin/env bash

# Hard-coded URL
URL="https://example.com"

# Function to open the URL across Linux, macOS, and WSL/Windows
open_browser() {
    local target_url="$1"
    if command -v xdg-open &>/dev/null; then
        xdg-open "$target_url" &>/dev/null
    elif command -v open &>/dev/null; then
        open "$target_url"
    elif command -v wslview &>/dev/null; then
        wslview "$target_url"
    else
        echo "Could not detect a browser opener. Please manually open: $target_url"
        return 1
    fi
}

echo "Opening URL in your default browser: $URL"
open_browser "$URL"

# Wait for user confirmation in the terminal
echo ""
read -p "Press [ENTER] to confirm and continue script execution (or Ctrl+C to cancel)... " key

# Step verification
echo ""
echo "Confirmation received. Continuing execution..."

# Place the rest of your script logic below
```

I download and test the script, and it works as expected. However, I don't add this to my scraper script, but my startup script. I don't need this to run every time I run the scraper, just the once, so it makes sense to be part of the startup. Also, the site I'm scraping does not like my public IP, so I need to be on my VPN to access it (and get the cookie). The startup script includes connecting to my VPN, so putting it in there makes more sense for the workflow.

But what if I want to be peak lazy...what if I don't want to move the cookie file out of my downloads folder? What if I don't want to delete my previous ones and end up with a bunch?

So I need the script to know the name of the latest (time wise) cookie file I downloaded. It'll always be in the downloads folder, and it'll mostly have the same name, just sometimes have a number if there's dupes. Which is regex I could do, but let's have the AI do it for me:

```
Write Bash code that saves to a local variable the newest file that matches a specific pattern in a specified directory. For example, if I download multiple files named `file.txt`, the default naming for additional files would be `file (1).txt`,`file (2).txt`... I want the name of the file that has the most recent creation date that starts with `file` and ends with `.txt`
```

It gives two versions of this can be done: one using `ls`, and one using `find`. The latter safely handles spaces and special chars, which would be the better choice due to how my distro defaults to naming duplicate files.

I end up making some minor tweaks in the rest of the code, taking advantage of file names being variables, commenting out unnesecearry code, and some general cleanup. I also tweak the text that's printed out to be shorter/funner, because this code is just for me! So it can be silly!

## Full Script Flow

When I open my terminal for the first time in a calendar day, `startup.sh` runs. With this script, it:

1. Prints a greeting based on the time of day
2. `curl`s wttr.in to print today's weather
3. Calls the weather.gov API and prints info about severe/immediate weather warnings/advisories/etc
4. Connects to the VPN and waits 1 second (to give it the chance to connect)
5. Runs my first scraper
6. Opens a browser tab to the URL and waits for me to get the cookie after passing the Anubis challenge
7. Runs the scraper for this one site, which goes:
   1. Finds the name of the latest cookie file in my downloads folder (and prints an error/exits if there's none)
   2. Checks if the individual cookies are expired. If one is, it exists the script. If the cookie is good, it says so and prints how many days/hours are left on it
   3. `curl-impersonate`s the webpage and saves it to a file, named after today's date (and overwrites any previous file, if it exists)
   4. `grep`s the file to see if it's the Anubis page (and exits the scripts if it is)
   5. Converts the html file to Markdown via `pandoc`
   6. Uses `grep`, `cut`, `head`, `wc`, and `sed` to find and cut out the "boring" parts of the file (everything other than the main block of txt I care about)
   7. Checks if a "baseline" file made from running the script previously exists (and, if not, makes today's file the baseline)
   8. Runs `diff` on the two files
   9. Cleans up after itself so only the baseline file remains
8.  Disconnects from the VPN

Altogether, there's 200 lines between these two scripts. And, when I ran it this morning, it worked!

```bash
Good morning! Here's the weather:
      \   /     Sunny
       .-.      64 °F
    ― (   ) ―   ↗ 3 mph
       `-’      6 mi
      /   \     0.0 in

[First scraper heading/results]
[...]

Opening URL...

Press [ENTER] once you got the cookie 🍪𓃩

🍪𓃩  gotted
[Second scraper heading]
Cookie 'techaro.lol-anubis-cookie-verification-XXX' is NOT EXPIRED. Expires in 0 days, 0 hours.
Cookie 'techaro.lol-anubis-auth-XXX' is NOT EXPIRED. Expires in 6 days, 23 hours.
Anubis successfully bypassed 𓃩
[diff output]
```

I can probably tweak the output to make it look nicer, but that's a simple enough fix. The code itself works!

## Caveats

I will not be surprised if Anubis gets further annoyed with me lol, so this is mostly a "here's what I think might happen and how I could keep getting around it" thought experiment.

There might be a way that I can "shuffle" where I'm VPN-ing "from." There might also be some other user agent "fingerprinting" that's happening with `curl-impersonate` that's giving me away. Changing them one at a time might work, but also maybe I could shuffle those options, too. THen having env variables that only last for the session would work well.

There really isn't a way I can make the cookies last longer, from what I understand. I *do* wonder if there's a way that the Anubis cookie can write down information about the browser/session/agent that generated it, so that it can't be passed along with another agent like this. It would probably make the most sense for those values to be encrypted/hashed in such a way that a guy like me can't edit them to match the second agent. But I can probably just fake the `curl` agent to make it match lol. It will be annoying, but it'll be good practice.

There's a lot of ways you can ID a specific user besides their IP address and their cookie And, since those are just bits of data you're sending to a server, you can forge them. I believe there's ways that the servers can read more, harder to forge signals to fingerprint people, like how long it takes requests to happen (because of device hardware specs/speeds). But that would require the server running the WAF to be pretty smart, and I'm not sure something free/open-source like Anubis will be willing/able to do/offer that.

I'll do some more reading on Anubis, including the documentation, to get a better idea of what I'm up against.

## Final Thoughts

Maybe I should suggest to my coworkers that they use Anubis, as I do hear complaints about the cost of Cloudflare. But I should also let them know that if a guy like me can figure out how to get around it, then mass scraping operations probably can, too.

I do wonder how successful Anubis is in reality, though. I know the purpose of it is to increase the computational cost of scraping...but does a company like Facebook or Amazon actually care? I imagine they can weather it, especially if they determine that what's on the other side is quite valuable. Maybe it works better against small to mid size operations? I'm sure someone on LinkedIn knows.