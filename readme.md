Opticon
-------

Opticon is an OSX accessory application that records user input and system event data (similar to a keylogger).
I wrote it for personal computer habit analytics, but I hope that people will find other (benevolent) uses for it.
Unlike malicious keyloggers, Opticon takes some steps to avoid collecting passwords,
in the hopes that the resulting data will be easier to share (see below).
Nevertheless, Opticon collects key, mouse, and application data while it is enabled,
so it is up to the user to protect the resulting database with the appropriate precautions.
OSX full disk encryption is highly recommended.

Opticon also comes with utility to prevent your system password from being recorded due to sudo prompts, called opticon-askpass. See The Usage section below.

###License

Opticon is licensed under the ISC License, a permissive, short license similar to Two-clause BSD.
See license-opticon.txt for more notes.
If you use this software, please send feedback!
If you modify or distribute this software, please cite github.com/gwk/opticon, as well as any intermediate upstream forks.
If you discover somebody using this software for malicious purposes, please notify me immediately.

###Requirements

Opticon is developed on and for OSX 10.9.

###Building Opticon

Currently opticon must be built from source.
Opticon depends on the libqk library, which is included as a git submodule.
Run update-submodules.sh to clone the necessary files.
Note that I currently use github to host the latest built version only of the third party libs,
which means that when the libs change,
dependent projects such as this can no longer simply checkout and build because the refs to the libs will be broken.

###Usage

Simply launch Opticon.app, and it will begin writing event data to ~/Documents/opticon.sqlite.
Use opticon-dump.py (requires Python 3.4) to generate a complete textual dump of the database.
More interesting analytics scripts need to be written; patches are welcome.

If you are a terminal user, you should make use of opticon-askpass to prevent your system password from being recorded at sudo prompts.
To install it, place the opticon-askpass binary somewhere stable, then add the following to your .bashrc / .bash_profile:

    export SUDO_ASKPASS=~/bin/opticon-askpass # or whatever install path you choose.
    alias sudo='sudo -A' # make sudo use SUDO_ASKPASS.

Now, when you invoke sudo, instead of the normal prompt,
you should see the unicode glyph representing the opticon disabled state (⎉).
For more information on SUDO_ASKPASS, read the sudo manpage.

###Details

Opticon uses the CGEventTap API, which requires user authorization, and does not emit events for Cocoa password fields, or any other user interfaces that make correct use of the EnableSecureEventInput API.
This API is documented in HIToolbox/CarbonEventsCore.h.
There is no guarantee that an application uses EnableSecureEventInput correctly,
but it is possible to tell by choosing "Show Keyboard Viewer" from the input sources status item menu
(enabled from System Preferences -> Keyboard -> Input Sources).
If keys highlight when the keyboard viewer is up, then event taps are receiving those key strokes.

###TODO


There are lots of things I would like to add, starting with:
* Fix tooltips, which seem to only display when running from Xcode.
* Simple menu accessed by right-click to display quit item, and tooltip text if the above bug cannot be fixed.
* A website from which to download builds.
* Scripts to simplify the aggregate key, mouse, and scroll events into statistically useful events to reduce privacy risk and facilitate data sharing.
* Scripts to analyze periodic usage, e.g. hours of day and days of week.
* Scripts to analyze usage of key commands by application.
* Scripts that cross-reference opticon events with Chrome browsing history and git logs.
* Application blacklist for apps that should not be recorded, e.g. 1Password, TrueCrypt.

Pull requests are welcome!
