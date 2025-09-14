# Ultimate Interactive Wi-Fi Dashboard

An **interactive terminal-based Wi-Fi dashboard** for Linux that scans nearby wireless access points and provides a live, color-coded overview of signal strength, estimated throughput, and channel congestion. Ideal for Wi-Fi site surveys, troubleshooting, and optimizing network performance.

---

## Features

- **Supports all Wi-Fi standards:** a/b/g/n/ac/ax  
- **Live RSSI bars** showing signal strength  
- **Estimated throughput** per AP based on standard, MCS, NSS, and channel width  
- **Channel congestion bars** to visualize crowded channels  
- **Top 3 recommended APs** (avoiding DFS channels when possible)  
- **Interactive sorting:**  
  - `[s]` - Signal strength (RSSI)  
  - `[t]` - Estimated throughput  
  - `[c]` - Channel load  
  - `[q]` - Quit  
- **Live refresh** every 10 seconds  
- **Color-coded display** for quick identification of best APs  

---

## Installation

1. **Clone the repository:**

git clone https://github.com/HereticXander/wifi-dashboard.git
cd wifi-dashboard

---

## Make the script executable:

chmod +x wifi-dashboard.sh

---

## Run the dashboard (requires sudo to scan Wi-Fi):

sudo ./wifi-dashboard.sh

---

## Usage

The script will automatically detect your first wireless interface.

The top section displays a legend explaining colors, RSSI bars, and channel load bars.

Use keys to sort dynamically while the dashboard refreshes:

[s] - Sort by RSSI

[t] - Sort by estimated throughput

[c] - Sort by channel load

[q] - Quit the dashboard

---

## Notes

Designed for terminal use. Best experience on a large terminal window with color support.

DFS channels are avoided for recommended APs if alternatives exist.

Throughput estimations are approximate and based on theoretical Wi-Fi rates.