# Anubis Bypass 𓃩 Part 3

## Background

I have 2 scrapers that I run each morning (along with a weather checker) when I boot up my computer. [One was in Python](https://github.com/ChaseJxyz/Moksha-Checker) (because I was learning Python at the time I first wrote it) and has had few problems since writing it. [Another was in Bash](https://github.com/ChaseJxyz/website-differ), because I only needed it to do 1 page (though I ended up tweaking it to run multiples...I tanked the speed issue since I only ran the multi version once a month). These were both scraping pages on Moksha[.]io, which is a SaaS for literary submissions.

The page I was scraping with the Bash script must have been quite popular, as the Anubis WAF got added to the "blog" pages specifically. After parts [1](/anubis_bypass.md) and [2](/anubis_2.md), I was able to run it with no issues.

Except for this morning, when the Python checker was failing. When I opened the URLs myself in my web browser, I saw *these* are now behind the WAF, too. Which, I get it. But also these URLs aren't really scrapable/IDOR-able (to my current knowledge. I'm collecting samples to see if the uid is actually random or not...which I think they might not actually be).

To be fair, I did email the Moksha admin/owner about all this before and wanting to explain myself. I know he's working on something that's just the Python checker, but Official and In The Site (which, I guess would require global user accounts? There's only accounts per individual subdomains right now), so the stuff I'm making *is* stuff that people want. But I'm checking way less often than humans who keep mashing F5 to see their submission still hasn't updated.

Up until now, I didn't say "I'm using this on Moksha specifically," but there's no real way around it because I'll be talking about my Moksha checker Python script.

## Tasks

Only one thing this time:

1. Figure out how to get the Python script to pass cookies to get around the WAF

This ends up being multiple steps/thinking, so I'll be breaking sub-headings like that instead of by tasks, like I normally do.

## Tools and Hardware

Same as always: my [main machine](/specs.md) (with a slightly better GPU since the last time I wrote a post), utilizing the web version of the Gemini agent. I'll be using the terminal (zsh) and xed (notepad) to run/tweak the script. I'll be using the Vivaldi web browser and the Get cookies.txt LOCALLY browser extension as well.

## Program Flow

For this to work, I needed to:
1. Get/download the Anubis cookie
2. "Find" the latest cookie in my Downloads folder (so I can be lazy and not need to delete the old ones lol)
3. Test that I can use it to get around Anubis
4. Run the Moksha submission checker (the current Python script)
5. Run the Moksha window checker (the current Bash script)

## To Bash or Python?

I just started my C++ class, and I had to write a paper about the differences between C++ and either Python or Java. I picked Python because it is so different, and I talked about the speed differences. Since my scripts are doing some loops, I believe it's faster in Python than it is Bash.

Also, when I started to draft my first prompt, where I converted the Python script to a Bash one, I looked at my supremely-messy structure (I was reading a file and storing stuff as a dictionary lol), writing out in plain English what the script did was really daunting. It did make me aware of just how not good it was.

But also it's the more complicated of the two scripts. The other one is just running a diff, really, all the hard stuff was passing the cookie over. But there's *gotta* be a way to do that in Python. And I wanted to minimize the chances that Gemini makes changes/breaks my otherwise functional script. Which leads us to the first prompt:

```
Combine these two scripts into a single python script file. This will require re-writing moksha_window_checker.sh's bash code into python code.

Requirements:
- The first action should be getting the latest cookie file in the Downloads folder (lines 11 - 21 from moksha_window_checker.sh)
- It runs the code that's in the moksha_checker.py file. The only update this script needs is that the urlopen needs to pass the cookie file that was found in the previous step. You can change urllib.request.urlopen to another function or library. The URLs will not be able to be read if the cookie file is not passed, passing the cookie when reading the URL is not optional.
- It then runs the rest of the code that's in moksha_window_checker.sh (lines 32 to the end)
```

I decided to be explicit in the files and lines of code to minimize mistakes. I knew the exact steps I needed to be taken, and in what order, so I used line numbers. I also decided to emphasize the need to pass the cookie (otherwise this whole thing will be pointless) and give Gemini permission to change the function I'd been using if necessary.

So the first output was mostly the converting and combining the scripts. Such as:

```python
# =====================================================================
# 1. Get the latest cookie file in the Downloads folder
# =====================================================================
downloads_dir = os.path.expanduser("~/Downloads")
cookie_files = glob.glob(os.path.join(downloads_dir, "moksha.io_cookies*.txt"))

if not cookie_files:
    print("No cookie found. You need a cookie or this doesn't work lol")
    exit(0)

# Sort by modification time (newest first)
cookie_file = max(cookie_files, key=os.path.getmtime)
file_name = os.path.basename(cookie_file)

# =====================================================================
# 2. moksha_checker.py logic with cookie file integration
# =====================================================================
# Build raw cookie header manually to bypass potential cookiejar formatting quirks
cookie_str_parts = []
with open(cookie_file, "r") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) >= 7:
            cookie_str_parts.append(f"{parts[5]}={parts[6].strip()}")

raw_cookie_header = "; ".join(cookie_str_parts)

# Setup global urllib opener to attach cookies to every request
opener = urllib.request.build_opener()
opener.addheaders = [
    ('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'),
    ('Cookie', raw_cookie_header)
]
urllib.request.install_opener(opener)
```

This was a new method of formatting comments. I also noticed it removed most of my comments from my Python script, including ones that explain what the code does.

## Time to Debug

 I tried running it, and got this output:

```bash
Market                   Position       Days      Avg. Days ID            
...........................................................................
                                        -         -    -     *************
                                        -         -    -     *************
                                        -         -    -     *************

--- Running Window Checker ---
techaro.lol-anubis-cookie-verification-[redacted] has EXPIRED.
```

This is what it should look like:

```bash
Market                   Position       Days      Avg. Days ID            
...........................................................................
Uncanny Magazine         In Progress    58        -    -     *************
Castof Wonders           211            39        11  (+28)  *************
Bourbon Penn             Rejected       -         -    -     *************
```

To explain what these pages are: these are submission status pages, which can include the "number in line" you are. For those, it also shows how long an average response takes, so this script records the queue position and tells me if there's been a change since I last ran it (and by how much), plus how above/below the average response time I am. Some markets do not share queue numbers, which means they also do not share average times, so this mostly just tells me it's still active. And rejected ones only show rejected lol.

(There's some other strings for statuses, but you don't need to worry about them. I also have the ID saved in the output file, as that + market name is unique {this is an int that increments by 1 that counts how many submissions a market has had}{the URLs for the status also include a uid, and I've had times where I've submitted twice to the same market, one right after the other, and the uid was the same, only the id different. So the uid isn't actually u.})

I checked the output file, and it also was missing the fields. But also you can see the cookie is expired...and that check was being done *after* I tried to use it. Which is not very helpful.

```
Please make these changes:

- Print the name of the cookie file once it has been found. This must be the cookie file with the latest creation datetime in the Downloads folder.
- Immediately after the previous step, check if the cookies have expired. If one of the cookies is expired, print a message stating which has expired and then exit the script. This is currently farther down in the file, but needs to be earlier.
- Fix the printing to the terminal and writing to the output file so that it prints the market, sub_status, length, avg_length, and day_diff. This worked in the script I supplied, but is broken in the newly generated script.
```

I wanted to ensure the cookie name was the "correct" one, so I got a new one (these last <1 hour, so I had to get them a couple times while working on this + watching the Valkyries game) and took note of its name for my next tests. I had the cookie freshness check moved, and to fix the printing issue. Which, now that I'm writing this out after the fact, is pretty obviously because the cookie was expired.

Turns out it was more than that!

> The issue with the formatting in the previous script was actually tied to the URL fetching method itself. Because the URLs are protected by the Anubis firewall, standard urllib.request was getting blocked and returning empty HTML strings (even when the cookies were being passed). This caused all the regex matches to fail and fall back to blank dashes in your terminal output.
>I've resolved this by swapping out urllib.request with curl-impersonate-ff in the checker loop, utilizing it the exact same way you had it configured in your window checker bash script. This accurately bypasses the firewall so the regexes can grab the actual values again.
>I've also moved the cookie expiration loop to the very top and added the filename printout.

I'm still green when it comes to header/packet forgery, so I didn't know about the URL issue. I ran it with a new cookie, and got:

```bash
File name: moksha.io_cookies (16).txt
techaro.lol-anubis-cookie-verification-[redacted] is GOOD. It expires in 0 days, 0 hours.
techaro.lol-anubis-auth-[redacted] is GOOD. It expires in 6 days, 23 hours.
Market                   Position       Days      Avg. Days ID            
...........................................................................
                                        -         -    -     *************
                                        -         -    -     *************
                                        -         -    -     *************

--- Running Window Checker ---
Anubis successfully bypassed 𓃩
No changes since last check!
```

Okay...so it's clearly not just a cookie problem. The bypass check is checking the scraped blog page to see if it's the actual Moksha site or the Anubis page. If the script fails (for whatever reason), having it later is not helpful, so I'll have to move that, too. But that's something I can just copy/paste myself. What I *need* is the scraper to actually scrape.

```
It is finding the correct cookie file, the cookies are not expired, but it is still not fetching the URL content. Please take a closer look and determine why this could be happening.
```

>The issue you are experiencing comes down to two very specific quirks with how curl handles cookie files and web requests under the hood compared to standard browsers:
>Strict Cookie Domains: Netscape cookie files (like the one you downloaded) enforce strict domain matching. Your output shows the Anubis cookies belong to the domain techaro.lol. When curl-impersonate-ff tries to fetch your moksha.io submission URLs, it sees the domain mismatch and refuses to send the techaro.lol Anubis cookie. Because Anubis doesn't see the clearance cookie, it silently blocks the request and returns the firewall page.
>Compressed Data: curl-impersonate-ff mimics Firefox, meaning it explicitly asks the server to send data compressed (Gzip/Brotli). However, unlike a browser, curl does not decompress it automatically unless you pass the --compressed flag. It was passing raw binary garbage back to Python, which caused the regex matching to fail completely and output blank dashes.
>To fix this, I have updated the script to manually parse the cookie file, extract all the cookies regardless of their domain, and inject them into a raw Cookie: header to force Anubis to accept them. I've also added the --compressed flag and included error-handling so that if Anubis or a Login timeout blocks a URL, it will tell you in the terminal instead of printing blank dashes.

What do you mean "raw binary garbage" lol. This was annoying because my previous shell script was using `curl-impersonate-ff` and I wasn't having any sort of issues with the URLs. I also didn't know about the compression thing, which makes sense as to why Python couldn't work with it.

What was even *more* annoying is that it just threw the code into the chat as-is, so the comments became headers, random chunks are fenced in as actual code, it was a mess! And I'm not going to put up with that.

```
Please take your previous answer and put the code into a .py file. It starts at `#!/usr/bin/env python3`  and ends at the end of your chat message.
```

And it turns it....into an md file 😐️ luckily I just needed to change the extension and it turned into a Python script and could run.

## Human Revisions

When I ran it, I got:

```bash
File name: moksha.io_cookies (16).txt
techaro.lol-anubis-cookie-verification-[redacted] is GOOD. It expires in 0 days, 0 hours.
techaro.lol-anubis-auth-[redacted] is GOOD. It expires in 6 days, 23 hours.
Market                   Position       Days      Avg. Days ID            
...........................................................................
Uncanny Magazine         In Progress    58        -    -     *************
Castof Wonders           211            39        11  (+28)  *************
Bourbon Penn             Rejected       -         -    -     *************

--- Running Window Checker ---
Anubis successfully bypassed 𓃩
No changes since last check!
```

All I really need to do at this point is to reorder some blocks and make the output nice. I remove the file name printout (since it was really just for testing), moved the "did I actually bypass it" check right after the cookies, and made it look nicer with newlines:

```bash
Cookie status:
techaro.lol-anubis-auth-[redacted] is GOOD. It expires in 6 days, 23 hours.
Anubis successfully bypassed 𓃩

Submission status report:

Market                   Position       Days      Avg. Days ID            
...........................................................................
Uncanny Magazine         In Progress    58        -    -     *************
Castof Wonders           211            39        11  (+28)  *************

Open windows report:
No changes since last check!
```

I removed the Bourbon Penn URL from being checked because the rejection wasn't going to change, but otherwise the inputs have all been the same.

My token budget is "whatever comes with my cloud subscription," so asking it just to add a newline or move a chunk of code isn't a good use of my resources. I still like being able to look at the code and know how it works, so I can make these minor tweaks by myself.

## Caveats

I have combined the two checkers into one Python file, as they're checking the same website, but different pages, and in different ways, but they need the same cookie to get through. This works great for my morning startup script, and on days that a lot of submissions happen, like the 1st of the month, but means I'll bec checking the windows page when I want to run just the checker (like after I've made submissions and want a snapshot of where I "started" in line). I absolutely could cut out all the window checking stuff and make just the Moksha checker (which I should do, anyways, to update that repo).

My window checker script, on its own, still works perfectly fine, as does its "check a bunch of pages at once" version. But that doesn't have the cookie passthrough enabled, as I'd need to fetch/send multiple cookies, and that will be a nightmare to do manually. I'll add that once I figure out how to automatically pass the Anubis challenge and skip the me getting the cookie step entirely.

And, of course, Anubis can change how it works (or Moksha can change its configuration) that can break this. But I'll just find another way around it lol. Even if I have to dumb my scripts down and open the webpages in a real web browser, I don't want to manually collect/store/compare the data.

## Final Thoughts

Mr. Moksha, if you're reading this: hi! I have a lot of thoughts about the security of Moksha and how it can be improved! Please answer my email.

If you're not Mr. Moksha: This extended exercise has been teaching me a lot! It's made me better equipped to talk at work about WAFs and scrapers, especially why you can't only throw up a WAF and say it's solved. I am just a guy, I'm no master hacker, and I'm still able to get around stuff. Ginormous companies with essentially infinite compute budgets can tank the proof of work challenges. Of course it's a balance between keeping out the traffic of people who are costing you money/not driving sales vs. letting in the people who want to buy stuff. So what *can* you do? That's the thing I'm working on learning right now