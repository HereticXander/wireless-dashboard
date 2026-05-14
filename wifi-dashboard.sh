#!/bin/bash

# =========================================
# Ultimate Interactive Wi-Fi Dashboard
# =========================================
# Live terminal dashboard for Linux Wi-Fi networks.
# Features:
# - Supports all Wi-Fi standards: a/b/g/n/ac/ax
# - RSSI bars (signal strength)
# - Estimated throughput per AP (fractional channel widths supported)
# - Channel congestion bars
# - Top 3 recommended APs (avoiding DFS)
# - Interactive sorting: s=Signal, t=Throughput, c=Channel Load, q=Quit
# - Live refresh every 10 seconds
# =========================================

# -----------------------------
# Function: estimate_throughput
# Estimate theoretical throughput (Mbps) based on Wi-Fi standard.
# Handles fractional widths and floating-point frequencies safely.
# -----------------------------
estimate_throughput() {
    local standard="$1"
    local mcs="$2"
    local nss="$3"
    local width="$4"
    local freq="$5"

    # Convert frequency to integer for comparisons
    local freq_int=${freq%.*}

    # Handle fractional width: scale by 10 to preserve decimal
    local width_scaled=$(echo "$width * 10 / 1" | bc)

    local est

    if [[ "$standard" == "ax" ]]; then
        # Wi-Fi 6 approximation
        est=$(( 78 * (mcs+1) * nss * width_scaled / (20*10) ))
    elif [[ "$standard" == "ac" ]]; then
        # Wi-Fi 5 approximation
        est=$(( 86 * (mcs+1) * nss * width_scaled / (20*10) ))
    elif [[ "$standard" == "n" ]]; then
        # Wi-Fi 4 approximation
        est=$(( 72 * (mcs+1) * nss * width_scaled / (20*10) ))
    else
        # Legacy a/b/g
        if (( freq_int >= 5000 )); then
            est=54
        else
            est=54
        fi
    fi

    echo $est
}

# -----------------------------
# Detect first wireless interface
# -----------------------------
iface=$(iw dev | awk '/Interface/ {print $2; exit}')
if [ -z "$iface" ]; then
    echo "No wireless interfaces detected. Exiting."
    exit 1
fi

# -----------------------------
# Default sort mode
# -----------------------------
sort_mode="throughput" # options: throughput, rssi, chanload

# -----------------------------
# Function: check for keypresses (interactive sorting)
# -----------------------------
get_sort_key() {
    read -t 0.1 -n 1 key
    case "$key" in
        s) sort_mode="rssi" ;;
        t) sort_mode="throughput" ;;
        c) sort_mode="chanload" ;;
        q) exit 0 ;;
    esac
}

# -----------------------------
# Main live-refresh loop
# -----------------------------
while true; do
    clear
    recommended_done=0

    # -----------------------------
    # Display legend
    # -----------------------------
    echo -e "\033[1;36mUltimate Wi-Fi Dashboard (Interface: $iface)\033[0m"
    echo -e "Colors = Throughput: \033[1;32mHigh\033[0m \033[32mMedium\033[0m \033[33mModerate\033[0m \033[31mLow\033[0m"
    echo -e "RSSI bars = Signal Strength (-100 to -30 dBm) | █ = ~5 dBm"
    echo -e "Channel Load bars = Congestion per channel | ▮ = relative load (Green=Low, Yellow=Med, Red=High)"
    echo -e "Sort: [s]=Signal, [t]=Throughput, [c]=Channel Load, [q]=Quit | Current sort: $sort_mode\n"

    get_sort_key

    # -----------------------------
    # Scan nearby APs using iw
    # -----------------------------
    mapfile -t aps < <(sudo iw dev "$iface" scan 2>/dev/null | awk '
    BEGIN { RS="BSS "; FS="\n" }

    NR>1 { 
        ssid=""; freq=""; width=""; standard="n"; dfs=""; sec=""; rssi=""; mcs=0; nss=1
        
        for (i=1; i<=NF; i++) {
            if ($i ~ /SSID:/)      {sub(/.*SSID: /,"",$i); ssid=$i}
            if ($i ~ /freq:/)      {sub(/.*freq: /,"",$i); freq=$i}
            if ($i ~ /signal:/)    {sub(/.*signal: /,"",$i); rssi=$i}
            if ($i ~ /WPA3/)       {sec="WPA3"}
            else if ($i ~ /RSN/)   {sec="WPA2"}
            else if ($i ~ /WPA /)  {sec="WPA"}

            if ($i ~ /HE Capabilities/) {standard="ax"}
            else if ($i ~ /VHT Capabilities/) {standard="ac"}
            else if ($i ~ /HT Capabilities/) {standard="n"}
        }

        if (ssid != "" && freq != "" && rssi != "") {
            print ssid "\t" freq "\t" rssi "\t" standard "\t" sec
        }
    }')

    # -----------------------------
    # Count APs per channel (channel congestion)
    # -----------------------------
    declare -A channel_counts
    aps_data=()
    for line in "${aps[@]}"; do
        IFS=$'\t' read -r ssid bssid freq width standard dfs sec rssi mcs nss <<< "$line"
        ((channel_counts[$freq]++))
    done

    # -----------------------------
    # Compute estimated throughput and real throughput
    # -----------------------------
    for line in "${aps[@]}"; do
        IFS=$'\t' read -r ssid bssid freq width standard dfs sec rssi mcs nss <<< "$line"
        chan_load=${channel_counts[$freq]}
        est=$(estimate_throughput "$standard" "$mcs" "$nss" "$width" "$freq")
        real_est=$((est / chan_load))
        aps_data+=("$ssid	$bssid	$freq/$width	$standard	$dfs	$sec	$rssi	$est	$chan_load	$real_est")
    done

    # -----------------------------
    # Sort APs based on mode
    # -----------------------------
    case "$sort_mode" in
        rssi) sorted_aps=($(printf '%s\n' "${aps_data[@]}" | sort -nr -k7)) ;;
        throughput) sorted_aps=($(printf '%s\n' "${aps_data[@]}" | sort -nr -k10)) ;;
        chanload) sorted_aps=($(printf '%s\n' "${aps_data[@]}" | sort -n -k9)) ;;
        *) sorted_aps=("${aps_data[@]}") ;;
    esac

    # -----------------------------
    # Display Top 3 Recommended APs
    # -----------------------------
    top_aps=$(printf '%s\n' "${sorted_aps[@]}" | awk 'NR<=3 {print $0}')
    echo -e "========== TOP 3 RECOMMENDED APS =========="
    printf "%-25s %-17s %-12s %-5s %-5s %-9s %-22s %-20s %-9s %-8s\n" \
        "SSID" "BSSID" "Freq/Width" "Std" "DFS" "Sec" "RSSI" "Channel Load" "Est(Mbps)" "RealEst"
    echo "$top_aps" | while IFS=$'\t' read -r ssid bssid freqwidth standard dfs sec rssi est chan_load real_est; do
        rssi_int=$(echo "$rssi" | awk '{print int($1)}')
        freq_int=$(echo "$freq" | awk '{print int($1)}')
        bar_length=$(( (100 + rssi_int) * 20 / 70 ))
        ((bar_length<0)) && bar_length=0
        ((bar_length>20)) && bar_length=20
        rssi_bar=$(printf '█%.0s' $(seq 1 $bar_length))

        max_chan_load=0
        for count in "${channel_counts[@]}"; do (( count > max_chan_load )) && max_chan_load=$count; done
        load_bar_length=$(( chan_load * 20 / max_chan_load ))
        ((load_bar_length>20)) && load_bar_length=20
        load_bar=$(printf '▮%.0s' $(seq 1 $load_bar_length))
        if (( chan_load <= max_chan_load / 3 )); then load_color="\033[1;32m"
        elif (( chan_load <= 2*max_chan_load/3 )); then load_color="\033[33m"
        else load_color="\033[31m"
        fi

        printf "%-25s %-17s %-12s %-5s %-5s %-9s %-22s %-20s %-9s %-8s\n" \
            "$ssid" "$bssid" "$freqwidth" "$standard" "$dfs" "$sec" "$rssi_bar" "$load_colored="${load_color}${load_bar}\033[0m"" "$est" "$real_est"
    done
    echo -e "===========================================\n"

    # -----------------------------
    # Full dashboard table
    # -----------------------------
    echo -e "SSID                     BSSID             Freq/Chan Width  Std   DFS  Sec       RSSI                   Channel Load           Est.Mbps  ChanLoad  RealEst  Recommended"
    echo -e "--------------------------------------------------------------------------------------------------------------------------------------------"

    recommended_done=0
    for entry in "${sorted_aps[@]}"; do
        IFS=$'\t' read -r ssid bssid freqwidth standard dfs sec rssi est chan_load real_est <<< "$entry"
        rssi_int=$(echo "$rssi" | awk '{print int($1)}')
        freq_int=$(echo "$freq" | awk '{print int($1)}')
        bar_length=$(( (100 + rssi_int) * 20 / 70 ))
        ((bar_length<0)) && bar_length=0
        ((bar_length>20)) && bar_length=20
        rssi_bar=$(printf '█%.0s' $(seq 1 $bar_length))

        max_chan_load=0
        for count in "${channel_counts[@]}"; do (( count > max_chan_load )) && max_chan_load=$count; done
        load_bar_length=$(( chan_load * 20 / max_chan_load ))
        ((load_bar_length>20)) && load_bar_length=20
        load_bar=$(printf '▮%.0s' $(seq 1 $load_bar_length))
        if (( chan_load <= max_chan_load / 3 )); then load_color="\033[1;32m"
        elif (( chan_load <= 2*max_chan_load/3 )); then load_color="\033[33m"
        else load_color="\033[31m"
        fi

        # Throughput color
        if (( real_est >= 600 )); then color="\033[1;32m"
        elif (( real_est >= 300 )); then color="\033[32m"
        elif (( real_est >= 150 )); then color="\033[33m"
        else color="\033[31m"
        fi

        rec=""
        if [[ $recommended_done -eq 0 && $dfs != "DFS" ]]; then
            rec="<-- Recommended"
            recommended_done=1
        fi

        printf "%b%-25s %-17s %-12s %-5s %-5s %-22s %-20s %-9s %-8s %s\033[0m\n" \
            "$color" "$ssid" "$bssid" "$freqwidth" "$standard" "$dfs" "$rssi_bar" "$load_colored="${load_color}${load_bar}\033[0m"" "$est" "$real_est" "$rec"
    done

    echo -e "\nPress [s]=Signal, [t]=Throughput, [c]=Channel Load, [q]=Quit | Current sort: $sort_mode"
    sleep 10
done
