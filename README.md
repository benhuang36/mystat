# MyStat

A beautiful and native macOS menu bar app for real-time system monitoring.

## Features
- **CPU**: Real-time CPU usage monitor and chart.
- **Memory**: Tracks memory usage and pressure.
- **Disk**: Shows disk space and read/write speeds.
- **Network**: Displays active network interface throughput.
- **Battery**: Monitors battery level, health, and cycles.
- **Time**: Customizable digital clock for your menu bar.
- **Display**: Quickly adjust display resolution and refresh rate.
- **Stock**: Live Taiwan stock and index quotes (TAIEX, TPEx, listed and OTC symbols) in the menu bar.

### A note on network access
Almost everything MyStat shows is read from local system state. Two features
reach the internet: the Network popover looks up your public IP (ipify, cached
for 5 minutes, only while that popover is open), and **Stock** fetches quotes
from the official TWSE real-time endpoint (`mis.twse.com.tw`).

Stock is the only one that polls on a schedule, so it is deliberately
conservative: it ships **disabled**, and even once enabled it only makes
requests while the Taiwan market is open (Mon–Fri, 09:00–13:30 Taipei time)
and the item is actually on screen. Outside those hours it shows the last
close and makes no requests at all. Nothing about you is sent — the request
carries only the stock codes on your watchlist.

Built entirely with SwiftUI for a modern, fluid user experience.
