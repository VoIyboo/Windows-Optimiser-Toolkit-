Quinn Optimiser Toolkit

A modular Windows optimisation and IT utility suite built in PowerShell + WPF.

⚠️ Project Status

The toolkit is actively in development.
V1 and V2 are complete, and V3 is currently being built.
The GitHub repository does not yet contain all features, and many modules are placeholders or under construction.

Please treat the project as an evolving tool rather than a finished product.

🧩 Project Overview

The Quinn Optimiser Toolkit started as a simple Windows cleanup script and has grown into a multi-module, UI-based optimisation suite designed for IT professionals.
It focuses on:

• System cleanups
• Debloating
• App installation & removal
• Windows performance tweaks
• System health dashboards
• Safe/Advanced modes
• Logging
• Modular design for future features

Long-term, the goal is to create an all-in-one IT support utility.

✅ Version Breakdown
V1 – Core Script (Completed)

The first version was a single PowerShell script that performed the basics:

• Clean Windows Update cache
• Clean Delivery Optimisation cache
• Clear temp folders
• WinSxS safe cleanup
• Remove Windows.old (if present)
• Remove crash dumps, memory dumps and logs
• Clean old restore points

V1 had no UI, no modules and no app intelligence.
It was the foundation that proved the idea worked.

V2 – UI + Modular System (Completed)

V2 introduced a full WPF-powered UI and broke the logic into separate modules.
This release focused on usability and structure.

Main changes:

• Tabs for Cleaning, Tweaks, Apps and Advanced
• Checkbox-driven UI
• Logging system
• Risk colour coding (green, amber, red)
• App scanning and uninstall logic
• Basic Windows tweaks
• Loading indicators and better UX
• Modular file layout in preparation for GitHub expansion

V2 is the point where the toolkit became a real application rather than a script.

V3 – Smart Toolkit Upgrade (In Development)

This is the current work in progress.

Key goals for V3:

System Health Dashboard

• CPU, RAM and disk usage
• Largest apps and folders
• Temp size
• Recommended actions

Preset Optimisation Modes

• Safe
• Performance
• Privacy
• Full debloat (Advanced only)

App Intelligence Improvements

• Sort and filter apps
• Last used detection
• Disk impact
• Smarter uninstall recommendations

Theme Support

• Light/dark modes
• Accent colours

Advanced Features

• Startup program optimiser
• Quick action utilities (flush DNS, restart explorer, etc)
• Admin rights checker
• Undo/restore panel
• Optional scheduled maintenance

V3 is focused on making the toolkit smarter, more visual, and closer to a professional IT management tool.

V4 – Imaging & Deployment Module (Planning Stage)

This is a future concept, not yet started.

V4 aims to introduce an advanced IT deployment feature, including:

• Safe Sysprep preparation for reference images
• Capturing Windows installs into WIMs
• Exporting to USB or external media
• Optional deployment guidance using WinPE
• Heavy warnings, admin checks and safe-guards

This module will be explicitly for IT admins, not casual users.

🚧 Important Notes

• The GitHub repo is not complete yet
• Many modules are missing or empty (on purpose)
• UI, structure and folder layout may change
• V3 features are being added gradually
• V4 is future-planned only — nothing implemented yet

Expect breakage, experimental code and ongoing changes.

💡 Contribution / Feedback

This project is currently a solo build.
Feature requests, issues and ideas are welcome once the repo stabilises.
Right now, the priority is completing the V3 foundations.
