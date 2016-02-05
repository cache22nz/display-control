# display-control

OS X Status-bar and CLI utilities for controlling display resolution and mirroring state. Coded in Swift.

While there are good utilities around for controlling display modes, none of them quite met our particular needs. Status-bar utilities were difficult, if not impossible, to deploy in a managed lab environment, and CLI utilities weren't able to set persistent resolutions; so I wrote my own. There are a number of features and tweaks I'd like to add at some point, but the tools are far enough along to do the job we need them to do, so further development isn't a priority right now.

The 1.1.0 branch includes only the status-bar app 'Display Control', while the 2.0.0 branch adds the CLI utility 'displaycontrol'. 'Display Control' isn't functionally much different in 2.0.0, the main change was moving code common to both tools into a separate file.

Both tools are free to use without warranty, expressed or implied. If you find them useful, though, I'd appreciate you letting me know.

I used this project as a vehicle for learning Swift, so any tips or suggestions for improvement will be gratefully accepted

Certain parts of the project, notably the functions for obtaining the correct label for a display, were adapted from Objective-C code found on the web. If I ever find the time to track down those projects again, I'll credit the authors appropriately.


# Quirks

The 'permanent' resolution state set by the CLI tool seems to be set on a per-user basis. If you're running the tool from a login hook, or from a Casper policy, or other similar situation where the command is executed as root, you can use 'sudo -u user displaycontrol -w width -h height -p', where 'user' is the target user account.

The CLI tool throws an error if the shell user executing the command doesn't have a valid Aqua login session (e.g. using a remote ssh connection), unless the account is 'root'.

The 'Display Control' app doesn't have a built-in mechanism for starting at login. You can manually create a LaunchAgent for that purpose, or add it as a per-user login item.
